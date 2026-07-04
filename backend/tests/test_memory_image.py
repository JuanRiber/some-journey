"""Testes do upload de imagem (POST /memories/{id}/image).

Cobrem wiring, validação de tipo/tamanho e ownership sem depender de um bucket
real. O caminho "storage desabilitado → 503" força as credenciais Supabase a
None no próprio teste, para não depender do que estiver no .env do dev.
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


def test_upload_valid_type_but_storage_disabled_returns_503(client, auth_headers, monkeypatch):
    from app.core.config import settings

    # Força o storage desabilitado independentemente do .env do dev: sem
    # SUPABASE_URL/SERVICE_KEY, storage_enabled=False e o upload responde 503.
    monkeypatch.setattr(settings, "SUPABASE_URL", None)
    monkeypatch.setattr(settings, "SUPABASE_SERVICE_KEY", None)
    h = auth_headers()
    mid = _memory(client, h)
    r = client.post(f"/memories/{mid}/image", files={"file": ("x.jpg", JPEG_BYTES, "image/jpeg")}, headers=h)
    assert r.status_code == 503


def _stub_storage(monkeypatch):
    """Stuba o Storage (sem rede) para exercitar o upload e a remoção felizes."""
    from app.core import storage

    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "upload", lambda *a, **k: None)
    monkeypatch.setattr(storage, "sign_url", lambda *a, **k: "https://signed.example/x")
    monkeypatch.setattr(storage, "delete", lambda *a, **k: None)


def test_delete_image_clears_a_set_image(client, auth_headers, monkeypatch):
    _stub_storage(monkeypatch)
    h = auth_headers()
    mid = _memory(client, h)
    up = client.post(f"/memories/{mid}/image", files={"file": ("x.jpg", JPEG_BYTES, "image/jpeg")}, headers=h)
    assert up.status_code == 200, up.text
    assert up.json()["image_url"] is not None
    # remover a foto salva
    r = client.delete(f"/memories/{mid}/image", headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["image_url"] is None
    # persistiu: o GET não traz mais imagem
    assert client.get(f"/memories/{mid}", headers=h).json()["image_url"] is None


def test_delete_image_is_idempotent_without_image(client, auth_headers):
    h = auth_headers()
    mid = _memory(client, h)
    r = client.delete(f"/memories/{mid}/image", headers=h)
    assert r.status_code == 200
    assert r.json()["image_url"] is None


def test_delete_image_missing_memory_returns_404(client, auth_headers):
    h = auth_headers()
    assert client.delete(f"/memories/{uuid.uuid4()}/image", headers=h).status_code == 404


def test_delete_image_other_users_memory_returns_404(client, auth_headers):
    h1 = auth_headers()
    h2 = auth_headers()
    mid = _memory(client, h1)
    assert client.delete(f"/memories/{mid}/image", headers=h2).status_code == 404
