"""A foto sobe sem os metadados — e continua sendo a MESMA foto.

Duas afirmações, e as duas precisam valer juntas:

1. **Nada do que identifica sai junto.** GPS, modelo e número de série do
   aparelho, data, miniatura, XMP, comentário, vídeo colado no fim.
2. **Nenhum pixel muda.** A limpeza copia os compartimentos de imagem byte a
   byte; estes testes decodificam o antes e o depois e comparam os pixels.

As imagens são geradas pelo Pillow (dependência só de teste) com metadados de
verdade. O servidor não usa biblioteca de imagem nenhuma.
"""

import struct
from io import BytesIO

import pytest
from PIL import Image, ImageCms, ImageOps

from app.core import images, storage
from app.core.image_metadata import MalformedImage, strip_metadata
from tests._images import encode, pixels

# O que não pode sobrar em byte nenhum do arquivo limpo.
_APARELHO = "iPhone 15 Pro"
_SERIE = "SERIE-F2LXK0ABCD"
_COMENTARIO = b"tirada na casa da vo, rua tal 123"
_XMP = (
    b'<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?><x:xmpmeta '
    b'xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
    b'<rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/" '
    b'dc:creator="Ana Lima Segredo"/></rdf:RDF></x:xmpmeta><?xpacket end="w"?>'
)
_SEGREDOS = (
    _APARELHO.encode(),
    _SERIE.encode(),
    _COMENTARIO,
    b"Ana Lima Segredo",
    b"xmpmeta",
    b"2026:05:01 14:30:00",
)

_ICC = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()


def _exif(orientacao: int | None = None) -> Image.Exif:
    """Um EXIF de celular: aparelho, data, número de série e GPS."""
    exif = Image.Exif()
    exif[0x010F] = "Apple"
    exif[0x0110] = _APARELHO
    exif[0x0132] = "2026:05:01 14:30:00"
    if orientacao is not None:
        exif[0x0112] = orientacao
    detalhes = exif.get_ifd(0x8769)
    detalhes[0xA431] = _SERIE  # BodySerialNumber
    gps = exif.get_ifd(0x8825)
    gps[1] = "S"
    gps[2] = (3.0, 43.0, 54.84)
    gps[3] = "W"
    gps[4] = (38.0, 31.0, 36.12)
    return exif


def _abrir(dados: bytes) -> Image.Image:
    img = Image.open(BytesIO(dados))
    img.load()
    return img


def _sem_segredos(dados: bytes) -> None:
    for segredo in _SEGREDOS:
        assert segredo not in dados, f"sobrou no arquivo: {segredo!r}"


def _so_orientacao(dados: bytes, esperada: int | None) -> None:
    """O EXIF que sobra tem no máximo UM número: a orientação."""
    exif = _abrir(dados).getexif()
    assert dict(exif) == ({} if esperada is None else {0x0112: esperada})
    assert not exif.get_ifd(0x8825), "sobrou GPS"
    assert not exif.get_ifd(0x8769), "sobrou o bloco de detalhes da câmera"


def _segmento(marker: int, corpo: bytes) -> bytes:
    return bytes((0xFF, marker)) + struct.pack(">H", len(corpo) + 2) + corpo


# --- JPEG -------------------------------------------------------------------


def _jpeg_de_celular(orientacao: int | None = 6, **mais) -> bytes:
    return encode(
        "JPEG",
        exif=_exif(orientacao),
        icc_profile=_ICC,
        comment=_COMENTARIO,
        xmp=_XMP,
        **mais,
    )


def test_o_arranjo_tem_mesmo_o_que_diz_ter():
    """Guarda do próprio teste: se o Pillow parar de gravar algum destes, os
    testes de "não sobrou" passariam sem conferir nada."""
    original = _jpeg_de_celular()
    for segredo in _SEGREDOS:
        assert segredo in original
    assert _abrir(original).getexif().get_ifd(0x8825), "o arranjo ficou sem GPS"


def test_jpeg_sai_sem_gps_aparelho_data_comentario_nem_xmp():
    limpo = strip_metadata(_jpeg_de_celular(), "image/jpeg")

    _sem_segredos(limpo)
    info = _abrir(limpo).info
    assert "comment" not in info and "xmp" not in info


def test_jpeg_limpo_tem_exatamente_os_mesmos_pixels():
    original = _jpeg_de_celular()

    limpo = strip_metadata(original, "image/jpeg")

    assert pixels(limpo) == pixels(original)
    assert len(limpo) < len(original)


def test_a_orientacao_fica_e_e_a_unica_coisa_que_fica():
    """Sem ela, toda foto tirada com o celular em pé apareceria deitada."""
    original = _jpeg_de_celular(orientacao=6)

    limpo = strip_metadata(original, "image/jpeg")

    _so_orientacao(limpo, 6)
    girada_antes = ImageOps.exif_transpose(_abrir(original))
    girada_depois = ImageOps.exif_transpose(_abrir(limpo))
    assert girada_depois.size == girada_antes.size
    assert girada_depois.tobytes() == girada_antes.tobytes()


@pytest.mark.parametrize("orientacao", [2, 3, 4, 5, 6, 7, 8])
def test_toda_orientacao_que_gira_e_preservada(orientacao):
    limpo = strip_metadata(_jpeg_de_celular(orientacao=orientacao), "image/jpeg")
    _so_orientacao(limpo, orientacao)


@pytest.mark.parametrize("orientacao", [None, 1])
def test_foto_que_nao_gira_sai_sem_exif_nenhum(orientacao):
    limpo = strip_metadata(_jpeg_de_celular(orientacao=orientacao), "image/jpeg")

    assert b"Exif" not in limpo
    _so_orientacao(limpo, None)


def test_orientacao_gravada_em_little_endian_tambem_e_lida():
    """O Pillow grava big-endian; muitos celulares gravam little-endian."""
    tiff = (
        b"II\x2a\x00"
        + struct.pack("<I", 8)
        + struct.pack("<H", 2)
        + struct.pack("<HHI", 0x010F, 2, 6)  # Make, ASCII, aponta para longe
        + struct.pack("<I", 38)
        + struct.pack("<HHI", 0x0112, 3, 1)  # Orientation
        + struct.pack("<HH", 8, 0)
        + struct.pack("<I", 0)
        + b"Apple\x00"
    )
    base = encode("JPEG")
    original = base[:2] + _segmento(0xE1, b"Exif\x00\x00" + tiff) + base[2:]

    limpo = strip_metadata(original, "image/jpeg")

    _so_orientacao(limpo, 8)
    assert b"Apple" not in limpo


def test_o_perfil_de_cor_fica():
    """Não identifica ninguém, e sem ele as cores mudam em tela de gama larga."""
    limpo = strip_metadata(_jpeg_de_celular(), "image/jpeg")
    assert _abrir(limpo).info.get("icc_profile") == _ICC


def test_perfil_de_cor_grande_em_varios_segmentos_fica_inteiro():
    grande = _ICC + b"\x00" * 150_000  # força mais de um segmento APP2
    original = encode("JPEG", exif=_exif(6), icc_profile=grande)

    limpo = strip_metadata(original, "image/jpeg")

    assert _abrir(limpo).info.get("icc_profile") == grande
    assert pixels(limpo) == pixels(original)


def test_miniatura_e_imagens_extras_saem():
    """A miniatura do EXIF pode mostrar o enquadramento de ANTES de um corte;
    o JFXX e o MPF são outras duas formas de carregar imagem escondida."""
    miniatura = encode("JPEG", tamanho=(4, 4))
    exif = _exif(6)
    base = encode("JPEG", exif=exif)
    original = (
        base[:2]
        + _segmento(0xE0, b"JFIF\x00\x01\x02\x00\x00\x01\x00\x01\x00\x00")
        + _segmento(0xE0, b"JFXX\x00\x10" + miniatura)
        + _segmento(0xE2, b"MPF\x00" + b"imagem-extra-escondida")
        + _segmento(0xED, b"Photoshop 3.0\x008BIM" + b"legenda-iptc-secreta")
        + base[2:]
    )

    limpo = strip_metadata(original, "image/jpeg")

    for resto in (b"JFXX", b"MPF\x00", b"imagem-extra-escondida", b"8BIM", b"iptc"):
        assert resto not in limpo
    assert limpo.count(b"\xff\xd8") == 1, "sobrou outra imagem dentro do arquivo"
    # Comparado com a imagem de base: o original, com um MPF de mentira, faz o
    # leitor avisar que o arquivo é estranho — e é, de propósito.
    assert pixels(limpo) == pixels(base)
    # O cabeçalho JFIF fica, e o EXIF mínimo vem logo depois dele.
    assert limpo[2:4] == b"\xff\xe0" and limpo[6:11] == b"JFIF\x00"
    _so_orientacao(limpo, 6)


def test_video_colado_depois_do_fim_da_foto_sai():
    """"Foto com movimento": alguns celulares colam um MP4 depois do fim do
    JPEG. Nenhum leitor de imagem mostra, e ele ia junto para o Storage."""
    video = b"\x00\x00\x00\x18ftypmp42" + b"audio-e-video-da-sala" * 200
    original = _jpeg_de_celular() + video

    limpo = strip_metadata(original, "image/jpeg")

    assert limpo.endswith(b"\xff\xd9")
    assert b"ftypmp42" not in limpo and b"audio-e-video" not in limpo
    assert pixels(limpo) == pixels(original)


@pytest.mark.parametrize(
    "opcoes",
    [
        {"progressive": True},
        {"optimize": True},
        {"quality": 30},
        {"quality": 95, "subsampling": 0},
        {"restart_marker_blocks": 1},
        {"progressive": True, "restart_marker_rows": 1},
    ],
    ids=["progressivo", "otimizado", "q30", "q95-444", "reinicio", "progressivo-reinicio"],
)
def test_variantes_de_jpeg_saem_com_os_mesmos_pixels(opcoes):
    original = encode("JPEG", tamanho=(67, 41), exif=_exif(6), comment=_COMENTARIO, **opcoes)

    limpo = strip_metadata(original, "image/jpeg")

    assert pixels(limpo) == pixels(original)
    _sem_segredos(limpo)
    _so_orientacao(limpo, 6)


@pytest.mark.parametrize("modo", ["L", "CMYK"])
def test_jpeg_em_cinza_e_em_cmyk(modo):
    """O CMYK depende do segmento Adobe (APP14) para ser lido com as cores
    certas: é um APPn que TEM de ficar."""
    original = encode("JPEG", modo=modo, exif=_exif(3), comment=_COMENTARIO)

    limpo = strip_metadata(original, "image/jpeg")

    assert pixels(limpo) == pixels(original)
    _sem_segredos(limpo)


def test_limpar_duas_vezes_da_no_mesmo():
    uma = strip_metadata(_jpeg_de_celular(), "image/jpeg")
    assert strip_metadata(uma, "image/jpeg") == uma


def test_foto_sem_metadado_nenhum_sai_igual_nos_pixels():
    original = encode("JPEG")
    assert pixels(strip_metadata(original, "image/jpeg")) == pixels(original)


# --- PNG --------------------------------------------------------------------


def _png_com_tudo(orientacao: int | None = 6, **mais) -> bytes:
    from PIL import PngImagePlugin

    textos = PngImagePlugin.PngInfo()
    textos.add_text("Comment", _COMENTARIO.decode())
    textos.add_text("Software", _APARELHO, zip=True)
    textos.add_itxt("XML:com.adobe.xmp", _XMP.decode())
    return encode(
        "PNG", pnginfo=textos, exif=_exif(orientacao), icc_profile=_ICC, **mais
    )


def test_png_sai_sem_textos_nem_exif_e_com_os_mesmos_pixels():
    original = _png_com_tudo()
    assert b"tEXt" in original and b"iTXt" in original and b"eXIf" in original

    limpo = strip_metadata(original, "image/png")

    for bloco in (b"tEXt", b"zTXt", b"iTXt", b"tIME"):
        assert bloco not in limpo
    _sem_segredos(limpo)
    assert pixels(limpo) == pixels(original)
    assert _abrir(limpo).info.get("icc_profile") == _ICC


def test_png_guarda_so_a_orientacao():
    limpo = strip_metadata(_png_com_tudo(orientacao=6), "image/png")
    _so_orientacao(limpo, 6)


def test_png_que_nao_gira_sai_sem_exif():
    limpo = strip_metadata(_png_com_tudo(orientacao=1), "image/png")
    assert b"eXIf" not in limpo


def test_png_continua_integro_bloco_a_bloco():
    """Cada bloco de PNG tem uma soma de verificação; o `verify` confere todas."""
    limpo = strip_metadata(_png_com_tudo(), "image/png")
    Image.open(BytesIO(limpo)).verify()


@pytest.mark.parametrize("modo", ["RGBA", "P", "L", "LA"])
def test_png_com_transparencia_e_paleta(modo):
    original = encode("PNG", modo=modo, exif=_exif(None))

    limpo = strip_metadata(original, "image/png")

    assert pixels(limpo) == pixels(original)


def test_png_com_dados_depois_do_fim_perde_o_resto():
    original = _png_com_tudo() + b"arquivo-escondido-depois-do-fim" * 50

    limpo = strip_metadata(original, "image/png")

    assert limpo.endswith(b"IEND\xaeB`\x82")
    assert b"arquivo-escondido" not in limpo
    assert pixels(limpo) == pixels(original)


# --- WebP -------------------------------------------------------------------


@pytest.mark.parametrize("sem_perda", [True, False], ids=["sem-perda", "com-perda"])
def test_webp_sai_sem_exif_nem_xmp_e_com_os_mesmos_pixels(sem_perda):
    original = encode(
        "WEBP", lossless=sem_perda, exif=_exif(6), xmp=_XMP, icc_profile=_ICC
    )
    assert b"EXIF" in original and b"XMP " in original

    limpo = strip_metadata(original, "image/webp")

    assert b"XMP " not in limpo
    _sem_segredos(limpo)
    assert pixels(limpo) == pixels(original)
    assert _abrir(limpo).info.get("icc_profile") == _ICC
    _so_orientacao(limpo, 6)


def test_webp_que_nao_gira_sai_sem_exif_e_para_de_anuncia_lo():
    original = encode("WEBP", lossless=True, exif=_exif(1), xmp=_XMP, icc_profile=_ICC)

    limpo = strip_metadata(original, "image/webp")

    assert b"EXIF" not in limpo and b"XMP " not in limpo
    assert limpo[12:16] == b"VP8X"
    flags = limpo[20]
    assert flags & 0x08 == 0 and flags & 0x04 == 0, "o cabeçalho anuncia o que saiu"
    assert flags & 0x20, "o perfil de cor continua lá, e anunciado"


def test_webp_declara_o_tamanho_certo():
    limpo = strip_metadata(
        encode("WEBP", lossless=True, exif=_exif(6), xmp=_XMP), "image/webp"
    )
    assert struct.unpack_from("<I", limpo, 4)[0] == len(limpo) - 8


def test_webp_simples_sem_cabecalho_estendido_passa_inteiro():
    original = encode("WEBP", lossless=False)
    assert original[12:16] != b"VP8X"

    limpo = strip_metadata(original, "image/webp")

    assert pixels(limpo) == pixels(original)


def test_webp_com_transparencia():
    original = encode("WEBP", modo="RGBA", lossless=True, exif=_exif(6))

    limpo = strip_metadata(original, "image/webp")

    assert pixels(limpo) == pixels(original)


def test_webp_animado_guarda_todos_os_quadros():
    quadros = [Image.new("RGB", (8, 8), cor) for cor in ("red", "green", "blue")]
    saida = BytesIO()
    quadros[0].save(
        saida, "WEBP", save_all=True, append_images=quadros[1:], duration=80,
        lossless=True, exif=_exif(None), xmp=_XMP,
    )
    original = saida.getvalue()

    limpo = strip_metadata(original, "image/webp")

    antes, depois = _abrir(original), _abrir(limpo)
    assert depois.n_frames == antes.n_frames == 3
    for i in range(3):
        antes.seek(i)
        depois.seek(i)
        assert depois.convert("RGB").tobytes() == antes.convert("RGB").tobytes()
    _sem_segredos(limpo)


def test_webp_com_lixo_depois_do_tamanho_declarado_perde_o_resto():
    original = encode("WEBP", lossless=True, exif=_exif(6)) + b"escondido" * 40

    limpo = strip_metadata(original, "image/webp")

    assert b"escondido" not in limpo
    assert pixels(limpo) == pixels(original[: -len(b"escondido" * 40)])


# --- arquivo que não dá para percorrer --------------------------------------


@pytest.mark.parametrize(
    ("dados", "mime"),
    [
        (b"\xff\xd8\xff\xe0" + b"0" * 64, "image/jpeg"),  # só o começo de um JPEG
        (encode("JPEG")[:-2], "image/jpeg"),  # sem o marcador de fim
        (encode("JPEG")[:40], "image/jpeg"),  # cortado no meio
        (b"\xff\xd8\xff\xe1\xff\xff" + b"x" * 10, "image/jpeg"),  # tamanho que mente
        (b"\x89PNG\r\n\x1a\n" + b"0" * 64, "image/png"),
        (encode("PNG")[:-12], "image/png"),  # sem o bloco de fim
        (b"RIFF\x10\x00\x00\x00WEBP", "image/webp"),  # sem imagem dentro
        (encode("WEBP")[:30], "image/webp"),
        (encode("JPEG"), "image/gif"),  # tipo que não aceitamos
    ],
    ids=[
        "jpeg-so-o-comeco", "jpeg-sem-fim", "jpeg-cortado", "jpeg-tamanho-falso",
        "png-so-o-comeco", "png-sem-fim", "webp-vazio", "webp-cortado", "tipo-estranho",
    ],
)
def test_arquivo_que_nao_da_para_percorrer_e_recusado(dados, mime):
    with pytest.raises(MalformedImage):
        strip_metadata(dados, mime)


def test_prepare_recusa_em_vez_de_guardar_como_veio():
    assert images.prepare(b"\xff\xd8\xff\xe0" + b"0" * 64) is None
    assert images.prepare(b"isto nao e imagem nenhuma") is None


def test_prepare_devolve_o_tipo_detectado_e_os_bytes_limpos():
    mime, limpo = images.prepare(_jpeg_de_celular())
    assert mime == "image/jpeg"
    _sem_segredos(limpo)


# --- de ponta a ponta: o que chega ao Storage -------------------------------


@pytest.fixture()
def gravados(monkeypatch):
    """Um Storage de mentira que guarda os BYTES que recebeu."""
    recebidos: dict[str, bytes] = {}
    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(
        storage, "upload", lambda path, data, mime: recebidos.__setitem__(path, data)
    )
    monkeypatch.setattr(storage, "delete", lambda *a, **k: None)
    monkeypatch.setattr(storage, "sign_url", lambda path, ttl=None: f"https://s/{path}")
    monkeypatch.setattr(
        storage, "sign_urls", lambda paths, ttl=None: {p: f"https://s/{p}" for p in paths}
    )
    return recebidos


def _memoria(client, h) -> str:
    return client.post(
        "/memories",
        headers=h,
        json={
            "text": "x",
            "latitude": -3.73,
            "longitude": -38.52,
            "occurred_at": "2026-05-01T12:00:00Z",
        },
    ).json()["id"]


def test_a_foto_da_memoria_chega_ao_storage_sem_metadados(
    client, auth_headers, gravados
):
    h = auth_headers()
    original = _jpeg_de_celular()

    r = client.post(
        f"/memories/{_memoria(client, h)}/images",
        headers=h,
        files={"file": ("foto.jpg", original, "image/jpeg")},
    )

    assert r.status_code == 200, r.text
    (guardado,) = gravados.values()
    _sem_segredos(guardado)
    _so_orientacao(guardado, 6)
    assert pixels(guardado) == pixels(original)


def test_o_avatar_chega_ao_storage_sem_metadados(client, auth_headers, gravados):
    h = auth_headers()
    original = _jpeg_de_celular()

    r = client.post(
        "/me/avatar", headers=h, files={"file": ("eu.jpg", original, "image/jpeg")}
    )

    assert r.status_code == 200, r.text
    (guardado,) = gravados.values()
    _sem_segredos(guardado)
    assert pixels(guardado) == pixels(original)


def test_a_capa_da_jornada_chega_ao_storage_sem_metadados(
    client, auth_headers, gravados
):
    h = auth_headers()
    jid = client.post("/journeys", headers=h, json={"title": "Litoral"}).json()["id"]
    original = _png_com_tudo()

    r = client.post(
        f"/journeys/{jid}/cover",
        headers=h,
        files={"file": ("capa.png", original, "image/png")},
    )

    assert r.status_code == 200, r.text
    (guardado,) = gravados.values()
    _sem_segredos(guardado)
    assert pixels(guardado) == pixels(original)


def test_imagem_que_nao_da_para_limpar_nao_chega_ao_storage(
    client, auth_headers, gravados
):
    """Na dúvida, recusa: o arquivo que não conseguimos percorrer é justamente
    o que não podemos guardar do jeito que veio."""
    h = auth_headers()
    cortada = _jpeg_de_celular()[:-2]

    r = client.post(
        f"/memories/{_memoria(client, h)}/images",
        headers=h,
        files={"file": ("foto.jpg", cortada, "image/jpeg")},
    )

    assert r.status_code == 400
    assert gravados == {}


def test_nenhum_upload_sobe_sem_passar_pela_limpeza():
    """Guarda de estrutura: os serviços chamam `storage.upload` com o que saiu
    de `images.prepare`. Um upload novo que use `sniff_image_type` direto
    guardaria a foto com tudo dentro."""
    from pathlib import Path

    servicos = Path(__file__).resolve().parents[1] / "app" / "services"
    for arquivo in servicos.glob("*.py"):
        fonte = arquivo.read_text(encoding="utf-8")
        if "storage.upload(" not in fonte:
            continue
        assert "images.prepare(" in fonte, f"{arquivo.name} sobe arquivo sem limpar"
        assert "= images.sniff_image_type(" not in fonte, (
            f"{arquivo.name} detecta o tipo e sobe os bytes como chegaram"
        )
