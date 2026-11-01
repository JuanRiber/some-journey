"""Infra dos testes.

Usa um banco DEDICADO (some_journey_test) — nunca o de desenvolvimento. A
DATABASE_URL de teste é definida em os.environ ANTES de qualquer import de
`app` (precedência sobre o .env no pydantic-settings), então o engine da app já
nasce apontando para o banco de teste. O schema é criado com create_all (que
hoje produz o mesmo schema das migrations) e TODA tabela da app é truncada a
cada teste para isolamento — a lista sai do metadata do ORM, não da mão de
ninguém (ver `_tabelas_a_truncar`), e `_assert_schema_coberto` para a suíte se
ela e o banco discordarem.

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
from sqlalchemy import MetaData, create_engine, text  # noqa: E402
from sqlalchemy.engine import make_url  # noqa: E402

_engine = create_engine(TEST_DATABASE_URL)

# Tabelas que moram no banco de teste mas não guardam dado de teste nenhum.
# `alembic_version` é do Alembic: truncá-la apaga o carimbo da migration
# aplicada e o ciclo seguinte remigra tudo do zero. `spatial_ref_sys` é a
# tabela de referência do PostGIS — limpá-la quebraria qualquer ST_Transform.
# Nenhuma das duas entra no TRUNCATE nem é cobrada pelo guarda de schema.
_FORA_DO_TRUNCATE = frozenset({"alembic_version", "spatial_ref_sys"})


def _tabelas_a_truncar(metadata: MetaData) -> list[str]:
    """Nomes das tabelas da app, na ordem filho→pai, tirados do metadata do ORM.

    Esta lista já foi escrita à mão e derrapou: nomeava sete das nove tabelas e
    só não vazava linha porque o `TRUNCATE ... CASCADE` alcançava as outras duas
    de carona pela chave estrangeira (`memory_music → memories`,
    `password_reset_tokens → users`). Era sorte, não cobertura: a primeira
    tabela nova sem FK para o conjunto listado ficaria por limpar, e o sintoma
    disso aparece longe da causa — um teste que passa sozinho e falha na suíte,
    ou o contrário. Derivar do metadata tira a lista da mão de quem esquece.

    `sorted_tables` vem em ordem de dependência (pai antes de filho) e nós
    invertemos, preservando a ordem filho→pai que a lista antiga usava. Num
    TRUNCATE único com CASCADE a ordem é indiferente para o Postgres, mas ela
    mantém o comando legível e fiel ao grafo de dependência do schema.
    """
    return [
        tabela.name
        for tabela in reversed(metadata.sorted_tables)
        if tabela.name not in _FORA_DO_TRUNCATE
    ]


def _assert_schema_coberto(tabelas: list[str]) -> None:
    """Interrompe a suíte se o banco de teste e o metadata do ORM discordarem.

    O isolamento entre testes vale exatamente o quanto esta lista for completa:
    tabela que existe no banco e o metadata não conhece não é truncada, e a
    linha que sobrar contamina o teste seguinte sem erro nenhum. Como o estrago
    é silencioso e se manifesta em outro arquivo, a falha aqui é barulhenta de
    propósito — para tudo, com o nome da tabela na mensagem, em vez de deixar
    278 testes rodarem em cima de um harness que não limpa o que promete.
    """
    with _engine.begin() as conn:
        no_banco = {
            linha[0]
            for linha in conn.execute(
                text("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")
            )
        }
    no_banco -= _FORA_DO_TRUNCATE
    cobertas = set(tabelas)
    sem_cobertura = sorted(no_banco - cobertas)
    sem_tabela = sorted(cobertas - no_banco)
    if not sem_cobertura and not sem_tabela:
        return

    recado = ["o harness de teste e o schema do banco discordam:"]
    if sem_cobertura:
        recado.append(
            "  existem no banco e NÃO seriam truncadas entre os testes: "
            + ", ".join(sem_cobertura)
        )
    if sem_tabela:
        recado.append(
            "  o metadata declara e o banco não tem: " + ", ".join(sem_tabela)
        )
    recado.append(
        "  se o model é novo, registre-o em app/models/__init__.py; se a tabela é"
    )
    recado.append(
        "  resquício de um schema antigo, recrie o banco de teste "
        f"({make_url(TEST_DATABASE_URL).database}) do zero."
    )
    pytest.exit("\n".join(recado), returncode=1)


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
    """Garante o schema e entrega a lista de tabelas que `_clean_tables` trunca."""
    _ensure_database()
    import app.models  # noqa: F401 - registra os models
    from app.db.base import Base

    Base.metadata.create_all(_engine)
    tabelas = _tabelas_a_truncar(Base.metadata)
    _assert_schema_coberto(tabelas)
    yield tabelas


@pytest.fixture(autouse=True)
def _clean_tables(_schema):
    """Cada teste começa com as tabelas vazias (isolamento)."""
    alvo = ", ".join(_schema)
    with _engine.begin() as conn:
        conn.execute(text(f"TRUNCATE {alvo} RESTART IDENTITY CASCADE"))
    yield


@pytest.fixture(autouse=True)
def _reset_rate_limit():
    """Zera os baldes do rate limiter (in-memory, por processo) a cada teste —
    o TestClient compartilha o mesmo IP, então o limite por-IP acumularia entre
    testes sem isso."""
    from app.core import rate_limit

    rate_limit._buckets.clear()
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
