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


def test_title_is_optional(client, auth_headers):
    # A regra de produto (docs/01-regras-negocio.md) sempre quis o título
    # opcional; a API é que exigia. Guardar uma lembrança não pode depender de
    # inventar um rótulo para ela.
    h = auth_headers()
    r = client.post("/memories", json=_payload(title=""), headers=h)
    assert r.status_code == 201
    assert r.json()["title"] == ""


def test_title_can_be_omitted_entirely(client, auth_headers):
    h = auth_headers()
    payload = _payload()
    payload.pop("title")
    r = client.post("/memories", json=payload, headers=h)
    assert r.status_code == 201
    assert r.json()["title"] == ""


def test_update_can_clear_title(client, auth_headers):
    # Mesma convenção do texto: "" apaga, null não mexe.
    h = auth_headers()
    mid = client.post("/memories", json=_payload(title="Praia"), headers=h).json()["id"]
    r = client.patch(f"/memories/{mid}", json={"title": ""}, headers=h)
    assert r.status_code == 200
    assert r.json()["title"] == ""


def test_title_still_has_a_ceiling(client, auth_headers):
    # Opcional não quer dizer sem limite: 120 continua valendo.
    h = auth_headers()
    r = client.post("/memories", json=_payload(title="x" * 121), headers=h)
    assert r.status_code == 422


def test_location_still_required(client, auth_headers):
    h = auth_headers()
    r = client.post(
        "/memories",
        json={"title": "M", "occurred_at": "2026-01-01T00:00:00Z"},
        headers=h,
    )
    assert r.status_code == 422  # latitude/longitude continuam obrigatórios
