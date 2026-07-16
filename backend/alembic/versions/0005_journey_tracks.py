"""journey tracks: real GPS path (tracks + track points)

Cria as tabelas do percurso real de uma jornada:
- journey_tracks: um trecho de gravação (started_at/ended_at, source), no máximo
  um aberto por jornada (índice único parcial onde ended_at IS NULL).
- journey_track_points: pontos GPS brutos (GEOGRAPHY POINT + metadados), com
  índice GiST espacial e índice por (track_id, recorded_at) para ler em ordem.

Sem migração de dados (tabelas novas).

Revision ID: 0005_journey_tracks
Revises: 0004_journey_identity
Create Date: 2026-07-07

"""
from collections.abc import Sequence

import geoalchemy2
import sqlalchemy as sa

from alembic import op

revision: str = "0005_journey_tracks"
down_revision: str | None = "0004_journey_identity"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "journey_tracks",
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
        sa.Column(
            "journey_id",
            sa.Uuid(as_uuid=True),
            sa.ForeignKey("journeys.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "source",
            sa.String(20),
            nullable=False,
            server_default=sa.text("'gps_live'"),
        ),
        sa.Column(
            "started_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_journey_tracks_journey_active",
        "journey_tracks",
        ["journey_id"],
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    op.create_index(
        "uq_journey_tracks_one_open_per_journey",
        "journey_tracks",
        ["journey_id"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL AND ended_at IS NULL"),
    )

    op.create_table(
        "journey_track_points",
        sa.Column(
            "id",
            sa.Uuid(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "track_id",
            sa.Uuid(as_uuid=True),
            sa.ForeignKey("journey_tracks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            sa.Uuid(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "journey_id",
            sa.Uuid(as_uuid=True),
            sa.ForeignKey("journeys.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "location",
            geoalchemy2.Geography(
                geometry_type="POINT", srid=4326, spatial_index=False
            ),
            nullable=False,
        ),
        sa.Column("accuracy", sa.Float(), nullable=True),
        sa.Column("altitude", sa.Float(), nullable=True),
        sa.Column("speed", sa.Float(), nullable=True),
        sa.Column("heading", sa.Float(), nullable=True),
        sa.Column("recorded_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index(
        "ix_journey_track_points_track_time",
        "journey_track_points",
        ["track_id", "recorded_at"],
    )
    op.create_index(
        "ix_journey_track_points_journey",
        "journey_track_points",
        ["journey_id"],
    )
    op.create_index(
        "idx_journey_track_points_location",
        "journey_track_points",
        ["location"],
        postgresql_using="gist",
    )


def downgrade() -> None:
    op.drop_index(
        "idx_journey_track_points_location", table_name="journey_track_points"
    )
    op.drop_index(
        "ix_journey_track_points_journey", table_name="journey_track_points"
    )
    op.drop_index(
        "ix_journey_track_points_track_time", table_name="journey_track_points"
    )
    op.drop_table("journey_track_points")
    op.drop_index("uq_journey_tracks_one_open_per_journey", table_name="journey_tracks")
    op.drop_index("ix_journey_tracks_journey_active", table_name="journey_tracks")
    op.drop_table("journey_tracks")
