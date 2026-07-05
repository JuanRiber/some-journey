"""memory_images: várias fotos por memória

Cria a tabela memory_images (uma memória tem N fotos, soft-delete por deleted_at)
e copia a foto única existente (memories.image_path) para não perder nada.

Revision ID: 0003_memory_images
Revises: 0002_one_journey_per_memory
Create Date: 2026-07-05

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0003_memory_images"
down_revision: str | None = "0002_one_journey_per_memory"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "memory_images",
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("memory_id", sa.Uuid(), nullable=False),
        sa.Column("image_path", sa.Text(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["memory_id"], ["memories.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_memory_images_memory_active",
        "memory_images",
        ["memory_id"],
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    # Migra a foto única existente (se houver) para a nova tabela (posição 1).
    op.execute(
        "INSERT INTO memory_images (memory_id, image_path, position) "
        "SELECT id, image_path, 1 FROM memories "
        "WHERE image_path IS NOT NULL AND deleted_at IS NULL"
    )


def downgrade() -> None:
    op.drop_index("ix_memory_images_memory_active", table_name="memory_images")
    op.drop_table("memory_images")
