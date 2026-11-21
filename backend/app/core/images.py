"""Validação de imagem por MAGIC BYTES (não confia no Content-Type do cliente).

O multipart do cliente pode mentir o Content-Type. Antes de subir ao Storage,
farejamos os primeiros bytes e confirmamos que batem com um formato permitido
(JPEG/PNG/WebP). Retornamos o mime DETECTADO (fonte da verdade para extensão e
Content-Type de armazenamento) ou None quando não é uma imagem suportada.

`prepare` é a porta única por onde TODA imagem passa antes de ir para o
Storage — foto de memória, capa de jornada, avatar: detecta o tipo e tira os
metadados (ver image_metadata.py). Subir os bytes como chegaram, sem passar por
ela, é guardar o GPS e o modelo do celular de quem mandou a foto.
"""

from app.core.image_metadata import MalformedImage, strip_metadata


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


def prepare(data: bytes) -> tuple[str, bytes] | None:
    """O que vai para o Storage: (mime detectado, bytes SEM metadados).

    None quando não é uma imagem que aceitamos — tipo não suportado, ou um
    arquivo que diz ser imagem e não tem a estrutura de uma. Os dois casos são
    o mesmo "imagem inválida" para quem chamou: na dúvida a foto é recusada, em
    vez de guardada do jeito que veio."""
    mime = sniff_image_type(data)
    if mime is None:
        return None
    try:
        return mime, strip_metadata(data, mime)
    except MalformedImage:
        return None
