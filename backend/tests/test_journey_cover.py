"""Capa da jornada: upload, fallback automático (primeira foto do rastro),
remoção e ownership."""

import uuid

JPEG = b"\xff\xd8\xff\xe0" + b"0" * 64


def _storage_on(monkeypatch):
    from app.core import storage

    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "upload", lambda *a, **k: None)
    monkeypatch.setattr(storage, "delete", lambda *a, **k: None)
    monkeypatch.setattr(
        storage,
        "sign_urls",
        lambda paths, ttl=None: {p: f"https://signed.example/{p}" for p in paths},
    )


def _journey(client, h, title="Fortaleza Nights"):
    return client.post("/journeys", json={"title": title}, headers=h).json()["id"]


def test_set_cover_and_list_shows_it(client, auth_headers, monkeypatch):
    _storage_on(monkeypatch)
    h = auth_headers()
    jid = _journey(client, h)
    r = client.post(
        f"/journeys/{jid}/cover",
        files={"file": ("cover.jpg", JPEG, "image/jpeg")},
        headers=h,
    )
    assert r.status_code == 200, r.text
    assert r.json()["cover_image_url"] is not None
    listed = client.get("/journeys", headers=h).json()
    assert listed[0]["cover_image_url"] is not None


def test_cover_falls_back_to_first_memory_photo(client, auth_headers, monkeypatch):
    _storage_on(monkeypatch)
    h = auth_headers()
    jid = _journey(client, h)
    # memória na jornada + foto -> vira capa automática (sem upload de capa)
    mid = client.post(
        f"/journeys/{jid}/memories",
        json={"title": "M", "text": "x", "latitude": 1.0, "longitude": 2.0, "occurred_at": "2026-07-01T12:00:00Z"},
        headers=h,
    ).json()["points"][0]["memory_id"]
    client.post(
        f"/memories/{mid}/images",
        files={"file": ("p.jpg", JPEG, "image/jpeg")},
        headers=h,
    )
    listed = client.get("/journeys", headers=h).json()
    assert listed[0]["cover_image_url"] is not None
    assert client.get(f"/journeys/{jid}", headers=h).json()["cover_image_url"] is not None


def test_remove_cover_returns_to_fallback_or_none(client, auth_headers, monkeypatch):
    _storage_on(monkeypatch)
    h = auth_headers()
    jid = _journey(client, h)
    client.post(
        f"/journeys/{jid}/cover",
        files={"file": ("cover.jpg", JPEG, "image/jpeg")},
        headers=h,
    )
    r = client.delete(f"/journeys/{jid}/cover", headers=h)
    assert r.status_code == 200, r.text
    # sem capa explícita e sem fotos no rastro -> None
    assert r.json()["cover_image_url"] is None


def test_cover_rejects_bad_type_and_other_user(client, auth_headers, monkeypatch):
    _storage_on(monkeypatch)
    h1 = auth_headers()
    h2 = auth_headers()
    jid = _journey(client, h1)
    bad = client.post(
        f"/journeys/{jid}/cover",
        files={"file": ("x.gif", b"GIF89a", "image/gif")},
        headers=h1,
    )
    assert bad.status_code == 400
    other = client.post(
        f"/journeys/{jid}/cover",
        files={"file": ("cover.jpg", JPEG, "image/jpeg")},
        headers=h2,
    )
    assert other.status_code == 404
    assert client.delete(f"/journeys/{uuid.uuid4()}/cover", headers=h1).status_code == 404
