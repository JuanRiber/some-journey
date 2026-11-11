from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings

# O engine é o ponto central de comunicação com o PostgreSQL.
# Ele gerencia um "pool" de conexões reutilizáveis.
# pool_pre_ping testa se a conexão está viva antes de usá-la,
# evitando erros quando o banco fechou uma conexão ociosa.
# O tamanho do pool vem da configuração (DB_POOL_SIZE / DB_MAX_OVERFLOW): em
# produção o banco fica atrás de um pooler com poucas vagas.
engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,
    pool_size=settings.DB_POOL_SIZE,
    max_overflow=settings.DB_MAX_OVERFLOW,
)

# SessionLocal é uma "fábrica" de sessões.
# Cada chamada SessionLocal() abre uma nova sessão (uma "conversa" com o banco).
SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
)


def get_db() -> Generator[Session, None, None]:
    """Dependency do FastAPI: entrega uma sessão por request e garante o fechamento."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
