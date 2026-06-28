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

from app.core import storage
from app.models.memory import Memory
from app.repositories import memory_repository
from app.schemas.memory import MemoryCreate, MemoryRead, MemoryUpdate

# Tipos de imagem aceitos no upload -> extensão usada no path do Storage.
_IMAGE_EXT = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}


class MemoryNotFoundError(Exception):
    """Memória inexistente ou de outro usuário — a rota traduz em 404."""


class InvalidImageError(Exception):
    """Tipo de imagem não suportado — a rota traduz em 400."""


def _to_read(memory: Memory, *, image_url: str | None = None) -> MemoryRead:
    """Converte o model (location = POINT(long, lat)) no DTO de saída (lat/long).

    to_shape devolve um Point do shapely: x = longitude, y = latitude. É aqui
    que o GEOGRAPHY volta a virar linguagem humana pra API. `image_url` é uma URL
    assinada de curta duração (None se não há imagem ou o Storage está desligado).
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
        image_url=image_url,
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
    memories = memory_repository.list_by_user(db, user_id=user_id)
    # Assina todas as imagens em UMA chamada (evita N round-trips ao Storage).
    signed = storage.sign_urls([m.image_path for m in memories if m.image_path])
    return [
        _to_read(m, image_url=signed.get(m.image_path) if m.image_path else None)
        for m in memories
    ]


def get(db: Session, *, user_id: uuid.UUID, memory_id: uuid.UUID) -> MemoryRead:
    memory = memory_repository.get_by_id(db, user_id=user_id, memory_id=memory_id)
    if memory is None:
        raise MemoryNotFoundError()
    return _to_read(memory, image_url=storage.sign_url(memory.image_path) if memory.image_path else None)


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


def attach_image(
    db: Session,
    *,
    user_id: uuid.UUID,
    memory_id: uuid.UUID,
    data: bytes,
    content_type: str,
) -> MemoryRead:
    """Sobe a imagem ao Storage e guarda o caminho na memória (do dono).

    Caminho isolado por usuário+memória: `${user_id}/${memory_id}/${rand}.${ext}`.
    Pode levantar InvalidImageError (tipo), MemoryNotFoundError (404),
    StorageNotConfigured/StorageError (propagam para a rota)."""
    ext = _IMAGE_EXT.get(content_type)
    if ext is None:
        raise InvalidImageError()
    memory = memory_repository.get_by_id(db, user_id=user_id, memory_id=memory_id)
    if memory is None:
        raise MemoryNotFoundError()
    path = f"{user_id}/{memory_id}/{uuid.uuid4().hex}.{ext}"
    storage.upload(path, data, content_type)
    updated = memory_repository.set_image_path(db, memory=memory, image_path=path)
    return _to_read(updated, image_url=storage.sign_url(path))
