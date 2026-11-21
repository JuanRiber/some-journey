"""pending_file_deletions: a fila dos arquivos a apagar do Storage

Excluir uma conta, ou expurgar o que foi apagado há muito, remove linhas do
banco e arquivos do Storage — dois sistemas, sem transação que cubra os dois.
A tabela guarda o caminho de cada arquivo a apagar, escrito na mesma transação
que apaga a linha: se o Storage falhar, o caminho continua aqui e é tentado de
novo, em vez de o arquivo ficar para sempre sem nenhuma linha que leve a ele.

Sem migração de dados (tabela nova).

Revision ID: 0019_pending_file_deletions
Revises: 0018_refresh_tokens
Create Date: 2026-11-21

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0019_pending_file_deletions"
down_revision: str | Sequence[str] | None = "0018_refresh_tokens"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "pending_file_deletions",
        sa.Column(
            "id",
            sa.Uuid(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("path", sa.Text(), nullable=False),
        sa.Column(
            "attempts", sa.Integer(), nullable=False, server_default=sa.text("0")
        ),
        sa.Column("last_attempt_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index(
        "ix_pending_file_deletions_queue",
        "pending_file_deletions",
        ["attempts", "created_at"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_pending_file_deletions_queue", table_name="pending_file_deletions"
    )
    op.drop_table("pending_file_deletions")
