"""journey identity: mood + is_private

Adiciona campos de identidade da jornada: `mood` (atmosfera livre, nullable) e
`is_private` (privacidade, NOT NULL default true). Jornadas existentes passam a
ser privadas por padrão. A capa (`cover_image_path`) já existia na baseline.

Revision ID: 0004_journey_identity
Revises: 0003_memory_images
Create Date: 2026-07-06

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0004_journey_identity"
down_revision: str | None = "0003_memory_images"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("journeys", sa.Column("mood", sa.Text(), nullable=True))
    op.add_column(
        "journeys",
        sa.Column(
            "is_private",
            sa.Boolean(),
            server_default=sa.text("true"),
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_column("journeys", "is_private")
    op.drop_column("journeys", "mood")
