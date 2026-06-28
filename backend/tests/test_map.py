"""Testes do mapa principal: pins soltos, jornadas com rastro, filtros por
bbox e por jornada, validação de bbox e isolamento por usuário."""

import uuid


def _memory(client, headers, *, lat, lng, occurred="2026-01-01T00:00:00Z"):
    r = client.post(
        "/memories",
        json={"title": "M", "text": "x", "latitude": lat, "longitude": lng, "occurred_at": occurred},
        headers=headers,
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _journey_with_points(client, headers, points):
    jid = client.post("/journeys", json={"title": "J"}, headers=headers).json()["id"]
    client.post(f"/journeys/{jid}/start", headers=headers)
    for i, (lat, lng) in enumerate(points):
        client.post(
            f"/journeys/{jid}/memories",
            json={"title": f"P{i}", "text": "x", "latitude": lat, "longitude": lng, "occurred_at": f"2026-07-{i + 1:02d}T00:00:00Z"},
            headers=headers,
        )
    return jid


def test_map_loose_and_journeys(client, auth_headers):
    h = auth_headers()
    loose = _memory(client, h, lat=-3.7, lng=-38.5)
    _journey_with_points(client, h, [(40.0, -74.0), (34.0, -118.0)])
    mp = client.get("/map", headers=h).json()
    assert len(mp["loose_points"]) == 1
    assert mp["loose_points"][0]["memory_id"] == loose
    assert len(mp["journeys"]) == 1
    assert len(mp["journeys"][0]["points"]) == 2
    assert mp["journeys"][0]["route"] is not None


def test_map_loose_excludes_linked_memory(client, auth_headers):
    h = auth_headers()
    mem = _memory(client, h, lat=10.0, lng=10.0)
    jid = client.post("/journeys", json={"title": "J"}, headers=h).json()["id"]
    client.post(f"/journeys/{jid}/start", headers=h)
    client.post(f"/journeys/{jid}/points", json={"memory_id": mem}, headers=h)
    mp = client.get("/map", headers=h).json()
    assert all(p["memory_id"] != mem for p in mp["loose_points"])


def test_map_bbox_filters_loose_points(client, auth_headers):
    h = auth_headers()
    fort = _memory(client, h, lat=-3.7, lng=-38.5)   # Fortaleza
    tokyo = _memory(client, h, lat=35.6, lng=139.7)  # Tóquio
    # bbox cobrindo o Brasil
    mp = client.get("/map?bbox=-74,-34,-34,5", headers=h).json()
    ids = [p["memory_id"] for p in mp["loose_points"]]
    assert fort in ids
    assert tokyo not in ids


def test_map_journey_id_filter(client, auth_headers):
    h = auth_headers()
    _memory(client, h, lat=0.0, lng=0.0)  # solto, não deve aparecer no filtro
    jid = _journey_with_points(client, h, [(40.0, -74.0), (34.0, -118.0)])
    mp = client.get(f"/map?journey_id={jid}", headers=h).json()
    assert mp["loose_points"] == []
    assert len(mp["journeys"]) == 1
    assert mp["journeys"][0]["id"] == jid
    # jornada inexistente / de outro usuário -> 404
    assert client.get(f"/map?journey_id={uuid.uuid4()}", headers=h).status_code == 404


def test_map_bad_bbox_returns_400(client, auth_headers):
    h = auth_headers()
    assert client.get("/map?bbox=1,2,3", headers=h).status_code == 400          # poucos valores
    assert client.get("/map?bbox=a,b,c,d", headers=h).status_code == 400        # não numérico
    assert client.get("/map?bbox=10,0,5,5", headers=h).status_code == 400       # min >= max
    assert client.get("/map?bbox=-200,0,10,10", headers=h).status_code == 400   # fora do range


def test_map_excludes_other_users(client, auth_headers):
    h1 = auth_headers()
    h2 = auth_headers()
    _memory(client, h1, lat=1.0, lng=1.0)
    _journey_with_points(client, h1, [(2.0, 2.0), (3.0, 3.0)])
    mp = client.get("/map", headers=h2).json()
    assert mp["loose_points"] == []
    assert mp["journeys"] == []
