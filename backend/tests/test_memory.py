"""Memórias: descrição (text) OPCIONAL — só título + data + local obrigatórios."""


def _payload(**over):
    base = {
        "title": "M",
        "latitude": 1.0,
        "longitude": 2.0,
        "occurred_at": "2026-01-01T00:00:00Z",
    }
    base.update(over)
    return base


def test_create_without_text(client, auth_headers):
    h = auth_headers()
    r = client.post("/memories", json=_payload(), headers=h)  # sem "text"
    assert r.status_code == 201, r.text
    assert r.json()["text"] == ""


def test_create_with_empty_text(client, auth_headers):
    h = auth_headers()
    r = client.post("/memories", json=_payload(text=""), headers=h)
    assert r.status_code == 201
    assert r.json()["text"] == ""


def test_update_can_clear_text(client, auth_headers):
    h = auth_headers()
    mid = client.post("/memories", json=_payload(text="algo"), headers=h).json()["id"]
    r = client.patch(f"/memories/{mid}", json={"text": ""}, headers=h)
    assert r.status_code == 200
    assert r.json()["text"] == ""


def test_title_still_required(client, auth_headers):
    h = auth_headers()
    r = client.post("/memories", json=_payload(title=""), headers=h)
    assert r.status_code == 422  # título vazio -> 422


def test_location_still_required(client, auth_headers):
    h = auth_headers()
    r = client.post(
        "/memories",
        json={"title": "M", "occurred_at": "2026-01-01T00:00:00Z"},
        headers=h,
    )
    assert r.status_code == 422  # latitude/longitude continuam obrigatórios
