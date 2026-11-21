"""Tira os metadados de uma foto SEM mexer na foto.

Uma foto de celular carrega muito além da imagem: as coordenadas de onde foi
tirada, o modelo e às vezes o número de série do aparelho, a data e a hora, um
rascunho em miniatura (que pode mostrar o enquadramento ANTES de um corte) e,
em alguns aparelhos, um vídeo inteiro colado depois do fim do arquivo. Nada
disso aparece na tela, e tudo isso ia para o nosso Storage junto com a imagem.

O lugar onde a pessoa disse que a memória aconteceu é o que ela escolheu no
mapa — e está no banco. O que o sensor do celular anotou por conta própria não
foi escolha de ninguém, e não é nosso para guardar.

**Sem recodificar.** Os três formatos aceitos (JPEG, PNG, WebP) são caixas com
compartimentos: uns guardam a imagem, outros guardam anotações. Aqui a caixa é
aberta, os compartimentos de imagem são copiados byte a byte, e os de anotação
ficam de fora. A imagem que sai é a MESMA — nenhum pixel muda, nenhuma
qualidade se perde — e o servidor não precisa de biblioteca de imagem, nem
decodifica nada que um arquivo malicioso pudesse explorar.

**O que fica**, porque sem isso a foto aparece errada:

- o perfil de cor (ICC) e os compartimentos de cor do PNG/WebP;
- a ORIENTAÇÃO. O celular grava a foto "deitada" e anota "gire ao mostrar"; essa
  anotação mora no EXIF, junto do GPS. O EXIF sai inteiro e, no lugar, entra
  um EXIF mínimo com esse único número — senão toda foto em pé apareceria de
  lado.

**O que sai**: EXIF (GPS, aparelho, data, miniatura), XMP, IPTC, comentários,
miniaturas JFXX, imagens extras (MPF) e qualquer coisa depois do fim da imagem.

**Na dúvida, recusa.** Um arquivo cuja estrutura não dá para percorrer levanta
`MalformedImage`, e o upload é recusado. Guardar "como veio" seria o caminho
fácil — e deixaria passar justamente o arquivo que não conseguimos limpar.
"""

from __future__ import annotations

import struct
import zlib


class MalformedImage(ValueError):
    """A estrutura do arquivo não pôde ser percorrida até o fim."""


def strip_metadata(data: bytes, mime: str) -> bytes:
    """Devolve a mesma imagem, sem metadados. `mime` é o tipo JÁ detectado
    (`images.sniff_image_type`). Levanta `MalformedImage` se o arquivo não
    tem a estrutura do formato que diz ter."""
    try:
        if mime == "image/jpeg":
            return _strip_jpeg(data)
        if mime == "image/png":
            return _strip_png(data)
        if mime == "image/webp":
            return _strip_webp(data)
    except (IndexError, struct.error) as exc:
        # Leitura além do fim: arquivo cortado ou com um tamanho que mente.
        raise MalformedImage(str(exc)) from exc
    raise MalformedImage(f"tipo não suportado: {mime}")


# --- orientação (o único número do EXIF que fica) ---------------------------

_ORIENTATION_TAG = 0x0112


def _read_orientation(tiff: bytes) -> int | None:
    """A orientação gravada num bloco TIFF (o miolo do EXIF), ou None.

    Lê só o primeiro diretório, que é onde ela mora. Qualquer coisa fora do
    esperado devolve None: a foto perde a anotação de giro, o que é um defeito
    de exibição — bem menor do que confiar num bloco que não entendemos."""
    if len(tiff) < 8:
        return None
    if tiff[:2] == b"II":
        ordem = "<"
    elif tiff[:2] == b"MM":
        ordem = ">"
    else:
        return None
    if struct.unpack_from(ordem + "H", tiff, 2)[0] != 42:
        return None
    inicio = struct.unpack_from(ordem + "I", tiff, 4)[0]
    if inicio + 2 > len(tiff):
        return None
    entradas = struct.unpack_from(ordem + "H", tiff, inicio)[0]
    for i in range(entradas):
        pos = inicio + 2 + i * 12
        if pos + 12 > len(tiff):
            return None
        tag, tipo, quantos = struct.unpack_from(ordem + "HHI", tiff, pos)
        if tag == _ORIENTATION_TAG:
            if tipo != 3 or quantos != 1:  # SHORT, um valor
                return None
            valor = struct.unpack_from(ordem + "H", tiff, pos + 8)[0]
            return valor if 1 <= valor <= 8 else None
    return None


def _orientation_tiff(orientation: int) -> bytes:
    """Um bloco TIFF com UMA entrada: a orientação. É o EXIF mínimo."""
    return (
        b"MM\x00\x2a"  # big-endian, número mágico do TIFF
        + struct.pack(">I", 8)  # o diretório começa logo depois do cabeçalho
        + struct.pack(">H", 1)  # uma entrada
        + struct.pack(">HHI", _ORIENTATION_TAG, 3, 1)  # tag, SHORT, um valor
        + struct.pack(">HH", orientation, 0)  # o valor, alinhado à esquerda
        + struct.pack(">I", 0)  # não há próximo diretório
    )


def _needs_rotation(orientation: int | None) -> bool:
    """1 é "do jeito que está": não há o que anotar."""
    return orientation is not None and orientation != 1


# --- JPEG --------------------------------------------------------------------

_EXIF_PREFIX = b"Exif\x00\x00"

# Marcadores sem corpo: os de reinício (RST0..RST7) e o TEM.
_JPEG_STANDALONE = frozenset(range(0xD0, 0xD8)) | {0x01}


def _jpeg_keeps(marker: int, body: bytes) -> bool:
    """Este segmento é parte da imagem (fica) ou é anotação (sai)?"""
    if marker == 0xE0:  # APP0: o cabeçalho JFIF fica; a miniatura JFXX sai
        return body.startswith(b"JFIF\x00")
    if marker == 0xE2:  # APP2: o perfil de cor fica; MPF e FlashPix saem
        return body.startswith(b"ICC_PROFILE\x00")
    if marker == 0xEE:  # APP14: diz ao decodificador como ler as cores
        return body.startswith(b"Adobe")
    if 0xE1 <= marker <= 0xEF:  # os outros APPn: EXIF, XMP, IPTC, de fabricante
        return False
    if marker == 0xFE:  # COM: comentário
        return False
    return True  # tabelas, cabeçalho de quadro e de varredura: a imagem


def _strip_jpeg(data: bytes) -> bytes:
    if data[:2] != b"\xff\xd8":
        raise MalformedImage("JPEG sem marcador de início")
    partes: list[bytes] = []
    orientation: int | None = None
    pos = 2
    fim = len(data)
    while True:
        if pos >= fim:
            raise MalformedImage("JPEG sem marcador de fim")
        if data[pos] != 0xFF:
            raise MalformedImage("JPEG: esperava um marcador")
        # Bytes FF de preenchimento antes do marcador são permitidos.
        while data[pos] == 0xFF:
            pos += 1
        marker = data[pos]
        pos += 1

        if marker == 0xD9:  # EOI: a imagem acabou. O que vier depois não entra.
            break
        if marker in _JPEG_STANDALONE:
            partes.append(bytes((0xFF, marker)))
            continue

        tamanho = struct.unpack_from(">H", data, pos)[0]
        if tamanho < 2 or pos + tamanho > fim:
            raise MalformedImage("JPEG: segmento com tamanho inválido")
        corpo = data[pos + 2 : pos + tamanho]
        segmento = data[pos - 2 : pos + tamanho]
        pos += tamanho

        if marker == 0xE1 and corpo.startswith(_EXIF_PREFIX) and orientation is None:
            orientation = _read_orientation(corpo[len(_EXIF_PREFIX) :])
        if not _jpeg_keeps(marker, corpo):
            continue
        partes.append(b"\xff" + bytes((marker,)) + segmento[2:])

        if marker == 0xDA:  # SOS: depois do cabeçalho vêm os dados comprimidos
            inicio = pos
            pos = _jpeg_scan_end(data, pos)
            partes.append(data[inicio:pos])

    if _needs_rotation(orientation):
        corpo = _EXIF_PREFIX + _orientation_tiff(orientation)  # type: ignore[arg-type]
        exif = b"\xff\xe1" + struct.pack(">H", len(corpo) + 2) + corpo
        # Depois do JFIF, que por norma é o primeiro segmento.
        onde = 1 if partes and partes[0][:2] == b"\xff\xe0" else 0
        partes.insert(onde, exif)
    return b"\xff\xd8" + b"".join(partes) + b"\xff\xd9"


def _jpeg_scan_end(data: bytes, pos: int) -> int:
    """Onde terminam os dados comprimidos que começam em `pos`.

    Dentro deles, FF só é marcador de verdade quando NÃO vem seguido de 00
    (byte "recheado") nem de um marcador de reinício — esses fazem parte dos
    dados. O primeiro FF seguido de outra coisa é o próximo segmento."""
    fim = len(data)
    while True:
        pos = data.find(b"\xff", pos)
        if pos < 0 or pos + 1 >= fim:
            raise MalformedImage("JPEG: dados da imagem sem fim")
        seguinte = data[pos + 1]
        if seguinte == 0x00 or 0xD0 <= seguinte <= 0xD7 or seguinte == 0xFF:
            pos += 1 if seguinte == 0xFF else 2
            continue
        return pos


# --- PNG ---------------------------------------------------------------------

_PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

# Blocos opcionais que mudam COMO a imagem aparece: cor, transparência,
# proporção do pixel e animação. Todo o resto que é opcional é anotação.
_PNG_KEEP_ANCILLARY = frozenset(
    {
        b"tRNS", b"gAMA", b"cHRM", b"sRGB", b"iCCP", b"sBIT", b"bKGD", b"pHYs",
        b"hIST", b"sPLT", b"cICP", b"mDCV", b"cLLI",
        b"acTL", b"fcTL", b"fdAT",
    }
)  # fmt: skip


def _png_chunk(tipo: bytes, corpo: bytes) -> bytes:
    crc = zlib.crc32(tipo + corpo) & 0xFFFFFFFF
    return struct.pack(">I", len(corpo)) + tipo + corpo + struct.pack(">I", crc)


def _strip_png(data: bytes) -> bytes:
    if data[:8] != _PNG_SIGNATURE:
        raise MalformedImage("PNG sem assinatura")
    partes: list[bytes] = [_PNG_SIGNATURE]
    orientation: int | None = None
    exif_em: int | None = None
    pos = 8
    fim = len(data)
    while True:
        if pos + 12 > fim:
            raise MalformedImage("PNG sem bloco de fim")
        tamanho = struct.unpack_from(">I", data, pos)[0]
        tipo = data[pos + 4 : pos + 8]
        total = 12 + tamanho
        if pos + total > fim:
            raise MalformedImage("PNG: bloco com tamanho inválido")
        corpo = data[pos + 8 : pos + 8 + tamanho]
        bloco = data[pos : pos + total]
        pos += total

        # A primeira letra maiúscula marca um bloco ESSENCIAL: sem ele o
        # decodificador não lê a imagem. Esses ficam sempre, conhecidos ou não.
        essencial = not (tipo[0] & 0x20)
        if tipo == b"eXIf":
            orientation = _read_orientation(corpo)
            exif_em = len(partes)
        elif essencial or tipo in _PNG_KEEP_ANCILLARY:
            partes.append(bloco)
        if tipo == b"IEND":
            break  # o que vier depois não entra

    if _needs_rotation(orientation) and exif_em is not None:
        partes.insert(exif_em, _png_chunk(b"eXIf", _orientation_tiff(orientation)))  # type: ignore[arg-type]
    return b"".join(partes)


# --- WebP --------------------------------------------------------------------

# Os blocos que desenham: cabeçalho estendido, cor, transparência, animação e
# os dois codecs. EXIF e XMP são os de anotação; o desconhecido também sai.
_WEBP_KEEP = frozenset(
    {b"VP8X", b"ICCP", b"ANIM", b"ANMF", b"ALPH", b"VP8 ", b"VP8L"}
)
_WEBP_FLAG_EXIF = 0x08
_WEBP_FLAG_XMP = 0x04


def _strip_webp(data: bytes) -> bytes:
    if data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        raise MalformedImage("WebP sem cabeçalho")
    declarado = struct.unpack_from("<I", data, 4)[0]
    # O tamanho declarado manda: o que estiver depois dele não é do arquivo.
    fim = min(len(data), 8 + declarado)
    partes: list[bytes] = []
    orientation: int | None = None
    pos = 12
    while pos + 8 <= fim:
        tipo = data[pos : pos + 4]
        tamanho = struct.unpack_from("<I", data, pos + 4)[0]
        if pos + 8 + tamanho > fim:
            raise MalformedImage("WebP: bloco com tamanho inválido")
        corpo = data[pos + 8 : pos + 8 + tamanho]
        pos += 8 + tamanho + (tamanho & 1)  # blocos são alinhados a 2 bytes

        if tipo == b"EXIF":
            # Alguns gravadores repetem aqui o prefixo do JPEG; outros não.
            tiff = corpo[len(_EXIF_PREFIX) :] if corpo.startswith(_EXIF_PREFIX) else corpo
            orientation = _read_orientation(tiff)
        elif tipo in _WEBP_KEEP:
            partes.append(_webp_chunk(tipo, corpo))
    if not partes:
        raise MalformedImage("WebP sem imagem")

    manter_exif = _needs_rotation(orientation) and partes[0][:4] == b"VP8X"
    if partes[0][:4] == b"VP8X":
        # O cabeçalho estendido anuncia o que o arquivo traz: tem de parar de
        # anunciar o que saiu.
        cabecalho = bytearray(partes[0])
        flags = cabecalho[8] & ~_WEBP_FLAG_XMP
        flags = flags | _WEBP_FLAG_EXIF if manter_exif else flags & ~_WEBP_FLAG_EXIF
        cabecalho[8] = flags
        partes[0] = bytes(cabecalho)
    if manter_exif:
        partes.append(_webp_chunk(b"EXIF", _orientation_tiff(orientation)))  # type: ignore[arg-type]

    corpo_total = b"WEBP" + b"".join(partes)
    return b"RIFF" + struct.pack("<I", len(corpo_total)) + corpo_total


def _webp_chunk(tipo: bytes, corpo: bytes) -> bytes:
    return tipo + struct.pack("<I", len(corpo)) + corpo + (b"\x00" if len(corpo) & 1 else b"")
