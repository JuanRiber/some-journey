"""Persistência do lugar: o job de fundo, a saída da API e a garantia de que
geocodificar jamais bloqueia (ou quebra) o registro de uma memória."""

from datetime import UTC, datetime

from app.db.session import SessionLocal
from app.domain.location import Location
from app.repositories import memory_repository
from app.services import geocoding, memory_service

PAYLOAD = {
    "title": "Fim de tarde",
    "text": "",
    "latitude": -3.7319,
    "longitude": -38.5267,
    "occurred_at": "2026-07-01T12:00:00Z",
}


def _create(client, headers):
    r = client.post("/memories", json=PAYLOAD, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()


def test_memoria_nasce_sem_lugar_e_a_api_expoe_os_campos(client, auth_headers):
    """Em teste o provedor é o Null: a memória grava na hora, sem lugar, e o
    contrato de saída já traz as chaves (o cliente não precisa adivinhar)."""
    body = _create(client, auth_headers())
    for field in ("place_label", "city", "country", "country_code", "continent"):
        assert field in body
        assert body[field] is None


def test_criar_memoria_nao_depende_do_provedor(client, auth_headers, monkeypatch):
    """Provedor explodindo NÃO pode impedir o registro — é a regra inegociável."""

    class Broken:
        def reverse(self, latitude, longitude):
            raise RuntimeError("provedor fora do ar")

    monkeypatch.setattr(geocoding, "get_provider", lambda: Broken())
    body = _create(client, auth_headers())  # BackgroundTasks roda no TestClient
    assert body["id"]
    assert body["place_label"] is None


def test_job_de_fundo_persiste_o_lugar(client, auth_headers, monkeypatch):
    headers = auth_headers()
    fixed = datetime(2026, 7, 26, 12, 0, tzinfo=UTC)

    class Fake:
        def reverse(self, latitude, longitude):
            return Location(
                latitude=latitude, longitude=longitude
            ).with_geocoding(
                place_name="Praia de Iracema",
                place_label="Praia de Iracema, Fortaleza",
                city="Fortaleza",
                state_province="Ceará",
                country="Brasil",
                country_code="br",
                formatted_address="Praia de Iracema, Fortaleza, CE",
                timezone="America/Fortaleza",
                geocoded_at=fixed,
            )

    monkeypatch.setattr(geocoding, "get_provider", lambda: Fake())
    created = _create(client, headers)

    # Releitura pela API: o lugar já está persistido (o job rodou no create).
    body = client.get(f"/memories/{created['id']}", headers=headers).json()
    assert body["place_label"] == "Praia de Iracema, Fortaleza"
    assert body["city"] == "Fortaleza"
    assert body["country_code"] == "BR"       # normalizado
    assert body["continent"] == "América do Sul"  # derivado, sem rede


def test_set_location_grava_todas_as_colunas_do_vo(client, auth_headers):
    """O repository é o único ponto que conhece o mapeamento objeto↔colunas."""
    headers = auth_headers()
    created = _create(client, headers)

    with SessionLocal() as db:
        import uuid as _uuid

        user_memories = memory_repository.get_by_id(
            db,
            user_id=_uuid.UUID(
                client.get("/auth/me", headers=headers).json()["id"]
            ),
            memory_id=_uuid.UUID(created["id"]),
        )
        loc = Location(
            latitude=-3.7319,
            longitude=-38.5267,
            city="Fortaleza",
            country_code="BR",
            geocoded_at=datetime.now(UTC),
        )
        saved = memory_repository.set_location(db, memory=user_memories, location=loc)
        assert saved.city == "Fortaleza"
        assert saved.country_code == "BR"
        assert saved.continent == "América do Sul"
        assert saved.geohash and saved.geocoded_at is not None


def test_job_ignora_memoria_apagada_entre_o_create_e_a_execucao(
    client, auth_headers, monkeypatch, caplog
):
    """Corrida real: o usuário apaga logo após criar. O job sai pela porta da
    frente — não pelo `except`.

    `geocode_memory` engole QUALQUER exceção para jamais derrubar o processo, e é
    por isso que "não levantou" não prova nada: o teste passaria igual se a
    função estourasse na primeira linha. O que prova é o caminho percorrido — o
    `return` antecipado roda, o provedor NÃO chega a ser pedido (memória apagada
    não justifica ida à rede) e nada é registrado como falha."""
    import logging
    import uuid as _uuid

    pedidos: list[str] = []

    class Espia:
        def reverse(self, latitude, longitude):
            pedidos.append("reverse")
            return Location(latitude=latitude, longitude=longitude)

    def _get_provider():
        pedidos.append("get_provider")
        return Espia()

    monkeypatch.setattr(geocoding, "get_provider", _get_provider)

    headers = auth_headers()
    me = client.get("/auth/me", headers=headers).json()

    caplog.clear()
    with caplog.at_level(logging.ERROR, logger="app.memory"):
        memory_service.geocode_memory(
            user_id=_uuid.UUID(me["id"]), memory_id=_uuid.uuid4()
        )

    assert pedidos == [], "memória apagada não pode custar uma chamada ao provedor"
    engolidas = [r for r in caplog.records if r.levelno >= logging.ERROR]
    assert engolidas == [], "o except largo escondeu uma falha de verdade"


class _Provedor:
    """Provedor falso que devolve sempre o mesmo lugar e conta as chamadas."""

    def __init__(self, cidade):
        self.cidade = cidade
        self.chamadas = 0

    def reverse(self, latitude, longitude):
        self.chamadas += 1
        return Location(latitude=latitude, longitude=longitude).with_geocoding(
            place_name=self.cidade,
            place_label=self.cidade,
            city=self.cidade,
            state_province=None,
            country="Portugal" if self.cidade == "Lisboa" else "Brasil",
            country_code="pt" if self.cidade == "Lisboa" else "br",
            formatted_address=self.cidade,
            timezone=None,
            geocoded_at=datetime(2026, 7, 26, 12, 0, tzinfo=UTC),
        )


def test_mudar_de_lugar_refaz_o_lugar(client, auth_headers, monkeypatch):
    """Regressão: o PATCH trocava o ponto e deixava "Fortaleza" no lugar — com
    `geocoded_at` preenchido, nem o backfill a pegava de novo, e o Passaporte
    contava o país errado para sempre."""
    headers = auth_headers()
    monkeypatch.setattr(geocoding, "get_provider", lambda: _Provedor("Fortaleza"))
    criada = _create(client, headers)
    assert client.get(f"/memories/{criada['id']}", headers=headers).json()["city"] == "Fortaleza"

    monkeypatch.setattr(geocoding, "get_provider", lambda: _Provedor("Lisboa"))
    r = client.patch(
        f"/memories/{criada['id']}",
        json={"latitude": 38.7223, "longitude": -9.1393},
        headers=headers,
    )
    assert r.status_code == 200, r.text

    lida = client.get(f"/memories/{criada['id']}", headers=headers).json()
    assert lida["city"] == "Lisboa"
    assert lida["country_code"] == "PT"
    assert lida["continent"] == "Europa"


def test_mudar_de_lugar_sem_provedor_volta_para_a_fila(client, auth_headers, monkeypatch):
    # Com o provedor fora, o lugar antigo NÃO pode ficar: ele mentiria. A
    # memória fica sem lugar e com geocoded_at nulo — a fila do backfill.
    headers = auth_headers()
    monkeypatch.setattr(geocoding, "get_provider", lambda: _Provedor("Fortaleza"))
    criada = _create(client, headers)

    class Fora:
        def reverse(self, latitude, longitude):
            return None

    monkeypatch.setattr(geocoding, "get_provider", lambda: Fora())
    client.patch(
        f"/memories/{criada['id']}",
        json={"latitude": 38.7223, "longitude": -9.1393},
        headers=headers,
    )

    lida = client.get(f"/memories/{criada['id']}", headers=headers).json()
    assert lida["city"] is None and lida["place_label"] is None
    with SessionLocal() as db:
        from app.models.memory import Memory

        linha = db.get(Memory, __import__("uuid").UUID(criada["id"]))
        assert linha.geocoded_at is None, "fora da fila, o lugar nunca seria refeito"


def test_salvar_sem_mexer_no_mapa_nao_apaga_o_lugar(client, auth_headers, monkeypatch):
    # O app manda latitude e longitude em TODO salvar. Mudar só o texto não
    # pode apagar o lugar nem gastar uma chamada ao provedor.
    headers = auth_headers()
    monkeypatch.setattr(geocoding, "get_provider", lambda: _Provedor("Fortaleza"))
    criada = _create(client, headers)

    vigia = _Provedor("Outro lugar")
    monkeypatch.setattr(geocoding, "get_provider", lambda: vigia)
    r = client.patch(
        f"/memories/{criada['id']}",
        json={
            "text": "o mar estava frio",
            "latitude": PAYLOAD["latitude"],
            "longitude": PAYLOAD["longitude"],
        },
        headers=headers,
    )
    assert r.status_code == 200, r.text
    assert r.json()["city"] == "Fortaleza"
    assert vigia.chamadas == 0


def test_memoria_criada_dentro_da_jornada_tambem_ganha_lugar(client, auth_headers, monkeypatch):
    """Regressão: POST /journeys/{id}/memories não agendava a geocodificação, e
    o backfill não roda sozinho em lugar nenhum — essas memórias ficavam sem
    cidade nem país."""
    headers = auth_headers()
    monkeypatch.setattr(geocoding, "get_provider", lambda: _Provedor("Fortaleza"))
    jornada = client.post("/journeys", json={"title": "Litoral"}, headers=headers).json()

    corpo = {k: v for k, v in PAYLOAD.items() if k != "title"}
    r = client.post(f"/journeys/{jornada['id']}/memories", json=corpo, headers=headers)
    # E sem título: a cópia deste contrato tinha ficado exigindo um.
    assert r.status_code == 201, r.text

    memoria_id = r.json()["points"][-1]["memory_id"]
    lida = client.get(f"/memories/{memoria_id}", headers=headers).json()
    assert lida["title"] == ""
    assert lida["city"] == "Fortaleza"
