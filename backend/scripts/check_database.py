"""Confere se o banco apontado por DATABASE_URL está pronto para a API.

Uso (a partir de backend/), contra o banco do ar:

    sh scripts/with_production_env.sh .venv/bin/python -m scripts.check_database

Ou contra o banco local, sem o wrapper:

    python -m scripts.check_database

Responde, em ordem, às perguntas que travam um primeiro deploy: a conexão abre?
O PostGIS está disponível (e instalado)? Em que migration o schema está, e é a
última? Nunca imprime a senha: só o host e o banco.

Sai com código 0 se a conexão abriu e o PostGIS está disponível — o resto
(extensão ainda não criada, migrations pendentes) é o estado normal ANTES do
primeiro boot da API, que aplica as migrations sozinho.
"""

import sys
from pathlib import Path

from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import text

from app.db.session import engine

_BACKEND = Path(__file__).resolve().parent.parent


def _head_revision() -> str | None:
    config = Config(str(_BACKEND / "alembic.ini"))
    config.set_main_option("script_location", str(_BACKEND / "alembic"))
    return ScriptDirectory.from_config(config).get_current_head()


def main() -> int:
    url = engine.url
    print(f"banco: {url.host}:{url.port}/{url.database}")

    try:
        with engine.connect() as conn:
            version = conn.execute(text("SHOW server_version")).scalar()
            print(f"ok    conexão aberta (PostgreSQL {version})")

            available = conn.execute(
                text("SELECT default_version FROM pg_available_extensions WHERE name = 'postgis'")
            ).scalar()
            installed = conn.execute(
                text("SELECT extversion FROM pg_extension WHERE extname = 'postgis'")
            ).scalar()

            has_alembic = conn.execute(
                text("SELECT to_regclass('alembic_version') IS NOT NULL")
            ).scalar()
            current = (
                conn.execute(text("SELECT version_num FROM alembic_version")).scalar()
                if has_alembic
                else None
            )
    except Exception as exc:  # noqa: BLE001 — o tipo varia por driver; a mensagem é o que importa
        # A mensagem do driver não contém a senha (só host, usuário e motivo).
        print(f"ERRO  a conexão não abriu: {type(exc).__name__}: {exc}".splitlines()[0])
        print("      Confira o prefixo postgresql+psycopg://, o Session pooler e a senha.")
        return 1

    if available is None:
        print("ERRO  o PostGIS não está disponível neste servidor.")
        return 1
    if installed:
        print(f"ok    PostGIS {installed} instalado")
    else:
        print(f"--    PostGIS {available} disponível, ainda não instalado (a migration 0001 instala)")

    head = _head_revision()
    if current is None:
        print(f"--    schema vazio; o primeiro boot da API aplica as migrations até {head}")
    elif current == head:
        print(f"ok    schema na última migration ({head})")
    else:
        print(f"--    schema em {current}; a última é {head} (o próximo deploy aplica)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
