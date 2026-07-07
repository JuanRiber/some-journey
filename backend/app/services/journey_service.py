import uuid
from datetime import UTC, datetime

from geoalchemy2.shape import to_shape
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.journey import Journey
from app.models.memory import Memory
from app.repositories import journey_repository, memory_repository
from app.schemas.memory import MemoryRead
from app.services import memory_service
from app.schemas.journey import (
    JourneyCreate,
    JourneyDetailRead,
    JourneyFinish,
    JourneyMemoryAdd,
    JourneyMemoryCreate,
    JourneyPointRead,
    JourneyRead,
    JourneyReorder,
    JourneyRoute,
    JourneyUpdate,
)


class JourneyNotFoundError(Exception):
    """Journey ou memory inexistente, apagada ou de outro usuario."""


class ActiveJourneyExistsError(Exception):
    """Ja existe outra journey ativa para o usuario."""


class MemoryAlreadyInJourneyError(Exception):
    """A memory ja pertence a uma journey (MVP: um ponto em uma journey so)."""


class JourneyClosedError(Exception):
    """Nao da pra adicionar pontos numa journey finished (encerrada)."""


class JourneyLinkNotFoundError(Exception):
    """A memory nao esta vinculada a esta journey."""


class JourneyConflictError(Exception):
    """Backstop de concorrencia: o banco recusou por violar uma constraint
    (posicao/uniqueness) numa corrida. A rota traduz em 409."""


class InvalidJourneyTransitionError(Exception):
    """Transicao de status invalida para o estado atual da journey."""


class InvalidJourneyReorderError(Exception):
    """A reordenacao precisa conter exatamente os pontos atuais."""


# Transicoes de status permitidas a partir do estado atual. Qualquer outra vira
# 409 (InvalidJourneyTransitionError). 'finished' e terminal.
_ALLOWED_FROM = {
    "start": {"draft"},
    "pause": {"active"},
    "resume": {"paused"},
    "finish": {"active", "paused"},
}


def _ensure_transition(journey: Journey, action: str) -> None:
    if journey.status not in _ALLOWED_FROM[action]:
        raise InvalidJourneyTransitionError(
            f"journey em '{journey.status}' nao permite '{action}'"
        )


def _journey_to_read(journey: Journey, points_count: int) -> JourneyRead:
    return JourneyRead(
        id=journey.id,
        title=journey.title,
        description=journey.description,
        mood=journey.mood,
        is_private=journey.is_private,
        # Capa de jornada ainda não tem upload próprio; expomos o contrato como
        # None para o cliente já poder tratar (placeholder editorial).
        cover_image_url=None,
        status=journey.status,  # type: ignore[arg-type]
        started_at=journey.started_at,
        ended_at=journey.ended_at,
        points_count=points_count,
        created_at=journey.created_at,
    )


def _point_to_read(memory: Memory, position: int) -> JourneyPointRead:
    point = to_shape(memory.location)
    return JourneyPointRead(
        memory_id=memory.id,
        position=position,
        title=memory.title,
        text=memory.text,
        latitude=point.y,
        longitude=point.x,
        occurred_at=memory.occurred_at,
        created_at=memory.created_at,
    )


def _build_route(points: list[JourneyPointRead]) -> JourneyRoute | None:
    """Rastro do mapa. Um LineString GeoJSON exige >= 2 posicoes; com 0 ou 1
    ponto nao ha rastro (retorna None — o front desenha so os pins)."""
    if len(points) < 2:
        return None
    return JourneyRoute(
        coordinates=[[point.longitude, point.latitude] for point in points]
    )


def _detail(db: Session, *, user_id: uuid.UUID, journey: Journey) -> JourneyDetailRead:
    rows = journey_repository.list_points(db, journey_id=journey.id, user_id=user_id)
    points = [_point_to_read(memory, item.position) for item, memory in rows]
    base = _journey_to_read(journey, len(points))
    return JourneyDetailRead(
        **base.model_dump(), points=points, route=_build_route(points)
    )


def create(db: Session, *, user_id: uuid.UUID, data: JourneyCreate) -> JourneyRead:
    journey = journey_repository.create_journey(
        db,
        user_id=user_id,
        title=data.title,
        description=data.description,
        mood=data.mood,
        is_private=data.is_private,
        started_at=data.started_at,
        ended_at=data.ended_at,
    )
    return _journey_to_read(journey, 0)


def list_memories(
    db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID
) -> list[MemoryRead]:
    """Memórias da jornada em ordem CRONOLÓGICA (por occurred_at) — a timeline
    da jornada. 404 se a jornada não é do usuário. Reaproveita o builder de
    memórias (assina as fotos em lote), então cada item já traz image_url."""
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is None:
        raise JourneyNotFoundError()
    memories = journey_repository.list_memories_chronological(
        db, journey_id=journey.id, user_id=user_id
    )
    return memory_service.reads_for(db, memories)


def update(
    db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID, data: JourneyUpdate
) -> JourneyRead:
    """Edita título/descrição da jornada (metadados). Permitido em qualquer
    status — não é uma transição de ciclo de vida. 404 se não é do usuário."""
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is None:
        raise JourneyNotFoundError()
    updated = journey_repository.update_journey(
        db, journey=journey, **data.model_dump(exclude_unset=True)
    )
    return _read_with_count(db, user_id=user_id, journey=updated)


def list_for_user(db: Session, *, user_id: uuid.UUID) -> list[JourneyRead]:
    return [
        _journey_to_read(journey, points_count)
        for journey, points_count in journey_repository.list_journeys(
            db, user_id=user_id
        )
    ]


def get(db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID) -> JourneyDetailRead:
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is None:
        raise JourneyNotFoundError()
    return _detail(db, user_id=user_id, journey=journey)


def _read_with_count(
    db: Session, *, user_id: uuid.UUID, journey: Journey
) -> JourneyRead:
    return _journey_to_read(
        journey,
        journey_repository.points_count(db, journey_id=journey.id, user_id=user_id),
    )


def _activate(
    db: Session, *, user_id: uuid.UUID, journey: Journey, action: str
) -> JourneyRead:
    """Leva a journey para 'active' (start de draft ou resume de paused),
    garantindo que nao haja outra ativa. O indice parcial unico no banco e o
    backstop final caso duas requisicoes corram ao mesmo tempo."""
    _ensure_transition(journey, action)
    if journey_repository.has_active_journey(
        db, user_id=user_id, exclude_journey_id=journey.id
    ):
        raise ActiveJourneyExistsError()
    started_at = journey.started_at or datetime.now(UTC)
    try:
        updated = journey_repository.set_status(
            db, journey=journey, status="active", started_at=started_at
        )
    except IntegrityError as exc:
        db.rollback()
        raise ActiveJourneyExistsError() from exc
    return _read_with_count(db, user_id=user_id, journey=updated)


def start(db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID) -> JourneyRead:
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is None:
        raise JourneyNotFoundError()
    return _activate(db, user_id=user_id, journey=journey, action="start")


def resume(db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID) -> JourneyRead:
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is None:
        raise JourneyNotFoundError()
    return _activate(db, user_id=user_id, journey=journey, action="resume")


def pause(db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID) -> JourneyRead:
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is None:
        raise JourneyNotFoundError()
    _ensure_transition(journey, "pause")
    updated = journey_repository.set_status(db, journey=journey, status="paused")
    return _read_with_count(db, user_id=user_id, journey=updated)


def finish(
    db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID, data: JourneyFinish
) -> JourneyRead:
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is None:
        raise JourneyNotFoundError()
    _ensure_transition(journey, "finish")
    ended_at = data.ended_at or datetime.now(UTC)
    updated = journey_repository.set_status(
        db, journey=journey, status="finished", ended_at=ended_at
    )
    return _read_with_count(db, user_id=user_id, journey=updated)


def _ensure_open(journey: Journey) -> None:
    """Journey 'finished' e terminal: nao recebe novos pontos."""
    if journey.status == "finished":
        raise JourneyClosedError()


def add_existing_memory(
    db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID, data: JourneyMemoryAdd
) -> JourneyDetailRead:
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    memory = memory_repository.get_by_id(db, user_id=user_id, memory_id=data.memory_id)
    if journey is None or memory is None:
        raise JourneyNotFoundError()
    _ensure_open(journey)
    # MVP: um ponto em uma journey so. Se a memory ja esta vinculada a qualquer
    # journey ativa, recusa (precisa desvincular antes).
    if journey_repository.get_active_link_for_memory(db, memory_id=memory.id):
        raise MemoryAlreadyInJourneyError()
    try:
        journey_repository.add_memory(
            db,
            journey_id=journey.id,
            memory_id=memory.id,
            position=journey_repository.next_position(db, journey_id=journey.id),
        )
    except IntegrityError as exc:
        db.rollback()
        # Corrida com outro vinculo da mesma memory (uq por memory_id).
        raise MemoryAlreadyInJourneyError() from exc
    return _detail(db, user_id=user_id, journey=journey)


def create_memory_in_journey(
    db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID, data: JourneyMemoryCreate
) -> JourneyDetailRead:
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is None:
        raise JourneyNotFoundError()
    _ensure_open(journey)

    try:
        memory = memory_repository.create_pending(
            db,
            user_id=user_id,
            title=data.title,
            text=data.text,
            latitude=data.latitude,
            longitude=data.longitude,
            occurred_at=data.occurred_at,
        )
        journey_repository.add_memory_pending(
            db,
            journey_id=journey.id,
            memory_id=memory.id,
            position=journey_repository.next_position(db, journey_id=journey.id),
        )
        db.commit()
    except IntegrityError as exc:
        # Corrida na posicao (uq journey_id+position) entre criacoes simultaneas.
        db.rollback()
        raise JourneyConflictError() from exc
    except Exception:
        db.rollback()
        raise
    return _detail(db, user_id=user_id, journey=journey)


def unlink_memory(
    db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID, memory_id: uuid.UUID
) -> None:
    """Remove a memory da journey SEM apagar a memory (soft-delete do vinculo).
    404 se a journey nao e do usuario ou a memory nao esta vinculada a ela."""
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is None:
        raise JourneyNotFoundError()
    link = journey_repository.get_journey_memory(
        db, journey_id=journey.id, memory_id=memory_id
    )
    if link is None:
        raise JourneyLinkNotFoundError()
    journey_repository.unlink_memory(db, link=link)


def reorder_points(
    db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID, data: JourneyReorder
) -> JourneyDetailRead:
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is None:
        raise JourneyNotFoundError()
    rows = journey_repository.list_points(db, journey_id=journey.id, user_id=user_id)
    current_ids = [memory.id for _, memory in rows]
    if set(current_ids) != set(data.memory_ids) or len(current_ids) != len(data.memory_ids):
        raise InvalidJourneyReorderError()
    positions = {memory_id: index + 1 for index, memory_id in enumerate(data.memory_ids)}
    journey_repository.reorder(
        db,
        items=[item for item, _ in rows],
        positions=positions,
    )
    return _detail(db, user_id=user_id, journey=journey)


def delete(db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID) -> None:
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is None:
        raise JourneyNotFoundError()
    journey_repository.soft_delete(db, journey=journey)
