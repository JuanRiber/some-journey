"""Model ORM do limite de tentativas (tabela 'auth_rate_limits').

Uma linha por BALDE — a combinação de escopo e partes que `app.core.rate_limit`
conta (login por conta+IP, por IP, por e-mail...). A linha guarda quando a
janela começou e quantas tentativas caíram nela.

Mora no banco, e não na memória do processo, por dois motivos que a memória não
resolve: um reinício (deploy, queda, o contêiner do plano grátis acordando)
zerava os baldes e devolvia a quem estava adivinhando senha uma janela nova; e
com mais de um processo cada um contava o seu, multiplicando o teto.

A chave NÃO guarda e-mail nem IP: é o SHA-256 das partes, prefixado pelo escopo.
Um vazamento desta tabela não diz quem tentou entrar nem de onde.
"""

from datetime import datetime

from sqlalchemy import DateTime, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class AuthRateLimit(Base):
    __tablename__ = "auth_rate_limits"
    __table_args__ = (
        # A faxina apaga janelas vencidas há muito; sem índice ela varreria a
        # tabela inteira a cada passada.
        Index("ix_auth_rate_limits_window_started_at", "window_started_at"),
    )

    # "<escopo>:<sha256 hex>" — ver _bucket_key em app/core/rate_limit.py.
    key: Mapped[str] = mapped_column(String(160), primary_key=True)

    # Início da janela corrente (TIMESTAMPTZ, relógio do BANCO: o mesmo para
    # todos os processos).
    window_started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    # Tentativas contadas nesta janela, incluindo as recusadas.
    attempts: Mapped[int] = mapped_column(Integer)

    def __repr__(self) -> str:
        return f"<AuthRateLimit attempts={self.attempts!r}>"
