"""Serviço das fases da vida: aplica as regras, delega o resto.

Não conhece HTTP. Sinaliza com exceções de domínio que a rota traduz em
status — o mesmo arranjo dos outros serviços.
"""

import uuid

from sqlalchemy import update
from sqlalchemy.orm import Session

from app.domain.life_phase import validate_color, validate_name, validate_period
from app.models.journey import Journey
from app.models.life_phase import LifePhase
from app.models.memory import Memory
from app.repositories import life_phase_repository
from app.schemas.life_phase import LifePhaseCreate, LifePhaseUpdate


class PhaseNotFoundError(Exception):
    """Fase inexistente OU de outra pessoa — a rota responde 404 nos dois
    casos, para quem sonda ids não descobrir quais existem."""


def list_phases(db: Session, *, user_id: uuid.UUID) -> list[LifePhase]:
    return life_phase_repository.list_for_user(db, user_id=user_id)


def get_phase(db: Session, *, phase_id: uuid.UUID, user_id: uuid.UUID) -> LifePhase:
    fase = life_phase_repository.get_owned(db, phase_id=phase_id, user_id=user_id)
    if fase is None:
        raise PhaseNotFoundError()
    return fase


def owned_phase_id(
    db: Session, *, user_id: uuid.UUID, phase_id: uuid.UUID | None
) -> uuid.UUID | None:
    """O id que um vínculo pode gravar: o da fase, ou None para soltar.

    É a única porta por onde uma memória ou jornada ganha fase. Sem ela, um
    `life_phase_id` qualquer no corpo do POST amarraria a lembrança à fase de
    OUTRA pessoa — a FK aceitaria, porque a fase existe. A de outra pessoa, a
    apagada e a inexistente levantam o mesmo erro, pelo motivo de sempre.
    """
    if phase_id is None:
        return None
    return get_phase(db, phase_id=phase_id, user_id=user_id).id


def create_phase(db: Session, *, user_id: uuid.UUID, data: LifePhaseCreate) -> LifePhase:
    nome = validate_name(data.name)
    cor = validate_color(data.color)
    validate_period(data.started_at, data.ended_at)
    descricao = (data.description or "").strip() or None
    return life_phase_repository.create(
        db,
        user_id=user_id,
        name=nome,
        description=descricao,
        color=cor,
        started_at=data.started_at,
        ended_at=data.ended_at,
    )


def update_phase(
    db: Session, *, phase_id: uuid.UUID, user_id: uuid.UUID, data: LifePhaseUpdate
) -> LifePhase:
    """Edição parcial, com `null` significando LIMPAR.

    `model_fields_set` é o que distingue "não mandou" de "mandou null" — sem
    isso não haveria como uma fase que ganhou fim por engano voltar a ser a
    fase em curso, porque para data não existe o truque da string vazia.
    """
    fase = get_phase(db, phase_id=phase_id, user_id=user_id)
    enviados = data.model_fields_set

    if "name" in enviados and data.name is not None:
        fase.name = validate_name(data.name)
    if "color" in enviados:
        fase.color = validate_color(data.color)
    if "description" in enviados:
        fase.description = (data.description or "").strip() or None
    if "started_at" in enviados:
        fase.started_at = data.started_at
    if "ended_at" in enviados:
        fase.ended_at = data.ended_at

    validate_period(fase.started_at, fase.ended_at)
    return life_phase_repository.save(db, phase=fase)


def delete_phase(db: Session, *, phase_id: uuid.UUID, user_id: uuid.UUID) -> None:
    """Apaga a fase e SOLTA o que apontava para ela.

    A etiqueta não leva a lembrança junto: memórias e jornadas da fase apagada
    voltam a não ter fase, e continuam inteiras. O banco faria isso sozinho
    num DELETE de verdade (ON DELETE SET NULL), mas aqui o apagar é suave —
    então quem desfaz os vínculos é este serviço, explicitamente.
    """
    fase = get_phase(db, phase_id=phase_id, user_id=user_id)
    for modelo in (Memory, Journey):
        db.execute(
            update(modelo)
            .where(modelo.life_phase_id == fase.id)
            .values(life_phase_id=None)
        )
    life_phase_repository.soft_delete(db, phase=fase)
