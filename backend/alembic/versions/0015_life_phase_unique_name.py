"""life_phases: um nome por pessoa, entre as fases ativas

Duas fases "Faculdade" viram duas etiquetas iguais na lente da timeline e do
atlas, e a pessoa não tem como saber qual filtra o quê. O índice é por
`LOWER(name)` ("faculdade" e "Faculdade" são o mesmo capítulo) e só entre as
ativas: dá para recriar uma fase com o nome de uma que foi apagada.

Se já houver repetidos (num banco de desenvolvimento), os mais novos ganham um
sufixo " (2)", " (3)"... antes de o índice nascer — renomear é reversível à mão;
apagar não seria.

Revision ID: 0015_life_phase_unique_name
Revises: 0014_drop_memories_image_path
Create Date: 2026-11-14

"""
from collections.abc import Sequence

from alembic import op

revision: str = "0015_life_phase_unique_name"
down_revision: str | Sequence[str] | None = "0014_drop_memories_image_path"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        """
        WITH repetidas AS (
            SELECT id,
                   ROW_NUMBER() OVER (
                       PARTITION BY user_id, LOWER(name)
                       ORDER BY created_at, id
                   ) AS n
            FROM life_phases
            WHERE deleted_at IS NULL
        )
        UPDATE life_phases AS f
        SET name = LEFT(f.name, 54) || ' (' || r.n || ')'
        FROM repetidas r
        WHERE f.id = r.id AND r.n > 1
        """
    )
    op.execute(
        "CREATE UNIQUE INDEX uq_life_phases_user_name_active "
        "ON life_phases (user_id, LOWER(name)) WHERE deleted_at IS NULL"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_life_phases_user_name_active")
