"""Testes das fotos da memória (POST /memories/{id}/images e
DELETE /memories/{id}/images/{image_id}).

Cobrem validação de tipo/tamanho, ownership, o teto de fotos e a remoção. O
caminho "storage desabilitado -> 503" força as credenciais Supabase a None.
"""

import uuid

import pytest

# Cabeçalhos com MAGIC BYTES reais (o backend valida pelos bytes, não pelo
# Content-Type do multipart): JPEG começa com FF D8 FF; PNG com 89 50 4E 47...
JPEG_BYTES = b"\xff\xd8\xff\xe0" + b"0" * 64
PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"0" * 64


def _memory(client, headers):
    r = client.post(
        "/memories",
        json={"title": "M", "text": "x", "latitude": 1.0, "longitude": 2.0, "occurred_at": "2026-01-01T00:00:00Z"},
        headers=headers,
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _stub_storage(monkeypatch):
    """Stuba o Storage (sem rede): upload no-op, assinatura fake, delete no-op."""
    from app.core import storage

    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "upload", lambda *a, **k: None)
    monkeypatch.setattr(storage, "sign_urls", lambda paths, ttl=None: {p: f"https://signed/{p}" for p in paths})
    monkeypatch.setattr(storage, "delete", lambda *a, **k: None)


def _add(client, headers, mid):
    return client.post(
        f"/memories/{mid}/images",
        files={"file": ("x.jpg", JPEG_BYTES, "image/jpeg")},
        headers=headers,
    )


# --- validação (antes de tocar no storage) ---------------------------------
def test_add_unsupported_type_returns_400(client, auth_headers):
    h = auth_headers()
    mid = _memory(client, h)
    r = client.post(f"/memories/{mid}/images", files={"file": ("x.txt", b"hello", "text/plain")}, headers=h)
    assert r.status_code == 400


def test_add_empty_file_returns_400(client, auth_headers):
    h = auth_headers()
    mid = _memory(client, h)
    r = client.post(f"/memories/{mid}/images", files={"file": ("x.jpg", b"", "image/jpeg")}, headers=h)
    assert r.status_code == 400


def test_add_missing_memory_returns_404(client, auth_headers):
    h = auth_headers()
    r = client.post(f"/memories/{uuid.uuid4()}/images", files={"file": ("x.jpg", JPEG_BYTES, "image/jpeg")}, headers=h)
    assert r.status_code == 404


def test_add_other_users_memory_returns_404(client, auth_headers):
    h1 = auth_headers()
    h2 = auth_headers()
    mid = _memory(client, h1)
    r = client.post(f"/memories/{mid}/images", files={"file": ("x.jpg", JPEG_BYTES, "image/jpeg")}, headers=h2)
    assert r.status_code == 404


def test_add_too_large_returns_413(client, auth_headers, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "MAX_IMAGE_BYTES", 16)
    h = auth_headers()
    mid = _memory(client, h)
    r = _add(client, h, mid)
    assert r.status_code == 413


def test_add_storage_disabled_returns_503(client, auth_headers, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "SUPABASE_URL", None)
    monkeypatch.setattr(settings, "SUPABASE_SERVICE_KEY", None)
    h = auth_headers()
    mid = _memory(client, h)
    r = _add(client, h, mid)
    assert r.status_code == 503


# --- múltiplas fotos --------------------------------------------------------
def test_add_up_to_five_then_reject_sixth(client, auth_headers, monkeypatch):
    _stub_storage(monkeypatch)
    h = auth_headers()
    mid = _memory(client, h)
    for i in range(5):
        r = _add(client, h, mid)
        assert r.status_code == 200, r.text
        assert len(r.json()["images"]) == i + 1
    # a sexta estoura o teto -> 409
    assert _add(client, h, mid).status_code == 409


def test_remove_one_image(client, auth_headers, monkeypatch):
    _stub_storage(monkeypatch)
    h = auth_headers()
    mid = _memory(client, h)
    _add(client, h, mid)
    body = _add(client, h, mid).json()
    assert len(body["images"]) == 2
    img_id = body["images"][0]["id"]
    r = client.delete(f"/memories/{mid}/images/{img_id}", headers=h)
    assert r.status_code == 200, r.text
    remaining = [i["id"] for i in r.json()["images"]]
    assert img_id not in remaining
    assert len(remaining) == 1


def test_remove_missing_image_returns_404(client, auth_headers):
    h = auth_headers()
    mid = _memory(client, h)
    r = client.delete(f"/memories/{mid}/images/{uuid.uuid4()}", headers=h)
    assert r.status_code == 404


def test_remove_other_users_image_returns_404(client, auth_headers, monkeypatch):
    _stub_storage(monkeypatch)
    h1 = auth_headers()
    h2 = auth_headers()
    mid = _memory(client, h1)
    img_id = _add(client, h1, mid).json()["images"][0]["id"]
    r = client.delete(f"/memories/{mid}/images/{img_id}", headers=h2)
    assert r.status_code == 404


# --- validação por MAGIC BYTES (não confia no Content-Type) -----------------
def test_add_lying_content_type_rejected_by_magic_bytes(client, auth_headers, monkeypatch):
    """Content-Type diz image/jpeg mas os bytes NÃO são imagem -> 400. A decisão
    é pelos bytes farejados, não pelo header mentiroso do cliente."""
    _stub_storage(monkeypatch)
    h = auth_headers()
    mid = _memory(client, h)
    r = client.post(
        f"/memories/{mid}/images",
        files={"file": ("x.jpg", b"this is plainly not an image payload", "image/jpeg")},
        headers=h,
    )
    assert r.status_code == 400


def test_detected_type_overrides_client_content_type(client, auth_headers, monkeypatch):
    """Content-Type mente 'text/plain' mas os bytes são PNG: aceito, e tanto a
    extensão do path quanto o Content-Type gravado no Storage vêm do DETECTADO."""
    from app.core import storage

    captured: dict[str, str] = {}

    def fake_upload(path, data, content_type):
        captured["path"] = path
        captured["content_type"] = content_type

    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "upload", fake_upload)
    monkeypatch.setattr(
        storage, "sign_urls", lambda paths, ttl=None: {p: f"https://signed/{p}" for p in paths}
    )
    monkeypatch.setattr(storage, "delete", lambda *a, **k: None)

    h = auth_headers()
    mid = _memory(client, h)
    r = client.post(
        f"/memories/{mid}/images",
        files={"file": ("x.bin", PNG_BYTES, "text/plain")},
        headers=h,
    )
    assert r.status_code == 200, r.text
    assert captured["content_type"] == "image/png"
    assert captured["path"].endswith(".png")


# --- rollback compensatório do upload em falha do banco ---------------------
def test_upload_rolled_back_when_db_write_fails(client, auth_headers, monkeypatch):
    """Escrita em dois sistemas: se o INSERT no banco falha DEPOIS do upload, o
    objeto já enviado é apagado (delete compensatório) e o erro é repropagado."""
    from app.core import storage
    from app.repositories import memory_repository

    deleted: list[str] = []
    uploaded: list[str] = []

    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "upload", lambda path, *a, **k: uploaded.append(path))
    monkeypatch.setattr(storage, "sign_urls", lambda paths, ttl=None: {})
    monkeypatch.setattr(storage, "delete", lambda path: deleted.append(path))

    def boom(*a, **k):
        raise RuntimeError("db down")

    monkeypatch.setattr(memory_repository, "add_image", boom)

    h = auth_headers()
    mid = _memory(client, h)
    with pytest.raises(RuntimeError):
        _add(client, h, mid)
    # subiu um objeto e apagou exatamente esse mesmo objeto (compensação).
    assert len(uploaded) == 1
    assert deleted == uploaded
