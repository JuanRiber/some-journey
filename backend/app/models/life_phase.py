"""Model ORM da tabela 'life_phases' — os capítulos de uma vida."""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Text, Uuid, func
from sqlalchemy import text as sql_text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class LifePhase(Base):
    """Uma fase da vida: nome, período opcional e uma cor da paleta.

    Pertence a uma pessoa (`user_id`) e nunca é vista por outra — o isolamento
    é o mesmo de memórias e jornadas, imposto no repository.

    `deleted_at` para apagar sem perder: uma fase excluída solta as memórias e
    jornadas que apontavam para ela (a FK vira NULL), mas o registro fica, do
    mesmo jeito que acontece com jornada.
    """

    __tablename__ = "life_phases"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), primary_key=True, server_default=sql_text("gen_random_uuid()")
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )

    name: Mapped[str] = mapped_column(String(60))
    description: Mapped[str | None] = mapped_column(Text)

    # Papel da paleta (primary, secondary, accent, moss, highlight) — nunca um
    # hexadecimal solto, que quebraria o contraste num dos dois modos.
    color: Mapped[str] = mapped_column(String(20), server_default=sql_text("'accent'"))

    # Os dois são opcionais: nem toda pessoa sabe quando uma fase começou, e a
    # fase em curso não terminou.
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
