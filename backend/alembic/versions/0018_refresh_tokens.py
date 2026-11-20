"""refresh_tokens: a sessão passa a durar mais que o access token

O access token vale uma hora e não havia como renová-lo: passada a hora, a
pessoa voltava para o login. A tabela guarda o refresh token que o app troca por
um par novo em POST /auth/refresh — só o SHA-256 dele, com validade, uso único
(rotação) e a família, que é a sessão de um aparelho.

Sem migração de dados (tabela nova). As sessões abertas antes desta migration
não têm refresh token: valem até o access token vencer, como já valiam.

Revision ID: 0018_refresh_tokens
Revises: 0017_auth_rate_limits
Create Date: 2026-11-20

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0018_refresh_tokens"
down_revision: str | Sequence[str] | None = "0017_auth_rate_limits"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "refresh_tokens",
        sa.Column(
            "id",
            sa.Uuid(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "user_id",
            sa.Uuid(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("family_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("token_hash", sa.String(64), nullable=False, unique=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index("ix_refresh_tokens_user_id", "refresh_tokens", ["user_id"])
    op.create_index("ix_refresh_tokens_family_id", "refresh_tokens", ["family_id"])


def downgrade() -> None:
    op.drop_index("ix_refresh_tokens_family_id", table_name="refresh_tokens")
    op.drop_index("ix_refresh_tokens_user_id", table_name="refresh_tokens")
    op.drop_table("refresh_tokens")
