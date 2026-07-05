"""Testes das fotos da memória (POST /memories/{id}/images e
DELETE /memories/{id}/images/{image_id}).

Cobrem validação de tipo/tamanho, ownership, o teto de fotos e a remoção. O
caminho "storage desabilitado -> 503" força as credenciais Supabase a None.
"""

import uuid

# 1x1 JPEG-ish header (o backend não decodifica: valida pelo content-type).
JPEG_BYTES = b"\xff\xd8\xff\xe0" + b"0" * 64


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
