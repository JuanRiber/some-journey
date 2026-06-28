"""one journey per memory: unique parcial por memory_id

Troca o índice único de vínculo de (journey_id, memory_id) para apenas
(memory_id), garantindo que uma memória esteja vinculada a no máximo UMA
jornada ativa por vez (MVP). Desvincular (soft-delete do vínculo) libera a
memória para outra jornada depois.

Revision ID: 0002_one_journey_per_memory
Revises: 0001_baseline
Create Date: 2026-06-28

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0002_one_journey_per_memory"
down_revision: str | None = "0001_baseline"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_index("uq_journey_memories_memory_active", table_name="journey_memories")
    op.create_index(
        "uq_journey_memories_memory_active",
        "journey_memories",
        ["memory_id"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )


def downgrade() -> None:
    op.drop_index("uq_journey_memories_memory_active", table_name="journey_memories")
    op.create_index(
        "uq_journey_memories_memory_active",
        "journey_memories",
        ["journey_id", "memory_id"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
