"""Ambiente de migrations do Alembic.

A URL vem de app.core.config.settings (mesma fonte do app — .env / ambiente),
nunca do alembic.ini. O target_metadata é o Base.metadata com TODOS os models
importados (via `import app.models`), para autogenerate futuro. geoalchemy2 é
importado para que os tipos espaciais sejam resolvíveis nas migrations.
"""

from logging.config import fileConfig

import geoalchemy2  # noqa: F401 - registra os tipos espaciais p/ as migrations
from sqlalchemy import create_engine, pool

from alembic import context

import app.models  # noqa: F401 - registra todos os models no metadata
from app.core.config import settings
from app.db.base import Base

config = context.config
# NÃO passamos a URL via config.set_main_option: o configparser do Alembic trata
# '%' como interpolação e quebra em senhas URL-encoded (ex.: '%40' para '@'). O
# create_engine recebe a URL direto do settings — como o app faz em db/session.py.

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def _incluir(objeto, nome, tipo, refletido, comparado_a) -> bool:
    """O que o autogenerate/`alembic check` deve comparar.

    `spatial_ref_sys` vem com a extensão PostGIS, não com os models: sem esta
    exclusão o `alembic check` sempre veria "uma tabela a mais" e nunca
    passaria — e um check que nunca passa é um check que ninguém roda."""
    return not (tipo == "table" and refletido and comparado_a is None and nome == "spatial_ref_sys")


def run_migrations_offline() -> None:
    context.configure(
        url=settings.DATABASE_URL,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
        include_object=_incluir,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = create_engine(settings.DATABASE_URL, poolclass=pool.NullPool)
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
            include_object=_incluir,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
