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


# --- Regra: uma memória é de algo que já aconteceu ---------------------------

def _daqui(**delta):
    from datetime import UTC, datetime, timedelta

    return (datetime.now(UTC) + timedelta(**delta)).isoformat()


def test_memoria_de_um_dia_que_nao_chegou_e_recusada(client, auth_headers):
    """O seletor do app já não deixa escolher amanhã; o backend aceitava de
    qualquer outro cliente, e a timeline abriria com um capítulo do futuro."""
    h = auth_headers()
    r = client.post("/memories", json=_payload(occurred_at=_daqui(days=3)), headers=h)
    assert r.status_code == 422
    assert "ainda não chegou" in r.json()["detail"][0]["msg"]
    assert client.get("/memories", headers=h).json() == []


def test_hoje_em_qualquer_fuso_cabe(client, auth_headers):
    # O app ancora o dia ao meio-dia UTC: "hoje" em UTC+14 pode estar ~26 h à
    # frente do relógio do servidor, e ainda assim é hoje para quem registra.
    h = auth_headers()
    assert client.post("/memories", json=_payload(occurred_at=_daqui(hours=30)), headers=h).status_code == 201
    assert client.post("/memories", json=_payload(occurred_at=_daqui(minutes=-1)), headers=h).status_code == 201


def test_editar_para_o_futuro_tambem_e_recusado(client, auth_headers):
    h = auth_headers()
    mid = client.post("/memories", json=_payload(), headers=h).json()["id"]
    r = client.patch(f"/memories/{mid}", json={"occurred_at": _daqui(days=10)}, headers=h)
    assert r.status_code == 422


def test_a_regra_vale_dentro_da_jornada(client, auth_headers):
    h = auth_headers()
    jid = client.post("/journeys", json={"title": "J"}, headers=h).json()["id"]
    corpo = {k: v for k, v in _payload(occurred_at=_daqui(days=5)).items()}
    assert client.post(f"/journeys/{jid}/memories", json=corpo, headers=h).status_code == 422


def test_jornada_e_fase_podem_olhar_para_frente(client, auth_headers):
    # A regra é da MEMÓRIA. Uma viagem pode estar planejada e uma fase pode ter
    # fim marcado — nenhuma das duas é uma lembrança.
    h = auth_headers()
    assert client.post(
        "/journeys", json={"title": "Viagem planejada", "started_at": _daqui(days=60)}, headers=h
    ).status_code == 201
    assert client.post(
        "/life-phases", json={"name": "Intercâmbio", "ended_at": _daqui(days=200)}, headers=h
    ).status_code == 201
