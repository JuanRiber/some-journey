"""memories.image_path sai: a coluna da época de uma foto só

A 0003 criou memory_images e copiou para lá a foto única de cada memória. De lá
para cá nada mais escrevia na coluna — a função que a gravava ficou sem
chamador — e a API lê as fotos só de memory_images. Uma coluna que ninguém
escreve e ninguém lê é um lugar onde a próxima pessoa vai procurar a foto
errada.

Antes de soltar a coluna, copia de novo o que tiver sobrado: um caminho que
não esteja em memory_images vira a última foto da memória. Num banco novo não
há nada a copiar; num banco antigo, nenhuma foto se perde.

O downgrade devolve a coluna VAZIA — o conteúdo já vive em memory_images.

Revision ID: 0014_drop_memories_image_path
Revises: 0013_life_phases
Create Date: 2026-11-14

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0014_drop_memories_image_path"
down_revision: str | Sequence[str] | None = "0013_life_phases"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        INSERT INTO memory_images (memory_id, image_path, position)
        SELECT m.id,
               m.image_path,
               COALESCE(
                   (SELECT MAX(i.position) FROM memory_images i WHERE i.memory_id = m.id),
                   0
               ) + 1
        FROM memories m
        WHERE m.image_path IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM memory_images i
              WHERE i.memory_id = m.id AND i.image_path = m.image_path
          )
        """
    )
    op.drop_column("memories", "image_path")


def downgrade() -> None:
    op.add_column("memories", sa.Column("image_path", sa.Text(), nullable=True))
