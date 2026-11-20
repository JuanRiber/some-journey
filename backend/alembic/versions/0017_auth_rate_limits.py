"""auth_rate_limits: o limite de tentativas sai da memória do processo

O limitador dos endpoints de autenticação era um dicionário em memória: um
reinício da API zerava os baldes, e cada processo contava o seu. A tabela guarda
uma linha por balde (janela + tentativas), contada com um único
INSERT ... ON CONFLICT DO UPDATE — ver app/core/rate_limit.py.

A chave é o SHA-256 das partes (IP, e-mail), prefixado pelo escopo: a tabela não
guarda quem tentou entrar nem de onde.

Sem migração de dados (tabela nova; os baldes em memória não são levados).

Revision ID: 0017_auth_rate_limits
Revises: 0016_track_points_index_with_id
Create Date: 2026-11-20

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0017_auth_rate_limits"
down_revision: str | Sequence[str] | None = "0016_track_points_index_with_id"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "auth_rate_limits",
        sa.Column("key", sa.String(160), primary_key=True),
        sa.Column("window_started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
    )
    op.create_index(
        "ix_auth_rate_limits_window_started_at",
        "auth_rate_limits",
        ["window_started_at"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_auth_rate_limits_window_started_at", table_name="auth_rate_limits"
    )
    op.drop_table("auth_rate_limits")
