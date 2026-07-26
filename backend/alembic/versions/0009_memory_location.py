"""memory location: full place object

Uma memória passa a guardar O LUGAR onde aconteceu, não só o par de coordenadas.
Os campos são preenchidos por reverse geocoding na escrita e ficam persistidos —
o app nunca volta ao provedor para saber onde algo aconteceu.

TODOS nullable de propósito: geocodificar pode falhar (rede, limite de uso, ponto
no meio do oceano) e registrar a memória JAMAIS pode depender disso. As
coordenadas (coluna GEOGRAPHY) continuam sendo a fonte espacial; `geocoded_at IS
NULL` é a fila de reprocessamento.

Índices parciais (só linhas ativas), pensados para o que vem: Passaporte e
estatísticas agregam por `country_code`/`city`; vizinhança e clustering do Atlas
usam prefixo de `geohash`.

Revision ID: 0009_memory_location
Revises: 0008_list_indexes
Create Date: 2026-07-26

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0009_memory_location"
down_revision: str | None = "0008_list_indexes"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# (nome, tipo) — a ordem espelha o docs/10-localizacao.md.
_COLUMNS: tuple[tuple[str, sa.types.TypeEngine], ...] = (
    ("place_name", sa.Text()),
    ("place_label", sa.Text()),
    ("city", sa.Text()),
    ("state_province", sa.Text()),
    ("country", sa.Text()),
    ("country_code", sa.CHAR(2)),
    ("continent", sa.Text()),
    ("formatted_address", sa.Text()),
    ("timezone", sa.Text()),
    ("geohash", sa.String(12)),
    ("geocoded_at", sa.DateTime(timezone=True)),
)


def upgrade() -> None:
    for name, type_ in _COLUMNS:
        op.add_column("memories", sa.Column(name, type_, nullable=True))

    op.create_index(
        "ix_memories_city_active",
        "memories",
        ["user_id", "city"],
        postgresql_where=sa.text("deleted_at IS NULL AND city IS NOT NULL"),
    )
    op.create_index(
        "ix_memories_country_active",
        "memories",
        ["user_id", "country_code"],
        postgresql_where=sa.text("deleted_at IS NULL AND country_code IS NOT NULL"),
    )
    # Prefixo de geohash = vizinhança. text_pattern_ops faz o LIKE 'abc%' usar
    # o índice (o operador padrão do btree não serve para busca por prefixo).
    op.create_index(
        "ix_memories_geohash_active",
        "memories",
        [sa.text("geohash text_pattern_ops")],
        postgresql_where=sa.text("deleted_at IS NULL AND geohash IS NOT NULL"),
    )
    # Fila de backfill: memórias antigas (ou falhas) a geocodificar depois.
    op.create_index(
        "ix_memories_pending_geocode",
        "memories",
        ["created_at"],
        postgresql_where=sa.text("deleted_at IS NULL AND geocoded_at IS NULL"),
    )


def downgrade() -> None:
    op.drop_index("ix_memories_pending_geocode", table_name="memories")
    op.drop_index("ix_memories_geohash_active", table_name="memories")
    op.drop_index("ix_memories_country_active", table_name="memories")
    op.drop_index("ix_memories_city_active", table_name="memories")
    for name, _ in reversed(_COLUMNS):
        op.drop_column("memories", name)
