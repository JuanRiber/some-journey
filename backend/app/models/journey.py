import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, String, Text, Uuid, func
from sqlalchemy import text as sql_text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Journey(Base):
    """Narrativa/trajetoria que conecta memories do mesmo usuario."""

    __tablename__ = "journeys"

    __table_args__ = (
        Index(
            "ix_journeys_user_active",
            "user_id",
            postgresql_where=sql_text("deleted_at IS NULL"),
        ),
        Index(
            "uq_journeys_one_active_per_user",
            "user_id",
            unique=True,
            postgresql_where=sql_text("deleted_at IS NULL AND status = 'active'"),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        server_default=sql_text("gen_random_uuid()"),
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
    )
    title: Mapped[str] = mapped_column(String(120))
    description: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(20), server_default=sql_text("'draft'"))
    cover_image_path: Mapped[str | None] = mapped_column(Text)
    # Atmosfera/humor livre da jornada (ex.: "noturno, nostálgico, urbano").
    mood: Mapped[str | None] = mapped_column(Text)
    # Privacidade: nasce privada. Reservado para compartilhamento futuro (V3).
    is_private: Mapped[bool] = mapped_column(Boolean, server_default=sql_text("true"))
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class JourneyMemory(Base):
    """Vinculo ordenado entre uma journey e uma memory.

    A memory continua existindo sozinha. Apagar/remover este vinculo nao apaga a
    memory; apagar a journey tambem nao apaga as memories.
    """

    __tablename__ = "journey_memories"

    __table_args__ = (
        Index(
            "ix_journey_memories_journey_active",
            "journey_id",
            postgresql_where=sql_text("deleted_at IS NULL"),
        ),
        # Uma memória pode estar vinculada a, no máximo, UMA jornada ativa por vez
        # (MVP: um ponto em uma jornada só). Desvincular faz soft-delete do vínculo
        # (deleted_at) e libera a memória para outra jornada depois.
        Index(
            "uq_journey_memories_memory_active",
            "memory_id",
            unique=True,
            postgresql_where=sql_text("deleted_at IS NULL"),
        ),
        Index(
            "uq_journey_memories_position_active",
            "journey_id",
            "position",
            unique=True,
            postgresql_where=sql_text("deleted_at IS NULL"),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        server_default=sql_text("gen_random_uuid()"),
    )
    journey_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("journeys.id", ondelete="CASCADE"),
    )
    memory_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("memories.id", ondelete="CASCADE"),
    )
    position: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
