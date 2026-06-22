"""Serviço de Memórias: orquestra as regras de negócio e converte o model
(geográfico) no schema de saída (lat/long).

Não conhece HTTP: sinaliza ausência com a exceção de domínio
MemoryNotFoundError, que a camada de rotas traduz em 404 (sem revelar se a
memória existe e é de outro — anti-enumeração). Todo acesso passa pelo
repository, que já filtra por user_id (ownership) e deleted_at (soft delete).
"""

import uuid

from geoalchemy2.shape import to_shape
from sqlalchemy.orm import Session

from app.models.memory import Memory
from app.repositories import memory_repository
from app.schemas.memory import MemoryCreate, MemoryRead, MemoryUpdate


class MemoryNotFoundError(Exception):
    """Memória inexistente ou de outro usuário — a rota traduz em 404."""


def _to_read(memory: Memory) -> MemoryRead:
    """Converte o model (location = POINT(long, lat)) no DTO de saída (lat/long).

    to_shape devolve um Point do shapely: x = longitude, y = latitude. É aqui
    que o GEOGRAPHY volta a virar linguagem humana pra API.
    """
    point = to_shape(memory.location)
    return MemoryRead(
        id=memory.id,
        title=memory.title,
        text=memory.text,
        latitude=point.y,
        longitude=point.x,
        occurred_at=memory.occurred_at,
        created_at=memory.created_at,
        image_url=None,  # URL temporária do Storage entra num bloco futuro
    )


def create(db: Session, *, user_id: uuid.UUID, data: MemoryCreate) -> MemoryRead:
    memory = memory_repository.create(
        db,
        user_id=user_id,
        title=data.title,
        text=data.text,
        latitude=data.latitude,
        longitude=data.longitude,
        occurred_at=data.occurred_at,
    )
    return _to_read(memory)


def list_for_user(db: Session, *, user_id: uuid.UUID) -> list[MemoryRead]:
    return [_to_read(m) for m in memory_repository.list_by_user(db, user_id=user_id)]


def get(db: Session, *, user_id: uuid.UUID, memory_id: uuid.UUID) -> MemoryRead:
    memory = memory_repository.get_by_id(db, user_id=user_id, memory_id=memory_id)
    if memory is None:
        raise MemoryNotFoundError()
    return _to_read(memory)


def update(
    db: Session, *, user_id: uuid.UUID, memory_id: uuid.UUID, data: MemoryUpdate
) -> MemoryRead:
    memory = memory_repository.get_by_id(db, user_id=user_id, memory_id=memory_id)
    if memory is None:
        raise MemoryNotFoundError()
    # exclude_unset: só os campos realmente enviados chegam ao repository.
    updated = memory_repository.update(
        db, memory=memory, **data.model_dump(exclude_unset=True)
    )
    return _to_read(updated)


def delete(db: Session, *, user_id: uuid.UUID, memory_id: uuid.UUID) -> None:
    memory = memory_repository.get_by_id(db, user_id=user_id, memory_id=memory_id)
    if memory is None:
        raise MemoryNotFoundError()
    memory_repository.soft_delete(db, memory=memory)
