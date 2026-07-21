"""Model ORM do token de recuperação de senha (tabela 'password_reset_tokens').

Fluxo seguro (o raw token NUNCA é gravado):
- POST /auth/forgot-password gera um token aleatório de alta entropia
  (secrets.token_urlsafe) e guarda AQUI apenas o SHA-256 dele (token_hash) +
  a validade (expires_at). O token cru só existe no link enviado por e-mail.
- POST /auth/reset-password recebe o token cru, calcula o mesmo SHA-256 e busca
  por token_hash (índice único). Um token é de USO ÚNICO: ao consumir, grava
  used_at; tokens expirados ou já usados são recusados.

Por que SHA-256 (e não argon2): o token é um segredo de 256 bits gerado por nós,
não uma senha escolhida por humano — não há dicionário a atacar, então um hash
rápido resistente a pré-imagem basta e mantém o lookup por índice O(log n).
Guardar só o hash garante que um vazamento da tabela não permita redefinir senhas.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Uuid, func, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )

    # Dono do token. CASCADE: apagar o usuário limpa seus tokens.
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
    )

    # SHA-256 (hex, 64 chars) do token cru. Único: o lookup do reset é por ele.
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)

    # Validade (TIMESTAMPTZ). Depois disto o token não vale mais.
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    # Marca o consumo (uso único). NULL = ainda não usado.
    used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )

    def __repr__(self) -> str:
        # Nunca expõe o hash nem o user_id em texto — só o id do registro.
        return f"<PasswordResetToken id={self.id!r} used={self.used_at is not None}>"
