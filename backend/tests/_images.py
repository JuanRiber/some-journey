"""Imagens DE VERDADE para os testes de upload.

Os testes mandavam "um JPEG" que era só os quatro primeiros bytes de um,
seguidos de zeros. Bastava enquanto o servidor olhava apenas o começo do
arquivo; desde que ele passou a percorrer a estrutura inteira para tirar os
metadados (app/core/image_metadata.py), um arquivo assim é recusado — como
deve ser. Aqui as imagens são geradas pelo Pillow, que é dependência só de
teste: o servidor continua sem biblioteca de imagem.
"""

from io import BytesIO

from PIL import Image


def _imagem(modo: str = "RGB", tamanho: tuple[int, int] = (12, 8)) -> Image.Image:
    """Uma imagem pequena com conteúdo variado (não uma cor chapada), para que
    "os pixels não mudaram" seja uma afirmação com conteúdo."""
    img = Image.new(modo, tamanho)
    largura, altura = tamanho
    bandas = len(img.getbands())
    img.putdata(
        [
            tuple((x * 21 + y * 13 + b * 57) % 256 for b in range(bandas))
            if bandas > 1
            else (x * 21 + y * 13) % 256
            for y in range(altura)
            for x in range(largura)
        ]
    )
    return img


def encode(formato: str, *, modo: str = "RGB", tamanho=(12, 8), **opcoes) -> bytes:
    """Codifica a imagem de teste. `opcoes` vai direto para `Image.save`."""
    saida = BytesIO()
    _imagem(modo, tamanho).save(saida, formato, **opcoes)
    return saida.getvalue()


def padded_jpeg(tamanho_minimo: int) -> bytes:
    """Um JPEG válido com PELO MENOS `tamanho_minimo` bytes.

    O recheio são segmentos de comentário, logo depois do início: é um arquivo
    que qualquer leitor abre, do tamanho que o teste de limite precisa."""
    base = encode("JPEG")
    recheio = b""
    while len(base) + len(recheio) < tamanho_minimo:
        corpo = b"0" * 65000
        recheio += b"\xff\xfe" + (len(corpo) + 2).to_bytes(2, "big") + corpo
    return base[:2] + recheio + base[2:]


def pixels(dados: bytes) -> tuple[str, tuple[int, int], bytes]:
    """O que a imagem MOSTRA: modo, tamanho e os pixels decodificados."""
    with Image.open(BytesIO(dados)) as img:
        img.load()
        return img.mode, img.size, img.tobytes()


JPEG = encode("JPEG")
PNG = encode("PNG")
WEBP = encode("WEBP", lossless=True)
