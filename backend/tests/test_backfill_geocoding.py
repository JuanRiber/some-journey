"""Backfill: a fila é lida corretamente, é idempotente e não perde progresso."""

from datetime import UTC, datetime

from app.db.session import SessionLocal
from app.domain.location import Location
from app.repositories import memory_repository
from app.services import geocoding
from scripts import backfill_geocoding


def _memory(client, headers, title="M"):
    r = client.post(
        "/memories",
        json={"title": title, "text": "", "latitude": -3.7319,
              "longitude": -38.5267, "occurred_at": "2026-07-01T12:00:00Z"},
        headers=headers,
    )
    assert r.status_code == 201
    return r.json()


class _Fake:
    """Provedor que sempre resolve (sem rede)."""

    def reverse(self, latitude, longitude):
        return Location(latitude=latitude, longitude=longitude).with_geocoding(
            place_name=None, place_label="Fortaleza", city="Fortaleza",
            state_province="Ceará", country="Brasil", country_code="BR",
            formatted_address=None, timezone=None, geocoded_at=datetime.now(UTC),
        )


def test_a_fila_traz_so_o_que_falta(client, auth_headers):
    headers = auth_headers()
    _memory(client, headers, "sem lugar")
    with SessionLocal() as db:
        assert len(backfill_geocoding.pending(db, 100)) >= 1


def test_backfill_resolve_e_persiste(client, auth_headers, monkeypatch):
    headers = auth_headers()
    created = _memory(client, headers)
    monkeypatch.setattr(geocoding, "get_provider", lambda: _Fake())
    monkeypatch.setattr(backfill_geocoding.time, "sleep", lambda s: None)

    assert backfill_geocoding.run(limit=100, dry_run=False) >= 1

    body = client.get(f"/memories/{created['id']}", headers=headers).json()
    assert body["city"] == "Fortaleza"
    assert body["continent"] == "América do Sul"


def test_e_idempotente(client, auth_headers, monkeypatch):
    headers = auth_headers()
    _memory(client, headers)
    monkeypatch.setattr(geocoding, "get_provider", lambda: _Fake())
    monkeypatch.setattr(backfill_geocoding.time, "sleep", lambda s: None)

    backfill_geocoding.run(limit=100, dry_run=False)
    assert backfill_geocoding.run(limit=100, dry_run=False) == 0, "nada sobra"


def test_dry_run_nao_grava(client, auth_headers, monkeypatch):
    headers = auth_headers()
    created = _memory(client, headers)
    monkeypatch.setattr(geocoding, "get_provider", lambda: _Fake())

    assert backfill_geocoding.run(limit=100, dry_run=True) == 0
    assert client.get(f"/memories/{created['id']}", headers=headers).json()["city"] is None


def test_provedor_desligado_nao_faz_nada(client, auth_headers):
    """Em teste o provedor é o Null — o script deve sair limpo, sem tocar no banco."""
    _memory(client, auth_headers())
    assert backfill_geocoding.run(limit=100, dry_run=False) == 0


def test_falha_em_uma_nao_perde_as_outras(client, auth_headers, monkeypatch):
    headers = auth_headers()
    _memory(client, headers, "a")
    _memory(client, headers, "b")

    calls = {"n": 0}

    class Flaky:
        def reverse(self, latitude, longitude):
            calls["n"] += 1
            if calls["n"] == 1:
                return None  # primeira não resolve
            return _Fake().reverse(latitude, longitude)

    monkeypatch.setattr(geocoding, "get_provider", lambda: Flaky())
    monkeypatch.setattr(backfill_geocoding.time, "sleep", lambda s: None)

    assert backfill_geocoding.run(limit=100, dry_run=False) == 1, "a segunda foi salva"
    with SessionLocal() as db:
        assert len(backfill_geocoding.pending(db, 100)) == 1, "a primeira segue na fila"
