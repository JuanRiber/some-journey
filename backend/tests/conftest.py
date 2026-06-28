"""Infra dos testes.

Usa um banco DEDICADO (some_journey_test) — nunca o de desenvolvimento. A
DATABASE_URL de teste é definida em os.environ ANTES de qualquer import de
`app` (precedência sobre o .env no pydantic-settings), então o engine da app já
nasce apontando para o banco de teste. O schema é criado com create_all (que
hoje produz o mesmo schema das migrations) e as tabelas são truncadas a cada
teste para isolamento.

Pré-requisito: o Postgres/PostGIS do docker-compose rodando em localhost:5433.
O banco de teste é criado automaticamente se não existir.
"""

import os

# --- precisa vir ANTES de importar qualquer coisa de `app` ---
TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+psycopg://somejourney:somejourney_password@localhost:5433/some_journey_test",
)
os.environ["DATABASE_URL"] = TEST_DATABASE_URL
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key-at-least-32-bytes-long-xx")
os.environ.setdefault("APP_ENV", "test")

import uuid  # noqa: E402

import psycopg  # noqa: E402
import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine, text  # noqa: E402
from sqlalchemy.engine import make_url  # noqa: E402

_engine = create_engine(TEST_DATABASE_URL)
_TABLES = "journey_memories, journeys, memories, users"


def _ensure_database() -> None:
    """Cria o banco de teste (se faltar) e habilita o PostGIS."""
    url = make_url(TEST_DATABASE_URL)
    admin = psycopg.connect(
        host=url.host,
        port=url.port,
        user=url.username,
        password=url.password,
        dbname="postgres",
        autocommit=True,
    )
    try:
        exists = admin.execute(
            "SELECT 1 FROM pg_database WHERE datname = %s", (url.database,)
        ).fetchone()
        if not exists:
            admin.execute(f'CREATE DATABASE "{url.database}"')
    finally:
        admin.close()
    with _engine.begin() as conn:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS postgis"))


@pytest.fixture(scope="session", autouse=True)
def _schema():
    _ensure_database()
    import app.models  # noqa: F401 - registra os models
    from app.db.base import Base

    Base.metadata.create_all(_engine)
    yield


@pytest.fixture(autouse=True)
def _clean_tables(_schema):
    """Cada teste começa com as tabelas vazias (isolamento)."""
    with _engine.begin() as conn:
        conn.execute(text(f"TRUNCATE {_TABLES} RESTART IDENTITY CASCADE"))
    yield


@pytest.fixture()
def client(_schema) -> TestClient:
    from app.main import app

    # base_url com host permitido pelo TrustedHostMiddleware.
    return TestClient(app, base_url="http://localhost")


@pytest.fixture()
def auth_headers(client):
    """Fábrica: registra+loga um usuário novo e devolve o header Authorization."""

    def _make(email: str | None = None) -> dict[str, str]:
        email = email or f"u_{uuid.uuid4().hex[:10]}@test.com"
        password = "Sup3rSecret!pw"
        client.post(
            "/auth/register",
            json={"name": "Tester", "email": email, "password": password},
        )
        resp = client.post(
            "/auth/login", json={"email": email, "password": password}
        )
        token = resp.json()["access_token"]
        return {"Authorization": f"Bearer {token}"}

    return _make
