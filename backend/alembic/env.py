"""Ambiente de migrations do Alembic.

A URL vem de app.core.config.settings (mesma fonte do app — .env / ambiente),
nunca do alembic.ini. O target_metadata é o Base.metadata com TODOS os models
importados (via `import app.models`), para autogenerate futuro. geoalchemy2 é
importado para que os tipos espaciais sejam resolvíveis nas migrations.
"""

from logging.config import fileConfig

import geoalchemy2  # noqa: F401 - registra os tipos espaciais p/ as migrations
from sqlalchemy import create_engine, pool, text

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


# Tabelas que pertencem a EXTENSÕES do banco, lidas do próprio catálogo na hora
# da comparação (ver run_migrations_online). `spatial_ref_sys` já entra de
# saída: é do PostGIS em qualquer instalação, inclusive no modo offline.
_DE_EXTENSAO: set[str] = {"spatial_ref_sys"}

# Toda relação que o Postgres registra como membro de uma extensão
# (pg_depend.deptype = 'e'). É assim que o banco sabe o que um DROP EXTENSION
# leva junto — e é a resposta exata para "isto é nosso ou é da extensão?".
_SQL_DE_EXTENSAO = text(
    """
    SELECT c.relname
    FROM pg_class c
    JOIN pg_depend d
      ON d.objid = c.oid
     AND d.classid = 'pg_class'::regclass
     AND d.deptype = 'e'
    WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f')
    """
)


def _incluir(objeto, nome, tipo, refletido, comparado_a) -> bool:
    """O que o autogenerate/`alembic check` deve comparar.

    Só o que é NOSSO. Tabelas de extensão vêm com o banco, não com os models: a
    imagem `postgis/postgis` do CI instala também o geocodificador TIGER e a
    topologia, e põe os schemas deles no `search_path` — dezenas de tabelas
    (county, addr, faces, topology...) que o check via como "a mais" e que o
    Postgres local, sem essas extensões, nem tem. Excluir por nome uma a uma
    seria uma lista que nunca termina; perguntar ao catálogo, não.
    """
    if not refletido or comparado_a is not None:
        return True
    if tipo == "table":
        return nome not in _DE_EXTENSAO
    if tipo in ("index", "unique_constraint", "foreign_key_constraint"):
        tabela = getattr(getattr(objeto, "table", None), "name", None)
        return tabela not in _DE_EXTENSAO
    return True


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
    # A consulta das tabelas de extensão roda numa conexão SÓ DELA. Na mesma
    # conexão das migrations, ela abria uma transação implícita, o Alembic
    # entendia que a transação era de quem chamou e não fazia o commit — e as
    # migrations eram desfeitas ao fechar a conexão, em silêncio.
    with connectable.connect() as consulta:
        _DE_EXTENSAO.update(consulta.execute(_SQL_DE_EXTENSAO).scalars())
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
