"""Serviço de Memórias: orquestra as regras de negócio e converte o model
(geográfico) no schema de saída (lat/long).

Não conhece HTTP: sinaliza ausência com exceções de domínio, que a camada de
rotas traduz em status (404/400/409). Todo acesso passa pelo repository, que já
filtra por user_id (ownership) e deleted_at (soft delete).
"""

import uuid

from geoalchemy2.shape import to_shape
from sqlalchemy.orm import Session

from app.core import storage
from app.models.memory import Memory, MemoryImage
from app.repositories import memory_repository
from app.schemas.memory import (
    MemoryCreate,
    MemoryImageRead,
    MemoryRead,
    MemoryUpdate,
)

# Tipos de imagem aceitos no upload -> extensão usada no path do Storage.
_IMAGE_EXT = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}
# Teto de fotos por memória.
_MAX_IMAGES = 5


class MemoryNotFoundError(Exception):
    """Memória inexistente ou de outro usuário — a rota traduz em 404."""


class MemoryImageNotFoundError(Exception):
    """Foto inexistente ou de memória de outro usuário — a rota traduz em 404."""


class InvalidImageError(Exception):
    """Tipo de imagem não suportado — a rota traduz em 400."""


class TooManyImagesError(Exception):
    """Excedeu o teto de fotos por memória — a rota traduz em 409."""


def _to_read(
    memory: Memory, images: list[MemoryImage], signed: dict[str, str]
) -> MemoryRead:
    """Converte o model (location = POINT(long, lat)) no DTO de saída (lat/long).

    `images` são as fotos ativas ordenadas; `signed` mapeia image_path -> URL
    assinada temporária. Fotos sem URL (Storage desligado/erro) ficam de fora.
    image_url = a primeira (capa), por compatibilidade com o cliente atual.
    """
    point = to_shape(memory.location)
    image_reads = [
        MemoryImageRead(id=img.id, url=signed[img.image_path])
        for img in images
        if img.image_path in signed
    ]
    return MemoryRead(
        id=memory.id,
        title=memory.title,
        text=memory.text,
        latitude=point.y,
        longitude=point.x,
        occurred_at=memory.occurred_at,
        created_at=memory.created_at,
        images=image_reads,
        image_url=image_reads[0].url if image_reads else None,
    )


def _read_with_images(db: Session, memory: Memory) -> MemoryRead:
    """Lê as fotos da memória, assina-as e monta o DTO."""
    images = memory_repository.list_images(db, memory_id=memory.id)
    signed = storage.sign_urls([img.image_path for img in images])
    return _to_read(memory, images, signed)


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
    return _to_read(memory, [], {})  # nasce sem fotos


def reads_for(db: Session, memories: list[Memory]) -> list[MemoryRead]:
    """Monta os DTOs de VÁRIAS memórias já carregadas, assinando as fotos em UMA
    chamada ao Storage (evita N round-trips). Preserva a ordem recebida — quem
    consulta decide a ordenação (recentes primeiro, cronológica na jornada, ...)."""
    images = memory_repository.list_images_for(
        db, memory_ids=[m.id for m in memories]
    )
    signed = storage.sign_urls([img.image_path for img in images])
    by_memory: dict[uuid.UUID, list[MemoryImage]] = {}
    for img in images:
        by_memory.setdefault(img.memory_id, []).append(img)
    return [_to_read(m, by_memory.get(m.id, []), signed) for m in memories]


def list_for_user(db: Session, *, user_id: uuid.UUID) -> list[MemoryRead]:
    return reads_for(db, memory_repository.list_by_user(db, user_id=user_id))


def get(db: Session, *, user_id: uuid.UUID, memory_id: uuid.UUID) -> MemoryRead:
    memory = memory_repository.get_by_id(db, user_id=user_id, memory_id=memory_id)
    if memory is None:
        raise MemoryNotFoundError()
    return _read_with_images(db, memory)


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
    return _read_with_images(db, updated)


def delete(db: Session, *, user_id: uuid.UUID, memory_id: uuid.UUID) -> None:
    memory = memory_repository.get_by_id(db, user_id=user_id, memory_id=memory_id)
    if memory is None:
        raise MemoryNotFoundError()
    memory_repository.soft_delete(db, memory=memory)


def add_image(
    db: Session,
    *,
    user_id: uuid.UUID,
    memory_id: uuid.UUID,
    data: bytes,
    content_type: str,
) -> MemoryRead:
    """Adiciona uma foto à memória (do dono), respeitando o teto _MAX_IMAGES.

    Caminho isolado: `${user_id}/${memory_id}/${rand}.${ext}`. Pode levantar
    InvalidImageError (tipo), MemoryNotFoundError (404), TooManyImagesError (409),
    StorageNotConfigured/StorageError (propagam para a rota)."""
    ext = _IMAGE_EXT.get(content_type)
    if ext is None:
        raise InvalidImageError()
    memory = memory_repository.get_by_id(db, user_id=user_id, memory_id=memory_id)
    if memory is None:
        raise MemoryNotFoundError()
    if memory_repository.count_images(db, memory_id=memory.id) >= _MAX_IMAGES:
        raise TooManyImagesError()
    position = memory_repository.next_image_position(db, memory_id=memory.id)
    path = f"{user_id}/{memory_id}/{uuid.uuid4().hex}.{ext}"
    storage.upload(path, data, content_type)
    memory_repository.add_image(
        db, memory_id=memory.id, image_path=path, position=position
    )
    return _read_with_images(db, memory)


def remove_image(
    db: Session,
    *,
    user_id: uuid.UUID,
    memory_id: uuid.UUID,
    image_id: uuid.UUID,
) -> MemoryRead:
    """Remove UMA foto da memória (do dono): soft-delete do registro + apaga o
    arquivo (best-effort). 404 se a memória ou a foto não são do usuário."""
    memory = memory_repository.get_by_id(db, user_id=user_id, memory_id=memory_id)
    if memory is None:
        raise MemoryNotFoundError()
    image = memory_repository.get_image(db, memory_id=memory.id, image_id=image_id)
    if image is None:
        raise MemoryImageNotFoundError()
    path = image.image_path
    memory_repository.soft_delete_image(db, image=image)
    storage.delete(path)
    return _read_with_images(db, memory)
