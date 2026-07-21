"""auth: users.password_changed_at (JWT invalidation on password change)

Marca a última troca/redefinição de senha. O access token carrega o claim
"pcat" (epoch dessa coluna no momento da emissão); get_current_user recusa
tokens cujo pcat seja anterior — assim trocar a senha (ou concluir um reset)
invalida NA HORA os tokens emitidos antes, sem deixar o token stateless.

Revision ID: 0007_password_changed_at
Revises: 0006_password_reset_tokens
Create Date: 2026-07-21

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0007_password_changed_at"
down_revision: str | None = "0006_password_reset_tokens"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # server_default now(): linhas existentes recebem o instante da migração
    # (equivale a "nenhuma troca desde então") — tokens já emitidos seguem
    # válidos até expirarem, sem quebrar sessões vigentes no deploy.
    op.add_column(
        "users",
        sa.Column(
            "password_changed_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )


def downgrade() -> None:
    op.drop_column("users", "password_changed_at")
