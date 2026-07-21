"""Repository dos tokens de recuperação de senha (acesso a dados).

Camada fina sobre password_reset_tokens. Nunca vê o token cru — só o SHA-256
(token_hash) que o service calcula. Regras de ouro do módulo:
- Buscar sempre por token_hash (índice único).
- Um token válido é: não usado (used_at IS NULL) E não expirado (expires_at > now()).
- Consumir é atômico com a troca de senha (o service comita tudo junto).
"""

import uuid
from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy import update as sa_update
from sqlalchemy.orm import Session

from app.models.password_reset import PasswordResetToken


def invalidate_user_tokens(db: Session, *, user_id: uuid.UUID) -> None:
    """Marca como usados todos os tokens ativos do usuário (sem commit próprio).

    Chamado antes de emitir um novo (só um token vivo por vez) e ao concluir um
    reset (invalida quaisquer outros pendentes). O commit é do caller."""
    db.execute(
        sa_update(PasswordResetToken)
        .where(
            PasswordResetToken.user_id == user_id,
            PasswordResetToken.used_at.is_(None),
        )
        .values(used_at=func.now())
    )


def create(
    db: Session, *, user_id: uuid.UUID, token_hash: str, expires_at: datetime
) -> PasswordResetToken:
    """Emite um novo token (commit próprio). Assume que os antigos já foram
    invalidados pelo service no mesmo fluxo."""
    token = PasswordResetToken(
        user_id=user_id, token_hash=token_hash, expires_at=expires_at
    )
    db.add(token)
    db.commit()
    db.refresh(token)
    return token


def get_valid_by_hash(db: Session, *, token_hash: str) -> PasswordResetToken | None:
    """Token AINDA VÁLIDO (não usado e não expirado) para o hash dado, ou None.

    A comparação de expiração é feita no banco (func.now()) para não depender do
    relógio do processo — a mesma fonte de tempo que gravou expires_at."""
    return db.scalar(
        select(PasswordResetToken).where(
            PasswordResetToken.token_hash == token_hash,
            PasswordResetToken.used_at.is_(None),
            PasswordResetToken.expires_at > func.now(),
        )
    )
