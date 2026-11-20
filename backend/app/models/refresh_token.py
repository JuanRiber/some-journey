"""Model ORM do refresh token (tabela 'refresh_tokens').

O access token (JWT) vale uma hora e não é guardado em lugar nenhum. O refresh
token é o que deixa a sessão durar mais que isso sem a pessoa digitar a senha de
novo: um segredo opaco, de vida longa, que o app troca por um par novo em
`POST /auth/refresh`.

Mesma regra do token de recuperação de senha: o valor cru NUNCA é gravado — só o
SHA-256 dele. É um segredo de alta entropia gerado por nós, então um hash rápido
basta e o lookup é por índice único. Um vazamento desta tabela não abre sessão
de ninguém.

**Rotação.** Cada refresh token vale UMA troca: ao ser usado ganha `used_at` e
nasce um sucessor na mesma `family_id`. A família é a sessão de um aparelho, do
login até o logout.

**Reuso.** Um token já trocado que reaparece (fora da folga curta que cobre duas
abas e a resposta que se perdeu no caminho) é sinal de cópia: a família inteira
é revogada, e tanto quem copiou quanto a dona caem para o login.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Uuid, func, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )

    # Dona da sessão. CASCADE: apagar o usuário encerra as sessões dele.
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
    )

    # A sessão a que este token pertence: todo sucessor herda a mesma. É por
    # ela que o logout e a detecção de reuso derrubam a cadeia inteira.
    family_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), index=True)

    # SHA-256 (hex, 64 chars) do token cru. Único: a troca busca por ele.
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)

    # Validade (TIMESTAMPTZ). O sucessor ganha validade nova: a sessão dura
    # enquanto for usada, e morre sozinha se ficar parada além disto.
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    # Marca a troca (uso único). NULL = ainda é o token vigente da família.
    used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # Revogação: logout, troca/redefinição de senha ou reuso detectado.
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )

    def __repr__(self) -> str:
        # Nunca expõe o hash nem o user_id em texto — só o id do registro.
        return (
            f"<RefreshToken id={self.id!r} used={self.used_at is not None} "
            f"revoked={self.revoked_at is not None}>"
        )
