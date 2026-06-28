"""Testes de fluxo das jornadas: ciclo de vida, pontos, reordenação,
um-ponto-por-jornada, desvínculo e ownership."""


def _journey(client, headers, title="Viagem"):
    r = client.post("/journeys", json={"title": title}, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _memory(client, headers, *, lat=10.0, lng=20.0, occurred="2026-01-01T00:00:00Z"):
    r = client.post(
        "/memories",
        json={
            "title": "M",
            "text": "x",
            "latitude": lat,
            "longitude": lng,
            "occurred_at": occurred,
        },
        headers=headers,
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _add_point(client, headers, jid, i, lat, lng):
    return client.post(
        f"/journeys/{jid}/memories",
        json={
            "title": f"P{i}",
            "text": "x",
            "latitude": lat,
            "longitude": lng,
            "occurred_at": f"2026-07-{i + 1:02d}T00:00:00Z",
        },
        headers=headers,
    )


def test_lifecycle_draft_to_finished(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    assert client.get(f"/journeys/{jid}", headers=h).json()["status"] == "draft"
    assert client.post(f"/journeys/{jid}/start", headers=h).json()["status"] == "active"
    assert client.post(f"/journeys/{jid}/finish", headers=h).json()["status"] == "finished"
    # finished é terminal
    assert client.post(f"/journeys/{jid}/start", headers=h).status_code == 409
    assert client.post(f"/journeys/{jid}/pause", headers=h).status_code == 409


def test_create_points_builds_ordered_route(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    client.post(f"/journeys/{jid}/start", headers=h)
    detail = None
    for i, (lat, lng) in enumerate([(40.71, -74.0), (34.05, -118.24), (41.88, -87.63)]):
        r = _add_point(client, h, jid, i, lat, lng)
        assert r.status_code == 201, r.text
        detail = r.json()
    assert [p["position"] for p in detail["points"]] == [1, 2, 3]
    assert detail["route"] is not None
    assert len(detail["route"]["coordinates"]) == 3
    # GeoJSON usa [lng, lat]
    assert detail["route"]["coordinates"][0] == [-74.0, 40.71]


def test_reorder_points(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    client.post(f"/journeys/{jid}/start", headers=h)
    ids = []
    for i in range(3):
        ids = [p["memory_id"] for p in _add_point(client, h, jid, i, float(i), float(i)).json()["points"]]
    rev = list(reversed(ids))
    r = client.patch(f"/journeys/{jid}/points/reorder", json={"memory_ids": rev}, headers=h)
    assert r.status_code == 200
    assert [p["memory_id"] for p in r.json()["points"]] == rev
    # subconjunto não bate com os pontos atuais -> 400
    assert (
        client.patch(
            f"/journeys/{jid}/points/reorder", json={"memory_ids": ids[:2]}, headers=h
        ).status_code
        == 400
    )


def test_one_journey_per_memory(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    mem = _memory(client, h)
    assert client.post(f"/journeys/{jid}/points", json={"memory_id": mem}, headers=h).status_code == 200
    # religar a mesma memória na mesma jornada -> 409
    assert client.post(f"/journeys/{jid}/points", json={"memory_id": mem}, headers=h).status_code == 409
    # outra jornada também não pode pegar a mesma memória -> 409
    jid2 = _journey(client, h, "Outra")
    assert client.post(f"/journeys/{jid2}/points", json={"memory_id": mem}, headers=h).status_code == 409


def test_unlink_keeps_memory_and_frees_it(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    mem = _memory(client, h)
    client.post(f"/journeys/{jid}/points", json={"memory_id": mem}, headers=h)
    # desvincular não apaga a memória
    assert client.delete(f"/journeys/{jid}/points/{mem}", headers=h).status_code == 204
    assert client.get(f"/memories/{mem}", headers=h).status_code == 200
    # e a memória volta a poder ser vinculada
    assert client.post(f"/journeys/{jid}/points", json={"memory_id": mem}, headers=h).status_code == 200
    # desvincular vínculo inexistente -> 404
    other = _memory(client, h, lat=5.0, lng=5.0)
    assert client.delete(f"/journeys/{jid}/points/{other}", headers=h).status_code == 404


def test_only_one_active_and_pause_resume(client, auth_headers):
    h = auth_headers()
    j1 = _journey(client, h, "A")
    client.post(f"/journeys/{j1}/start", headers=h)
    j2 = _journey(client, h, "B")
    # 2a não inicia enquanto a 1a está ativa
    assert client.post(f"/journeys/{j2}/start", headers=h).status_code == 409
    # pausar a 1a libera o slot
    assert client.post(f"/journeys/{j1}/pause", headers=h).json()["status"] == "paused"
    assert client.post(f"/journeys/{j2}/start", headers=h).status_code == 200
    # retomar a 1a com a 2a ativa -> 409
    assert client.post(f"/journeys/{j1}/resume", headers=h).status_code == 409
    client.post(f"/journeys/{j2}/pause", headers=h)
    assert client.post(f"/journeys/{j1}/resume", headers=h).json()["status"] == "active"


def test_ownership_isolation(client, auth_headers):
    h1 = auth_headers()
    h2 = auth_headers()
    jid = _journey(client, h1)
    mem = _memory(client, h1)
    client.post(f"/journeys/{jid}/points", json={"memory_id": mem}, headers=h1)
    # u2 não vê nem mexe na jornada de u1
    assert client.get(f"/journeys/{jid}", headers=h2).status_code == 404
    assert client.delete(f"/journeys/{jid}/points/{mem}", headers=h2).status_code == 404
    assert client.post(f"/journeys/{jid}/start", headers=h2).status_code == 404
    assert client.post(f"/journeys/{jid}/points", json={"memory_id": mem}, headers=h2).status_code == 404


def test_single_point_route_is_null(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    r = _add_point(client, h, jid, 0, 1.0, 2.0)
    assert r.status_code == 201
    assert r.json()["route"] is None
