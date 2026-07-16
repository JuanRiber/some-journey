"""Percurso real (GPS) das jornadas: trecho, pontos em lote, mapa GeoJSON,
ownership e a fronteira com o mapa global (que NÃO expõe GPS bruto)."""

PTS = [
    {"latitude": -3.7320, "longitude": -38.5260, "recorded_at": "2026-07-07T10:00:00Z"},
    {"latitude": -3.7330, "longitude": -38.5270, "accuracy": 8.0, "speed": 1.2, "recorded_at": "2026-07-07T10:01:00Z"},
    {"latitude": -3.7340, "longitude": -38.5280, "recorded_at": "2026-07-07T10:02:00Z"},
]


def _journey(client, h, title="Viagem AS"):
    r = client.post("/journeys", json={"title": title}, headers=h)
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _start(client, h, jid):
    r = client.post(f"/journeys/{jid}/tracks/start", headers=h)
    assert r.status_code == 201, r.text
    return r.json()


def _mem_in_journey(client, h, jid, i=0):
    r = client.post(
        f"/journeys/{jid}/memories",
        json={
            "title": f"Dia {i + 1}",
            "text": "x",
            "latitude": -3.73 + i * 0.001,
            "longitude": -38.52 - i * 0.001,
            "occurred_at": f"2026-07-0{i + 1}T11:00:00Z",
        },
        headers=h,
    )
    assert r.status_code == 201, r.text
    return r.json()


# 1
def test_start_track_for_own_journey(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    t = _start(client, h, jid)
    assert t["is_active"] is True
    assert t["ended_at"] is None
    assert t["point_count"] == 0


# 2
def test_start_track_other_user_returns_404(client, auth_headers):
    h1 = auth_headers()
    h2 = auth_headers()
    jid = _journey(client, h1)
    assert client.post(f"/journeys/{jid}/tracks/start", headers=h2).status_code == 404


# 3
def test_add_points_increments_count_and_distance(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    t = _start(client, h, jid)
    r = client.post(f"/journeys/{jid}/tracks/{t['id']}/points", json={"points": PTS}, headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["point_count"] == 3
    assert body["distance_m"] > 0


# 4
def test_reject_invalid_coordinates(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    t = _start(client, h, jid)
    bad = {"points": [{"latitude": 999.0, "longitude": 0.0, "recorded_at": "2026-07-07T10:00:00Z"}]}
    assert client.post(f"/journeys/{jid}/tracks/{t['id']}/points", json=bad, headers=h).status_code == 422


# 5
def test_add_points_other_user_returns_404(client, auth_headers):
    h1 = auth_headers()
    h2 = auth_headers()
    jid = _journey(client, h1)
    t = _start(client, h1, jid)
    r = client.post(f"/journeys/{jid}/tracks/{t['id']}/points", json={"points": PTS}, headers=h2)
    assert r.status_code == 404


# 6
def test_finish_track_then_cannot_add(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    t = _start(client, h, jid)
    f = client.post(f"/journeys/{jid}/tracks/{t['id']}/finish", headers=h)
    assert f.status_code == 200, f.text
    assert f.json()["is_active"] is False
    assert f.json()["ended_at"] is not None
    # adicionar depois de finalizado -> 409
    assert client.post(f"/journeys/{jid}/tracks/{t['id']}/points", json={"points": PTS}, headers=h).status_code == 409


def test_only_one_open_track_per_journey(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    _start(client, h, jid)
    # segundo trecho aberto na mesma jornada -> 409
    assert client.post(f"/journeys/{jid}/tracks/start", headers=h).status_code == 409


# 7
def test_journey_map_has_track_linestring(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    t = _start(client, h, jid)
    client.post(f"/journeys/{jid}/tracks/{t['id']}/points", json={"points": PTS}, headers=h)
    r = client.get(f"/journeys/{jid}/map", headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["tracks"]["type"] == "FeatureCollection"
    feats = body["tracks"]["features"]
    assert len(feats) == 1
    assert feats[0]["geometry"]["type"] == "LineString"
    coords = feats[0]["geometry"]["coordinates"]
    assert len(coords) == 3
    # GeoJSON usa [lng, lat]
    assert abs(coords[0][0] - (-38.526)) < 1e-6
    assert abs(coords[0][1] - (-3.732)) < 1e-6
    assert body["distance_m"] > 0


# 8
def test_journey_map_without_track_returns_memories(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    _mem_in_journey(client, h, jid, 0)
    _mem_in_journey(client, h, jid, 1)
    r = client.get(f"/journeys/{jid}/map", headers=h)
    assert r.status_code == 200
    body = r.json()
    assert body["tracks"]["features"] == []
    assert len(body["memories"]["features"]) == 2
    assert body["symbolic_route"] is not None  # 2+ memórias -> linha simbólica


# 9
def test_delete_track_keeps_memories(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    _mem_in_journey(client, h, jid, 0)
    t = _start(client, h, jid)
    client.post(f"/journeys/{jid}/tracks/{t['id']}/points", json={"points": PTS}, headers=h)
    assert client.delete(f"/journeys/{jid}/tracks/{t['id']}", headers=h).status_code == 204
    body = client.get(f"/journeys/{jid}/map", headers=h).json()
    assert len(body["memories"]["features"]) == 1  # memória preservada
    assert body["tracks"]["features"] == []  # percurso removido


# 10
def test_global_map_excludes_raw_gps(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    _mem_in_journey(client, h, jid, 0)
    t = _start(client, h, jid)
    client.post(f"/journeys/{jid}/tracks/{t['id']}/points", json={"points": PTS}, headers=h)
    body = client.get("/map", headers=h).json()
    assert set(body.keys()) == {"loose_points", "journeys"}
    for j in body["journeys"]:
        assert set(j.keys()) == {"id", "title", "status", "points", "route"}
        assert "tracks" not in j and "track" not in j


# 11
def test_journey_map_other_user_returns_404(client, auth_headers):
    h1 = auth_headers()
    h2 = auth_headers()
    jid = _journey(client, h1)
    assert client.get(f"/journeys/{jid}/map", headers=h2).status_code == 404


def test_journey_map_scoped_to_its_journey(client, auth_headers):
    h = auth_headers()
    j1 = _journey(client, h, "J1")
    j2 = _journey(client, h, "J2")
    _mem_in_journey(client, h, j1, 0)
    _mem_in_journey(client, h, j2, 1)
    body = client.get(f"/journeys/{j1}/map", headers=h).json()
    assert body["journey"]["id"] == j1
    assert len(body["memories"]["features"]) == 1
    assert body["memories"]["features"][0]["properties"]["title"] == "Dia 1"


# 12
def test_map_shows_memories_and_track_together(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    _mem_in_journey(client, h, jid, 0)
    t = _start(client, h, jid)
    client.post(f"/journeys/{jid}/tracks/{t['id']}/points", json={"points": PTS}, headers=h)
    body = client.get(f"/journeys/{jid}/map", headers=h).json()
    assert len(body["memories"]["features"]) >= 1
    assert len(body["tracks"]["features"]) == 1
