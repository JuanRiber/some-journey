"""Camada de repository das fases da vida (acesso a dados).

Mesma fronteira dos outros: só persiste e consulta. O ISOLAMENTO por usuário
mora aqui e é a razão de toda busca exigir `user_id` na assinatura — uma
função que buscasse só por id seria um convite a vazar a fase de outra pessoa
no primeiro lugar que alguém esquecesse de filtrar.
"""

import uuid
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.life_phase import LifePhase


def list_for_user(db: Session, *, user_id: uuid.UUID) -> list[LifePhase]:
    """As fases ativas da pessoa, na ordem em que a vida aconteceu.

    Quem não tem início declarado vai para o fim: a pessoa que não sabe quando
    a infância começou não deve ver essa fase encabeçando a lista por causa de
    um NULL.
    """
    consulta = (
        select(LifePhase)
        .where(LifePhase.user_id == user_id, LifePhase.deleted_at.is_(None))
        .order_by(LifePhase.started_at.asc().nullslast(), LifePhase.name.asc())
    )
    return list(db.scalars(consulta))


def get_owned(db: Session, *, phase_id: uuid.UUID, user_id: uuid.UUID) -> LifePhase | None:
    """A fase, SE for desta pessoa e não estiver apagada.

    Id de outra pessoa e id inexistente devolvem a mesma coisa (None), para a
    rota responder 404 nos dois casos — quem sonda ids não descobre quais
    existem.
    """
    return db.scalar(
        select(LifePhase).where(
            LifePhase.id == phase_id,
            LifePhase.user_id == user_id,
            LifePhase.deleted_at.is_(None),
        )
    )


def name_taken(
    db: Session, *, user_id: uuid.UUID, name: str, except_id: uuid.UUID | None = None
) -> bool:
    """Esta pessoa já tem uma fase ATIVA com este nome (sem diferenciar caixa)?

    `except_id` é a própria fase, num rename: trocar "faculdade" por
    "Faculdade" não colide com ela mesma."""
    consulta = select(LifePhase.id).where(
        LifePhase.user_id == user_id,
        LifePhase.deleted_at.is_(None),
        func.lower(LifePhase.name) == name.lower(),
    )
    if except_id is not None:
        consulta = consulta.where(LifePhase.id != except_id)
    return db.scalar(consulta.limit(1)) is not None


def create(
    db: Session,
    *,
    user_id: uuid.UUID,
    name: str,
    description: str | None,
    color: str,
    started_at: datetime | None,
    ended_at: datetime | None,
) -> LifePhase:
    fase = LifePhase(
        user_id=user_id,
        name=name,
        description=description,
        color=color,
        started_at=started_at,
        ended_at=ended_at,
    )
    db.add(fase)
    db.commit()
    db.refresh(fase)
    return fase


def save(db: Session, *, phase: LifePhase) -> LifePhase:
    db.commit()
    db.refresh(phase)
    return phase


def soft_delete(db: Session, *, phase: LifePhase) -> None:
    """Marca como apagada. As memórias e jornadas que apontavam para ela são
    soltas pelo banco (ON DELETE SET NULL não dispara em soft delete, então o
    serviço desfaz os vínculos explicitamente antes de chamar aqui)."""
    phase.deleted_at = datetime.now(UTC)
    db.commit()
