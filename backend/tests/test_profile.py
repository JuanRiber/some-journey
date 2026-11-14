"""GET /me/profile: agregações reais no banco + o contrato da tela."""

from datetime import UTC, datetime

import pytest

from app.db.session import SessionLocal
from app.domain.continents import CONTINENTS_IN_ORDER
from app.domain.location import Location
from app.repositories import memory_repository


def _memory(client, headers, *, title="M", lat=-3.7319, lng=-38.5267, when="2026-07-01"):
    r = client.post(
        "/memories",
        json={
            "title": title,
            "text": "",
            "latitude": lat,
            "longitude": lng,
            "occurred_at": f"{when}T12:00:00Z",
        },
        headers=headers,
    )
    assert r.status_code == 201, r.text
    return r.json()


def _geocode(client, headers, memory_id, *, city, country, code):
    """Preenche o lugar direto pelo repository (o provedor é Null em teste)."""
    import uuid as _uuid

    me = client.get("/auth/me", headers=headers).json()
    with SessionLocal() as db:
        memory = memory_repository.get_by_id(
            db, user_id=_uuid.UUID(me["id"]), memory_id=_uuid.UUID(memory_id)
        )
        loc = Location(
            latitude=-3.7319, longitude=-38.5267, city=city, country=country,
            country_code=code, geocoded_at=datetime.now(UTC),
        )
        memory_repository.set_location(db, memory=memory, location=loc)


def test_perfil_vazio_nao_quebra_e_ja_ensina(client, auth_headers):
    """Conta nova: tudo zero, passaporte inteiro por explorar. Nunca 500."""
    body = client.get("/me/profile", headers=auth_headers()).json()

    assert body["stats"]["memories"] == 0
    assert body["stats"]["cities"] == 0
    assert body["stats"]["tracked_meters"] == 0
    assert body["last_adventure"] is None
    assert body["current_journey"] is None
    assert len(body["passport"]) == len(CONTINENTS_IN_ORDER)
    assert all(stamp["visited"] is False for stamp in body["passport"])


def test_exige_autenticacao(client):
    assert client.get("/me/profile").status_code == 401


def test_conta_memorias_cidades_e_paises_distintos(client, auth_headers):
    headers = auth_headers()
    a = _memory(client, headers, title="A")
    b = _memory(client, headers, title="B")
    c = _memory(client, headers, title="C")
    _geocode(client, headers, a["id"], city="Fortaleza", country="Brasil", code="BR")
    _geocode(client, headers, b["id"], city="Fortaleza", country="Brasil", code="BR")
    _geocode(client, headers, c["id"], city="Lisboa", country="Portugal", code="PT")

    stats = client.get("/me/profile", headers=headers).json()["stats"]
    assert stats["memories"] == 3
    assert stats["cities"] == 2, "Fortaleza duas vezes conta uma"
    assert stats["countries"] == 2
    assert stats["continents"] == 2
    assert stats["pending_geocode"] == 0


def test_passaporte_carimba_os_continentes_visitados(client, auth_headers):
    headers = auth_headers()
    m = _memory(client, headers)
    _geocode(client, headers, m["id"], city="Fortaleza", country="Brasil", code="BR")

    passport = client.get("/me/profile", headers=headers).json()["passport"]
    stamped = {s["continent"]: s["visited"] for s in passport}
    assert stamped["América do Sul"] is True
    assert stamped["Ásia"] is False, "o que falta explorar continua visível"


def test_memoria_sem_geocode_entra_na_fila_e_nao_conta_cidade(client, auth_headers):
    headers = auth_headers()
    _memory(client, headers)

    stats = client.get("/me/profile", headers=headers).json()["stats"]
    assert stats["memories"] == 1
    assert stats["cities"] == 0
    assert stats["pending_geocode"] == 1


def test_ultima_aventura_e_a_mais_recente(client, auth_headers):
    headers = auth_headers()
    old = _memory(client, headers, title="antiga", when="2024-01-01")
    new = _memory(client, headers, title="recente", when="2026-06-01")
    _geocode(client, headers, old["id"], city="Recife", country="Brasil", code="BR")
    _geocode(client, headers, new["id"], city="Guaramiranga", country="Brasil", code="BR")

    body = client.get("/me/profile", headers=headers).json()
    assert body["last_adventure"]["city"] == "Guaramiranga"


def test_jornada_atual_traz_titulo_e_pontos(client, auth_headers):
    headers = auth_headers()
    journey = client.post(
        "/journeys", json={"title": "Viagem ao Sul"}, headers=headers
    ).json()
    client.post(f"/journeys/{journey['id']}/start", headers=headers)
    client.post(
        f"/journeys/{journey['id']}/memories",
        json={
            "title": "Parada",
            "text": "",
            "latitude": -3.73,
            "longitude": -38.52,
            "occurred_at": "2026-07-01T12:00:00Z",
        },
        headers=headers,
    )

    current = client.get("/me/profile", headers=headers).json()["current_journey"]
    assert current["title"] == "Viagem ao Sul"
    assert current["points_count"] == 1


def test_jornadas_concluidas_sao_contadas(client, auth_headers):
    headers = auth_headers()
    j = client.post("/journeys", json={"title": "Fechada"}, headers=headers).json()
    client.post(f"/journeys/{j['id']}/start", headers=headers)
    client.post(f"/journeys/{j['id']}/finish", headers=headers)

    stats = client.get("/me/profile", headers=headers).json()["stats"]
    assert stats["journeys"] == 1
    assert stats["journeys_finished"] == 1


def test_o_perfil_e_do_dono_e_de_mais_ninguem(client, auth_headers):
    """Isolamento: memórias de um usuário não podem aparecer no perfil do outro."""
    mine = auth_headers()
    theirs = auth_headers()
    _memory(client, mine, title="minha")

    assert client.get("/me/profile", headers=mine).json()["stats"]["memories"] == 1
    assert client.get("/me/profile", headers=theirs).json()["stats"]["memories"] == 0


# Rastro de GPS com coordenadas fixas: duas pernas de 0,001° em latitude e
# 0,001° em longitude a ~3,73° S. No WGS84 cada perna mede 156,74 m — o total de
# 313,48 m sai da conta das coordenadas, não de uma execução da suíte.
TRACK_PTS = [
    {"latitude": -3.7320, "longitude": -38.5260, "recorded_at": "2026-07-07T10:00:00Z"},
    {"latitude": -3.7330, "longitude": -38.5270, "recorded_at": "2026-07-07T10:01:00Z"},
    {"latitude": -3.7340, "longitude": -38.5280, "recorded_at": "2026-07-07T10:02:00Z"},
]
TRACK_METERS = 313.48


def _track(client, headers, title="Caminhada"):
    """Grava um percurso real: jornada -> trecho aberto -> lote de pontos GPS.

    Uma jornada por trecho porque só um trecho fica aberto por jornada de cada
    vez — é o que permite somar dois trechos no mesmo perfil."""
    jid = client.post("/journeys", json={"title": title}, headers=headers).json()["id"]
    track = client.post(f"/journeys/{jid}/tracks/start", headers=headers).json()
    r = client.post(
        f"/journeys/{jid}/tracks/{track['id']}/points",
        json={"points": TRACK_PTS},
        headers=headers,
    )
    assert r.status_code == 200, r.text


def test_metros_percorridos_somam_os_trechos_do_dono(client, auth_headers):
    """Até aqui `tracked_meters` só era conferido na conta vazia, valendo zero —
    e zero é também o que devolve uma soma que nunca encontra os pontos. O número
    precisa bater com a distância real dos dois trechos, e o perfil de quem não
    andou precisa continuar em zero (a soma é por dono)."""
    headers = auth_headers()
    _track(client, headers, "Primeiro trecho")
    _track(client, headers, "Segundo trecho")

    stats = client.get("/me/profile", headers=headers).json()["stats"]
    assert stats["tracked_meters"] == pytest.approx(2 * TRACK_METERS, rel=0.005)

    alheio = client.get("/me/profile", headers=auth_headers()).json()["stats"]
    assert alheio["tracked_meters"] == 0


def test_dias_ativos_contam_dias_distintos(client, auth_headers):
    headers = auth_headers()
    _memory(client, headers, title="A")
    _memory(client, headers, title="B")  # mesmo dia de criação
    stats = client.get("/me/profile", headers=headers).json()["stats"]
    assert stats["active_days"] == 1


def test_trecho_e_jornada_apagados_saem_da_distancia(client, auth_headers):
    """Regressão: a soma lia os pontos de GPS direto, e apagar um trecho ou a
    jornada só marca o trecho — o perfil continuava contando o caminho que a
    pessoa apagou."""
    headers = auth_headers()

    def gravar(titulo):
        jid = client.post("/journeys", json={"title": titulo}, headers=headers).json()["id"]
        tid = client.post(f"/journeys/{jid}/tracks/start", headers=headers).json()["id"]
        r = client.post(
            f"/journeys/{jid}/tracks/{tid}/points", json={"points": TRACK_PTS}, headers=headers
        )
        assert r.status_code == 200, r.text
        return jid, tid

    jornada_a, trecho_a = gravar("Trecho apagado")
    jornada_b, _ = gravar("Jornada apagada")
    _track(client, headers, "Fica")

    def metros():
        return client.get("/me/profile", headers=headers).json()["stats"]["tracked_meters"]

    assert metros() == pytest.approx(3 * TRACK_METERS, rel=0.005)

    assert client.delete(f"/journeys/{jornada_a}/tracks/{trecho_a}", headers=headers).status_code == 204
    assert metros() == pytest.approx(2 * TRACK_METERS, rel=0.005)

    assert client.delete(f"/journeys/{jornada_b}", headers=headers).status_code == 204
    assert metros() == pytest.approx(TRACK_METERS, rel=0.005)
