"""Testes de fluxo das jornadas: ciclo de vida, pontos, reordenação,
um-ponto-por-jornada, desvínculo, edição de metadados e ownership."""

import uuid


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


def test_update_journey_title_and_description(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h, "Antiga")
    r = client.patch(f"/journeys/{jid}", json={"title": "Nova", "description": "desc"}, headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["title"] == "Nova"
    assert body["description"] == "desc"
    # persistiu
    assert client.get(f"/journeys/{jid}", headers=h).json()["title"] == "Nova"


def test_update_journey_partial_keeps_other_fields(client, auth_headers):
    h = auth_headers()
    jid = client.post("/journeys", json={"title": "T", "description": "D"}, headers=h).json()["id"]
    r = client.patch(f"/journeys/{jid}", json={"title": "T2"}, headers=h)
    assert r.status_code == 200
    assert r.json()["title"] == "T2"
    assert r.json()["description"] == "D"  # não enviado -> inalterado


def test_update_journey_rejects_unknown_field(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    # extra="forbid": mexer no status por aqui é 422 (o ciclo tem endpoints próprios)
    assert client.patch(f"/journeys/{jid}", json={"status": "active"}, headers=h).status_code == 422


def test_update_journey_missing_returns_404(client, auth_headers):
    h = auth_headers()
    assert client.patch(f"/journeys/{uuid.uuid4()}", json={"title": "X"}, headers=h).status_code == 404


def test_update_journey_other_user_returns_404(client, auth_headers):
    h1 = auth_headers()
    h2 = auth_headers()
    jid = _journey(client, h1)
    assert client.patch(f"/journeys/{jid}", json={"title": "X"}, headers=h2).status_code == 404


def test_single_point_route_is_null(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    r = _add_point(client, h, jid, 0, 1.0, 2.0)
    assert r.status_code == 201
    assert r.json()["route"] is None


def test_create_with_mood_and_privacy(client, auth_headers):
    h = auth_headers()
    r = client.post(
        "/journeys",
        json={"title": "Fortaleza Nights", "mood": "noturno, urbano", "is_private": True},
        headers=h,
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["mood"] == "noturno, urbano"
    assert body["is_private"] is True
    assert body["cover_image_url"] is None
    # Sem flags: nasce privada e sem atmosfera.
    plain = client.post("/journeys", json={"title": "Sem flags"}, headers=h).json()
    assert plain["is_private"] is True
    assert plain["mood"] is None


def test_update_mood_and_privacy(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    r = client.patch(
        f"/journeys/{jid}", json={"mood": "nostálgico", "is_private": False}, headers=h
    )
    assert r.status_code == 200, r.text
    assert r.json()["mood"] == "nostálgico"
    assert r.json()["is_private"] is False
    got = client.get(f"/journeys/{jid}", headers=h).json()
    assert got["mood"] == "nostálgico"
    assert got["is_private"] is False


def test_journey_memories_are_chronological(client, auth_headers):
    h = auth_headers()
    jid = _journey(client, h)
    client.post(f"/journeys/{jid}/start", headers=h)
    # Insere fora de ordem de data (i controla o dia): 05, 01, 03 de julho.
    _add_point(client, h, jid, 4, 1.0, 1.0)
    _add_point(client, h, jid, 0, 2.0, 2.0)
    _add_point(client, h, jid, 2, 3.0, 3.0)
    r = client.get(f"/journeys/{jid}/memories", headers=h)
    assert r.status_code == 200, r.text
    dates = [m["occurred_at"] for m in r.json()]
    assert len(dates) == 3
    assert dates == sorted(dates)  # cronológico asc, não a ordem de inserção


def test_journey_memories_other_user_returns_404(client, auth_headers):
    h1 = auth_headers()
    h2 = auth_headers()
    jid = _journey(client, h1)
    assert client.get(f"/journeys/{jid}/memories", headers=h2).status_code == 404


def test_deleting_journey_frees_and_keeps_its_memories(client, auth_headers):
    # Regressão: excluir a jornada precisa soft-deletar os vínculos junto. Sem
    # isso a memória fica presa — não entra em outra jornada (409) e some dos
    # pontos soltos do mapa — mesmo com a jornada já inexistente. Excluir uma
    # jornada nunca apaga as memórias.
    h = auth_headers()
    jid = _journey(client, h)
    mem = _memory(client, h)
    assert client.post(f"/journeys/{jid}/points", json={"memory_id": mem}, headers=h).status_code == 200
    # enquanto vinculada, não aparece nos pontos soltos
    assert all(p["memory_id"] != mem for p in client.get("/map", headers=h).json()["loose_points"])
    # excluir a jornada
    assert client.delete(f"/journeys/{jid}", headers=h).status_code == 204
    # a memória continua existindo
    assert client.get(f"/memories/{mem}", headers=h).status_code == 200
    # e reaparece como ponto solto no mapa (o vínculo foi liberado)
    loose = [p["memory_id"] for p in client.get("/map", headers=h).json()["loose_points"]]
    assert mem in loose
    # e pode ser vinculada a outra jornada (o slot único foi liberado)
    jid2 = _journey(client, h, "Outra")
    assert client.post(f"/journeys/{jid2}/points", json={"memory_id": mem}, headers=h).status_code == 200
