"""Percurso real (GPS) de uma jornada.

Diferente do "rastro simbólico" (a linha reta que liga as memórias na ordem), o
percurso real é a sequência de pontos de GPS capturados enquanto a jornada
acontecia. Modelado em dois níveis:

- JourneyTrack: um TRECHO de gravação. Pausar encerra o trecho aberto (`ended_at`);
  retomar abre outro. Vários trechos formam uma experiência só. No máximo UM
  trecho aberto por jornada (índice único parcial).
- JourneyTrackPoint: cada ponto GPS bruto do trecho (POINT geográfico + metadados
  opcionais de precisão/altitude/velocidade/rumo).

Segurança/privacidade: dado sensível de localização. Sempre filtrado por user_id;
apagar a jornada faz CASCADE nos trechos e pontos.
"""

import uuid
from datetime import datetime

from geoalchemy2 import Geography
from geoalchemy2.elements import WKBElement
from sqlalchemy import DateTime, Float, ForeignKey, Index, String, Uuid, func
from sqlalchemy import text as sql_text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class JourneyTrack(Base):
    """Um trecho de percurso real de uma jornada (uma sessão de gravação GPS)."""

    __tablename__ = "journey_tracks"

    __table_args__ = (
        Index(
            "ix_journey_tracks_journey_active",
            "journey_id",
            postgresql_where=sql_text("deleted_at IS NULL"),
        ),
        # No máximo um trecho ABERTO (em gravação) por jornada. Pausar/finalizar
        # fecha o trecho (ended_at) e libera o slot para um novo (retomar).
        Index(
            "uq_journey_tracks_one_open_per_journey",
            "journey_id",
            unique=True,
            postgresql_where=sql_text("deleted_at IS NULL AND ended_at IS NULL"),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        server_default=sql_text("gen_random_uuid()"),
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE")
    )
    journey_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("journeys.id", ondelete="CASCADE")
    )
    # manual | gps_live | imported
    source: Mapped[str] = mapped_column(String(20), server_default=sql_text("'gps_live'"))
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    # NULL = trecho ainda aberto (gravando).
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class JourneyTrackPoint(Base):
    """Um ponto GPS bruto de um trecho. location = POINT(longitude, latitude)."""

    __tablename__ = "journey_track_points"

    __table_args__ = (
        # Leitura típica: pontos de um trecho em ordem de captura.
        Index("ix_journey_track_points_track_time", "track_id", "recorded_at"),
        Index("ix_journey_track_points_journey", "journey_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        server_default=sql_text("gen_random_uuid()"),
    )
    track_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("journey_tracks.id", ondelete="CASCADE")
    )
    # Desnormalizados para consultas/ownership diretos sem join.
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE")
    )
    journey_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("journeys.id", ondelete="CASCADE")
    )
    location: Mapped[WKBElement] = mapped_column(
        Geography(geometry_type="POINT", srid=4326)
    )
    # Metadados de GPS (podem faltar dependendo do device/sinal).
    accuracy: Mapped[float | None] = mapped_column(Float)
    altitude: Mapped[float | None] = mapped_column(Float)
    speed: Mapped[float | None] = mapped_column(Float)
    heading: Mapped[float | None] = mapped_column(Float)
    # Quando o ponto foi realmente capturado no device.
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
