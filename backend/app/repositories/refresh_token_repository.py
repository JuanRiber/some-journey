"""Repository dos refresh tokens (acesso a dados).

Camada fina sobre `refresh_tokens`. Nunca vê o token cru — só o SHA-256 que o
service calcula. NENHUMA função daqui comita: emitir, trocar e revogar andam na
mesma transação de quem chama (a troca de senha revoga as sessões no MESMO
commit do hash novo, ou a conta ficaria um instante com senha nova e sessões
velhas).
"""

import uuid
from datetime import datetime, timedelta

from sqlalchemy import delete, func, or_, select
from sqlalchemy import update as sa_update
from sqlalchemy.orm import Session

from app.models.refresh_token import RefreshToken

# Tokens já trocados ou revogados só servem para detectar reuso, e por pouco
# tempo. Passado isto saem na faxina feita a cada emissão.
_KEEP_SPENT_FOR = timedelta(days=1)


def create(
    db: Session,
    *,
    user_id: uuid.UUID,
    family_id: uuid.UUID,
    token_hash: str,
    expires_at: datetime,
) -> RefreshToken:
    """Emite um token na família dada (sem commit)."""
    token = RefreshToken(
        user_id=user_id,
        family_id=family_id,
        token_hash=token_hash,
        expires_at=expires_at,
    )
    db.add(token)
    db.flush()
    return token


def get_by_hash(db: Session, *, token_hash: str) -> RefreshToken | None:
    """O token do hash dado, em QUALQUER estado — quem decide se ele ainda
    vale é o service, que precisa distinguir "usado" de "nunca existiu"."""
    return db.scalar(select(RefreshToken).where(RefreshToken.token_hash == token_hash))


def mark_used(db: Session, *, token_id: uuid.UUID) -> bool:
    """Consome o token, se ele ainda for o vigente. Devolve se consumiu.

    O `WHERE used_at IS NULL` é o que decide a corrida entre duas trocas
    simultâneas do mesmo token: o Postgres trava a linha, a primeira grava, e a
    segunda não encontra mais o que atualizar."""
    result = db.execute(
        sa_update(RefreshToken)
        .where(
            RefreshToken.id == token_id,
            RefreshToken.used_at.is_(None),
            RefreshToken.revoked_at.is_(None),
        )
        .values(used_at=func.now())
    )
    return result.rowcount == 1


def revoke_family(db: Session, *, family_id: uuid.UUID) -> None:
    """Encerra uma sessão: revoga todo token ainda não revogado da família."""
    db.execute(
        sa_update(RefreshToken)
        .where(
            RefreshToken.family_id == family_id,
            RefreshToken.revoked_at.is_(None),
        )
        .values(revoked_at=func.now())
    )


def revoke_all_for_user(db: Session, *, user_id: uuid.UUID) -> None:
    """Encerra TODAS as sessões da pessoa (troca ou redefinição de senha)."""
    db.execute(
        sa_update(RefreshToken)
        .where(
            RefreshToken.user_id == user_id,
            RefreshToken.revoked_at.is_(None),
        )
        .values(revoked_at=func.now())
    )


def purge_stale_for_user(db: Session, *, user_id: uuid.UUID) -> None:
    """Apaga o que não serve mais da pessoa: vencidos, e trocados ou revogados
    há mais de um dia. Sem isto a tabela ganharia uma linha por hora, por
    aparelho, para sempre."""
    limite = func.now() - _KEEP_SPENT_FOR
    db.execute(
        delete(RefreshToken).where(
            RefreshToken.user_id == user_id,
            or_(
                RefreshToken.expires_at < func.now(),
                RefreshToken.used_at < limite,
                RefreshToken.revoked_at < limite,
            ),
        )
    )
