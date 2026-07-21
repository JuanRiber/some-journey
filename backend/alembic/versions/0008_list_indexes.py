"""perf: partial composite indexes for keyset pagination

Índices parciais compostos que servem o filtro (user_id + ativos) E a ORDER BY
com paginação por keyset das listagens:
- ix_memories_user_occurred (user_id, occurred_at DESC, id DESC)
- ix_journeys_user_created  (user_id, created_at DESC, id DESC)
Ambos com WHERE deleted_at IS NULL (só linhas ativas). Expressos em SQL cru
porque o create_index do Alembic não modela DESC por coluna de forma limpa.

Revision ID: 0008_list_indexes
Revises: 0007_password_changed_at
Create Date: 2026-07-21

"""
from collections.abc import Sequence

from alembic import op

revision: str = "0008_list_indexes"
down_revision: str | None = "0007_password_changed_at"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_memories_user_occurred "
        "ON memories (user_id, occurred_at DESC, id DESC) "
        "WHERE deleted_at IS NULL"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_journeys_user_created "
        "ON journeys (user_id, created_at DESC, id DESC) "
        "WHERE deleted_at IS NULL"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_journeys_user_created")
    op.execute("DROP INDEX IF EXISTS ix_memories_user_occurred")
