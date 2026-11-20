"""Limite de tentativas dos endpoints de autenticação — contado no BANCO.

Era um dicionário na memória do processo. Funcionava, com duas falhas que não
aparecem em teste nenhum:

- **Reinício zerava tudo.** Deploy, queda ou o contêiner do plano grátis
  acordando: quem estava adivinhando uma senha ganhava uma janela nova a cada
  reinício da API.
- **Cada processo contava o seu.** Com `WEB_CONCURRENCY=2` o teto real dobrava,
  e por isso a API estava presa a um processo só.

Agora cada balde é uma linha em `auth_rate_limits` e a contagem é UM comando: um
`INSERT ... ON CONFLICT DO UPDATE` que abre a janela, ou a reinicia se venceu, ou
soma mais uma tentativa — e devolve o total. O Postgres trava a linha durante o
comando, então duas tentativas simultâneas nunca leem o mesmo número; e o
relógio é o do banco (`now()`), o mesmo para todo processo.

A contagem roda numa transação PRÓPRIA, fora da sessão do request: a tentativa
tem de ficar contada mesmo quando o request termina em 401 ou em erro — que é
justamente o caso que o limite existe para contar.

Se o banco estiver fora, a checagem levanta e o request falha. É o
comportamento certo: login sem banco não acontece de qualquer jeito, e um limite
que abre quando não consegue contar não é limite.
"""

from __future__ import annotations

import hashlib
from threading import Lock
from time import monotonic

from sqlalchemy import text

from app.db.session import engine

# Abre a janela, reinicia a vencida ou soma — e devolve o total e quanto falta
# para a janela acabar. `EXCLUDED` não é usado de propósito: o que decide é o
# estado da linha que já existe.
_COUNT = text(
    """
    INSERT INTO auth_rate_limits AS b (key, window_started_at, attempts)
    VALUES (:key, now(), 1)
    ON CONFLICT (key) DO UPDATE SET
        attempts = CASE
            WHEN b.window_started_at <= now() - make_interval(secs => :window)
            THEN 1 ELSE b.attempts + 1 END,
        window_started_at = CASE
            WHEN b.window_started_at <= now() - make_interval(secs => :window)
            THEN now() ELSE b.window_started_at END
    RETURNING
        attempts,
        EXTRACT(EPOCH FROM
            (window_started_at + make_interval(secs => :window) - now()))
    """
)

# Janelas vencidas há mais que isto não servem a ninguém. É bem maior que a
# maior janela configurável (AUTH_RATE_LIMIT_WINDOW_SECONDS, teto de 1 h), para
# a faxina nunca apagar um balde ainda em uso.
_PURGE_OLDER_THAN_SECONDS = 24 * 3600
_PURGE = text(
    "DELETE FROM auth_rate_limits "
    "WHERE window_started_at < now() - make_interval(secs => :older)"
)

# A faxina é oportunista: no máximo uma por processo a cada intervalo. Este é o
# único estado em memória que sobrou, e perdê-lo num reinício só adianta uma
# faxina — não muda contagem nenhuma.
_PURGE_EVERY_SECONDS = 600.0
_purge_lock = Lock()
_last_purge: float | None = None


def _bucket_key(scope: str, parts: list[str]) -> str:
    raw = "\x1f".join([scope, *parts]).encode("utf-8", errors="ignore")
    return f"{scope}:{hashlib.sha256(raw).hexdigest()}"


def check_rate_limit(
    scope: str,
    parts: list[str],
    *,
    max_attempts: int,
    window_seconds: int,
) -> tuple[bool, int]:
    """Conta esta tentativa e devolve (permitida, segundos_até_liberar).

    Toda chamada conta, inclusive a que é recusada: quem insiste depois do 429
    não ganha a vaga de volta antes de a janela acabar."""
    key = _bucket_key(scope, parts)
    with engine.begin() as conn:
        attempts, remaining = conn.execute(
            _COUNT, {"key": key, "window": window_seconds}
        ).one()
    _maybe_purge()
    if attempts <= max_attempts:
        return True, 0
    return False, max(1, int(remaining))


def _maybe_purge() -> None:
    """Apaga baldes vencidos há muito, sem pesar em cada tentativa."""
    global _last_purge
    now = monotonic()
    with _purge_lock:
        if _last_purge is not None and now - _last_purge < _PURGE_EVERY_SECONDS:
            return
        _last_purge = now
    purge_expired()


def purge_expired() -> int:
    """Remove as janelas vencidas há mais de um dia. Devolve quantas saíram."""
    with engine.begin() as conn:
        return conn.execute(
            _PURGE, {"older": _PURGE_OLDER_THAN_SECONDS}
        ).rowcount
