"""Validação de imagem por MAGIC BYTES (não confia no Content-Type do cliente).

O multipart do cliente pode mentir o Content-Type. Antes de subir ao Storage,
farejamos os primeiros bytes e confirmamos que batem com um formato permitido
(JPEG/PNG/WebP). Retornamos o mime DETECTADO (fonte da verdade para extensão e
Content-Type de armazenamento) ou None quando não é uma imagem suportada.
"""


def sniff_image_type(data: bytes) -> str | None:
    """Detecta o tipo real da imagem pelos bytes iniciais.

    Retorna 'image/jpeg' | 'image/png' | 'image/webp', ou None se os bytes não
    correspondem a nenhum formato suportado."""
    if len(data) < 12:
        return None
    # JPEG: FF D8 FF
    if data[0:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    # PNG: 89 50 4E 47 0D 0A 1A 0A
    if data[0:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    # WebP: "RIFF" .... "WEBP"
    if data[0:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return None
