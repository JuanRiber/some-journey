"""Model ORM da fila de arquivos a apagar (tabela 'pending_file_deletions').

Foto, capa e avatar moram no Storage; no banco fica só o caminho. Apagar a
linha e o arquivo são duas operações em dois sistemas, e não há transação que
cubra as duas. A ordem ingênua — apaga a linha, depois o arquivo — tem um modo
de falha que não deixa rastro: se o Storage não responder, o arquivo continua
lá e ninguém mais sabe o caminho dele. Uma foto que a pessoa mandou apagar
ficaria guardada para sempre, sem nenhuma linha que leve até ela.

Por isso o caminho é escrito AQUI na mesma transação que apaga a linha. O
arquivo é removido depois; se falhar, o caminho continua na fila e a próxima
passada tenta de novo (ver app/services/purge_service.py).

Sem `user_id` de propósito: quando a conta é excluída, a pessoa deixa de
existir no banco, e o que resta a fazer é apagar arquivos — não saber de quem.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, Index, Integer, Text, Uuid, func, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class PendingFileDeletion(Base):
    __tablename__ = "pending_file_deletions"
    __table_args__ = (
        # A fila é lida do que foi menos tentado para o mais tentado, e do mais
        # antigo para o mais novo: um arquivo que nunca sai não trava os outros.
        Index("ix_pending_file_deletions_queue", "attempts", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )

    # Caminho do objeto dentro do bucket.
    path: Mapped[str] = mapped_column(Text)

    # Quantas vezes o Storage recusou ou não respondeu.
    attempts: Mapped[int] = mapped_column(Integer, server_default=text("0"))

    last_attempt_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )

    def __repr__(self) -> str:
        return f"<PendingFileDeletion id={self.id!r} attempts={self.attempts!r}>"
