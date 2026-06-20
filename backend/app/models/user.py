import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, String, Text, Uuid, func, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class User(Base):
    """Model ORM da tabela 'users' (cadastro de pessoas na plataforma).

    Estilo SQLAlchemy 2.0 moderno: Mapped[...] + mapped_column(...). A
    nullability é inferida pelo type hint -> Mapped[T] vira NOT NULL;
    Mapped[T | None] seria nullable. Como todo o schema é NOT NULL, nenhuma
    coluna usa T | None. Os defaults vêm do BANCO (server_default), nunca de
    objetos Python avaliados no momento do import.

    Segurança: o model PODE conter password_hash (a tabela precisa dele), mas
    NÃO é a fronteira de exposição — garantir que o hash nunca saia pela API é
    responsabilidade do schema Pydantic de saída e do endpoint. O id é UUID
    nativo gerado pelo banco (evita enumeração e já é o formato das futuras
    FKs de ownership: user_id UUID REFERENCES users(id)).
    """

    __tablename__ = "users"

    # UUID NATIVO gerado pelo BANCO (gen_random_uuid(), nativo no PG 13+).
    # Quem gera é o banco (server_default), não o app -> sem default=uuid.uuid4.
    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )

    # Nome de exibição da pessoa.
    name: Mapped[str] = mapped_column(String(120))

    # E-mail único de login. unique=True já cria índice btree no Postgres,
    # por isso não usamos index=True (evita índice redundante).
    email: Mapped[str] = mapped_column(String(255), unique=True)

    # Hash da senha. NUNCA texto puro e NUNCA retornado pela API/log — a coluna
    # existe aqui só porque a persistência precisa dela.
    password_hash: Mapped[str] = mapped_column(Text)

    # Timestamps timezone-aware (TIMESTAMPTZ). server_default=func.now() é
    # avaliado por linha no servidor (não congela um instante no import).
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )

    # updated_at: o banco preenche no INSERT; o ORM dispara onupdate a cada
    # UPDATE feito pela sessão. UPDATE cru fora do ORM não toca a coluna
    # (exigiria trigger no banco).
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )

    # Conta ativa por padrão; soft-disable (false) preserva as FKs de ownership.
    # server_default é text("true") (literal SQL), não o bool Python True.
    is_active: Mapped[bool] = mapped_column(
        Boolean,
        server_default=text("true"),
    )

    def __repr__(self) -> str:
        # Repr seguro: nunca password_hash nem e-mail (PII vaza em logs/tracebacks).
        return f"<User id={self.id!r} is_active={self.is_active!r}>"
