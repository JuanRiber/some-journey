import uuid
from datetime import datetime

from geoalchemy2 import Geography
from geoalchemy2.elements import WKBElement
from sqlalchemy import DateTime, ForeignKey, Index, String, Text, Uuid, func
from sqlalchemy import text as sql_text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Memory(Base):
    """Model ORM da tabela 'memories': um acontecimento humano preso a um lugar
    e a um momento.

    Pertence a um usuário (ownership via user_id). Exclusão é LÓGICA
    (deleted_at) — toda consulta deve filtrar deleted_at IS NULL. Estilo
    SQLAlchemy 2.0 (Mapped/mapped_column); defaults vêm do banco (server_default).
    """

    __tablename__ = "memories"

    # Índice parcial: acelera "listar minhas memórias ativas" (query mais comum).
    __table_args__ = (
        Index(
            "ix_memories_user_active",
            "user_id",
            postgresql_where=sql_text("deleted_at IS NULL"),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        server_default=sql_text("gen_random_uuid()"),
    )

    # Dono da memória. ON DELETE CASCADE: se o usuário for removido de vez, as
    # memórias vão junto (no MVP o usuário é desativado, não removido).
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
    )

    title: Mapped[str] = mapped_column(String(120))
    text: Mapped[str] = mapped_column(Text)

    # Geography(POINT, 4326): armazenado como POINT(longitude, latitude).
    # GeoAlchemy2 cria um índice espacial GiST automaticamente (spatial_index).
    location: Mapped[WKBElement] = mapped_column(
        Geography(geometry_type="POINT", srid=4326)
    )

    # Apenas o caminho no Storage (bucket privado) — nunca uma URL pública.
    # Não é preenchido pelo POST /memories: upload é fluxo separado do backend.
    image_path: Mapped[str | None] = mapped_column(Text)

    # Quando a memória ACONTECEU (alimenta a timeline) — pode ser no passado.
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    # Quando foi cadastrada e editada pela última vez.
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    # Exclusão lógica (soft delete). NULL = ativa.
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
