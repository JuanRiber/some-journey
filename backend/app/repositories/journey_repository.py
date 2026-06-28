import uuid
from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.journey import Journey, JourneyMemory
from app.models.memory import Memory


def create_journey(
    db: Session,
    *,
    user_id: uuid.UUID,
    title: str,
    description: str | None,
    started_at: datetime | None,
) -> Journey:
    journey = Journey(
        user_id=user_id,
        title=title,
        description=description,
        started_at=started_at,
    )
    db.add(journey)
    db.commit()
    db.refresh(journey)
    return journey


def list_journeys(db: Session, *, user_id: uuid.UUID) -> list[tuple[Journey, int]]:
    rows = db.execute(
        select(Journey, func.count(Memory.id))
        .outerjoin(
            JourneyMemory,
            (JourneyMemory.journey_id == Journey.id)
            & (JourneyMemory.deleted_at.is_(None)),
        )
        .outerjoin(
            Memory,
            (Memory.id == JourneyMemory.memory_id)
            & (Memory.user_id == user_id)
            & (Memory.deleted_at.is_(None)),
        )
        .where(Journey.user_id == user_id, Journey.deleted_at.is_(None))
        .group_by(Journey.id)
        .order_by(Journey.created_at.desc())
    )
    return [(journey, int(points_count)) for journey, points_count in rows]


def get_journey(
    db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID
) -> Journey | None:
    return db.scalar(
        select(Journey).where(
            Journey.id == journey_id,
            Journey.user_id == user_id,
            Journey.deleted_at.is_(None),
        )
    )


def has_active_journey(
    db: Session, *, user_id: uuid.UUID, exclude_journey_id: uuid.UUID | None = None
) -> bool:
    stmt = select(Journey.id).where(
        Journey.user_id == user_id,
        Journey.status == "active",
        Journey.deleted_at.is_(None),
    )
    if exclude_journey_id is not None:
        stmt = stmt.where(Journey.id != exclude_journey_id)
    return db.scalar(stmt) is not None


def set_status(
    db: Session,
    *,
    journey: Journey,
    status: str,
    started_at: datetime | None = None,
    ended_at: datetime | None = None,
) -> Journey:
    journey.status = status
    if started_at is not None:
        journey.started_at = started_at
    if ended_at is not None:
        journey.ended_at = ended_at
    db.commit()
    db.refresh(journey)
    return journey


def points_count(db: Session, *, journey_id: uuid.UUID, user_id: uuid.UUID) -> int:
    return int(
        db.scalar(
            select(func.count(JourneyMemory.id))
            .join(Memory, Memory.id == JourneyMemory.memory_id)
            .where(
                JourneyMemory.journey_id == journey_id,
                JourneyMemory.deleted_at.is_(None),
                Memory.user_id == user_id,
                Memory.deleted_at.is_(None),
            )
        )
        or 0
    )


def next_position(db: Session, *, journey_id: uuid.UUID) -> int:
    value = db.scalar(
        select(func.max(JourneyMemory.position)).where(
            JourneyMemory.journey_id == journey_id,
            JourneyMemory.deleted_at.is_(None),
        )
    )
    return int(value or 0) + 1


def get_journey_memory(
    db: Session, *, journey_id: uuid.UUID, memory_id: uuid.UUID
) -> JourneyMemory | None:
    return db.scalar(
        select(JourneyMemory).where(
            JourneyMemory.journey_id == journey_id,
            JourneyMemory.memory_id == memory_id,
            JourneyMemory.deleted_at.is_(None),
        )
    )


def get_active_link_for_memory(
    db: Session, *, memory_id: uuid.UUID
) -> JourneyMemory | None:
    """Vínculo ativo da memória em QUALQUER jornada (MVP: uma memória só pode
    estar numa jornada por vez). None se ela está solta."""
    return db.scalar(
        select(JourneyMemory).where(
            JourneyMemory.memory_id == memory_id,
            JourneyMemory.deleted_at.is_(None),
        )
    )


def unlink_memory(db: Session, *, link: JourneyMemory) -> None:
    """Soft-delete do vínculo jornada↔memória. NÃO apaga a memória — só a remove
    da jornada e libera a posição/uniqueness para um novo vínculo."""
    link.deleted_at = func.now()
    db.commit()


def add_memory(
    db: Session, *, journey_id: uuid.UUID, memory_id: uuid.UUID, position: int
) -> JourneyMemory:
    item = JourneyMemory(
        journey_id=journey_id,
        memory_id=memory_id,
        position=position,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


def add_memory_pending(
    db: Session, *, journey_id: uuid.UUID, memory_id: uuid.UUID, position: int
) -> JourneyMemory:
    item = JourneyMemory(
        journey_id=journey_id,
        memory_id=memory_id,
        position=position,
    )
    db.add(item)
    db.flush()
    db.refresh(item)
    return item


def list_points(
    db: Session, *, journey_id: uuid.UUID, user_id: uuid.UUID
) -> list[tuple[JourneyMemory, Memory]]:
    rows = db.execute(
        select(JourneyMemory, Memory)
        .join(Memory, Memory.id == JourneyMemory.memory_id)
        .where(
            JourneyMemory.journey_id == journey_id,
            JourneyMemory.deleted_at.is_(None),
            Memory.user_id == user_id,
            Memory.deleted_at.is_(None),
        )
        .order_by(JourneyMemory.position.asc())
    )
    return list(rows)


def reorder(
    db: Session, *, items: list[JourneyMemory], positions: dict[uuid.UUID, int]
) -> None:
    for item in items:
        item.position = -positions[item.memory_id]
    db.flush()
    for item in items:
        item.position = positions[item.memory_id]
    db.commit()


def soft_delete(db: Session, *, journey: Journey) -> None:
    journey.deleted_at = func.now()
    db.commit()
