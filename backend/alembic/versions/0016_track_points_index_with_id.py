"""journey_track_points: o índice de leitura em ordem ganha o `id`

O model sempre declarou (track_id, recorded_at, id), e a migration criou só
(track_id, recorded_at). O `id` é o desempate quando dois pontos têm o mesmo
recorded_at: sem ele no índice, o Postgres ordena à mão o que a polyline lê
em lote, e a ordem entre pontos coincidentes pode variar de uma leitura para
outra. A diferença também impedia o `alembic check` de passar.

Revision ID: 0016_track_points_index_with_id
Revises: 0015_life_phase_unique_name
Create Date: 2026-11-14

"""
from collections.abc import Sequence

from alembic import op

revision: str = "0016_track_points_index_with_id"
down_revision: str | Sequence[str] | None = "0015_life_phase_unique_name"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_index("ix_journey_track_points_track_time", table_name="journey_track_points")
    op.create_index(
        "ix_journey_track_points_track_time",
        "journey_track_points",
        ["track_id", "recorded_at", "id"],
    )


def downgrade() -> None:
    op.drop_index("ix_journey_track_points_track_time", table_name="journey_track_points")
    op.create_index(
        "ix_journey_track_points_track_time",
        "journey_track_points",
        ["track_id", "recorded_at"],
    )
