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


def test_job_ignora_memoria_apagada_entre_o_create_e_a_execucao(client, auth_headers):
    """Corrida real: o usuário apaga logo após criar. O job não pode estourar."""
    import uuid as _uuid

    headers = auth_headers()
    me = client.get("/auth/me", headers=headers).json()
    with SessionLocal() as db:
        memory_service.geocode_memory(
            user_id=_uuid.UUID(me["id"]), memory_id=_uuid.uuid4()
    )  # não levanta
