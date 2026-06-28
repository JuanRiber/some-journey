"""Testes do upload de imagem (POST /memories/{id}/image).

No ambiente de teste o Supabase NÃO está configurado, então o caminho feliz
termina em 503 (storage desabilitado) — o suficiente para cobrir wiring,
validação de tipo/tamanho e ownership sem depender de um bucket real.
"""

import uuid

# 1x1 JPEG-ish header bytes (conteúdo não precisa ser uma imagem válida: o
# backend não decodifica — valida pelo content-type e repassa ao Storage).
JPEG_BYTES = b"\xff\xd8\xff\xe0" + b"0" * 64


def _memory(client, headers):
    r = client.post(
        "/memories",
        json={"title": "M", "text": "x", "latitude": 1.0, "longitude": 2.0, "occurred_at": "2026-01-01T00:00:00Z"},
        headers=headers,
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def test_upload_unsupported_type_returns_400(client, auth_headers):
    h = auth_headers()
    mid = _memory(client, h)
    r = client.post(f"/memories/{mid}/image", files={"file": ("x.txt", b"hello", "text/plain")}, headers=h)
    assert r.status_code == 400


def test_upload_empty_file_returns_400(client, auth_headers):
    h = auth_headers()
    mid = _memory(client, h)
    r = client.post(f"/memories/{mid}/image", files={"file": ("x.jpg", b"", "image/jpeg")}, headers=h)
    assert r.status_code == 400


def test_upload_missing_memory_returns_404(client, auth_headers):
    h = auth_headers()
    r = client.post(f"/memories/{uuid.uuid4()}/image", files={"file": ("x.jpg", JPEG_BYTES, "image/jpeg")}, headers=h)
    assert r.status_code == 404


def test_upload_other_users_memory_returns_404(client, auth_headers):
    h1 = auth_headers()
    h2 = auth_headers()
    mid = _memory(client, h1)
    r = client.post(f"/memories/{mid}/image", files={"file": ("x.jpg", JPEG_BYTES, "image/jpeg")}, headers=h2)
    assert r.status_code == 404


def test_upload_too_large_returns_413(client, auth_headers, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "MAX_IMAGE_BYTES", 16)
    h = auth_headers()
    mid = _memory(client, h)
    r = client.post(f"/memories/{mid}/image", files={"file": ("x.jpg", JPEG_BYTES, "image/jpeg")}, headers=h)
    assert r.status_code == 413


def test_upload_valid_type_but_storage_disabled_returns_503(client, auth_headers):
    h = auth_headers()
    mid = _memory(client, h)
    r = client.post(f"/memories/{mid}/image", files={"file": ("x.jpg", JPEG_BYTES, "image/jpeg")}, headers=h)
    assert r.status_code == 503
