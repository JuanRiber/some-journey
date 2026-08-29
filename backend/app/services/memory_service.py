"""Serviço de Memórias: orquestra as regras de negócio e converte o model
(geográfico) no schema de saída (lat/long).

Não conhece HTTP: sinaliza ausência com exceções de domínio, que a camada de
rotas traduz em status (404/400/409). Todo acesso passa pelo repository, que já
filtra por user_id (ownership) e deleted_at (soft delete).
"""

import logging
import uuid
from datetime import datetime

from geoalchemy2.shape import to_shape
from sqlalchemy.orm import Session

from app.core import images, storage
from app.core.pagination import encode_cursor
from app.db.session import SessionLocal
from app.models.memory import Memory, MemoryImage, MemoryMusic
from app.repositories import memory_repository
from app.services import geocoding
from app.schemas.memory import (
    MemoryCreate,
    MemoryImageRead,
    MemoryMusicIn,
    MemoryMusicRead,
    MemoryRead,
    MemoryUpdate,
)

# Tipos de imagem aceitos no upload -> extensão usada no path do Storage.
_IMAGE_EXT = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}
# Teto de fotos por memória.
_MAX_IMAGES = 5

logger = logging.getLogger("app.memory")


class MemoryNotFoundError(Exception):
    """Memória inexistente ou de outro usuário — a rota traduz em 404."""


class MemoryImageNotFoundError(Exception):
    """Foto inexistente ou de memória de outro usuário — a rota traduz em 404."""


class InvalidImageError(Exception):
    """Tipo de imagem não suportado — a rota traduz em 400."""


class TooManyImagesError(Exception):
    """Excedeu o teto de fotos por memória — a rota traduz em 409."""


class MemoryMusicNotFoundError(Exception):
    """Faixa inexistente ou de memória de outro usuário — a rota traduz em 404."""


class DuplicateMusicError(Exception):
    """A faixa já está nesta memória — a rota traduz em 409."""


class TooManyTracksError(Exception):
    """Excedeu o teto de faixas por memória — a rota traduz em 409."""


def _to_read(
    memory: Memory,
    images: list[MemoryImage],
    signed: dict[str, str],
    music: list[MemoryMusic] | None = None,
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
        place_label=memory.place_label,
        city=memory.city,
        state_province=memory.state_province,
        country=memory.country,
        country_code=memory.country_code,
        continent=memory.continent,
        music=[
            MemoryMusicRead(
                id=t.id,
                provider=t.provider,
                external_id=t.external_id,
                title=t.title,
                artist=t.artist,
                album=t.album,
                artwork_url=t.artwork_url,
                preview_url=t.preview_url,
                external_url=t.external_url,
                duration_ms=t.duration_ms,
            )
            for t in (music or [])
        ],
    )


def _read_with_images(db: Session, memory: Memory) -> MemoryRead:
    """Lê fotos e faixas da memória, assina as fotos e monta o DTO."""
    images = memory_repository.list_images(db, memory_id=memory.id)
    signed = storage.sign_urls([img.image_path for img in images])
    music = memory_repository.list_music(db, memory_id=memory.id)
    return _to_read(memory, images, signed, music)


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


def geocode_memory(*, user_id: uuid.UUID, memory_id: uuid.UUID) -> None:
    """Resolve e PERSISTE o lugar de uma memória — roda em SEGUNDO PLANO.

    Por que fora do request: o provedor leva centenas de milissegundos e é de
    terceiros. Fazer o usuário esperar por isso para registrar uma memória seria
    cobrar dele a latência de um serviço externo — a memória grava na hora e o
    lugar aparece logo depois.

    ABRE A PRÓPRIA SESSÃO de propósito: a sessão do request já foi FECHADA pelo
    `get_db` quando a tarefa de fundo roda (ela executa depois da resposta).
    Reaproveitá-la daria erro de sessão fechada — e o lugar nunca seria gravado.

    Nunca levanta: qualquer falha deixa `geocoded_at` nulo e a linha na fila de
    backfill (índice `ix_memories_pending_geocode`).
    """
    try:
        with SessionLocal() as db:
            memory = memory_repository.get_by_id(
                db, user_id=user_id, memory_id=memory_id
            )
            if memory is None:
                return  # apagada entre o create e o job — nada a fazer
            point = to_shape(memory.location)
            located = geocoding.resolve_location(
                geocoding.get_provider(), latitude=point.y, longitude=point.x
            )
            if not located.is_geocoded:
                return  # provedor indisponível: fica para o backfill
            memory_repository.set_location(db, memory=memory, location=located)
    except Exception:  # noqa: BLE001 - job de fundo jamais derruba o processo
        logger.exception("Falha ao geocodificar a memória em segundo plano.")


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
    # As faixas de todas as memórias da página numa consulta só — o mesmo
    # cuidado que as fotos já tomavam contra o N+1.
    music_by_memory = memory_repository.list_music_for(
        db, memory_ids=[m.id for m in memories]
    )
    return [
        _to_read(m, by_memory.get(m.id, []), signed, music_by_memory.get(m.id, []))
        for m in memories
    ]


def list_for_user(
    db: Session,
    *,
    user_id: uuid.UUID,
    limit: int,
    cursor: tuple[datetime, uuid.UUID] | None = None,
) -> tuple[list[MemoryRead], str | None]:
    """Uma PÁGINA das memórias do usuário + o cursor da próxima (ou None).

    O repository devolve `limit + 1` linhas: se vieram mais que `limit`, existe
    próxima página. Cortamos em `limit` e o cursor é o par (occurred_at, id) da
    ÚLTIMA linha da página — o mesmo par que o keyset usa para continuar. Retorna
    a lista (corpo, array puro) e o cursor separados; a rota decide o header.
    """
    rows = memory_repository.list_by_user(
        db, user_id=user_id, limit=limit, cursor=cursor
    )
    has_next = len(rows) > limit
    page = rows[:limit]
    next_cursor = (
        encode_cursor(page[-1].occurred_at, page[-1].id) if has_next else None
    )
    return reads_for(db, page), next_cursor


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
) -> MemoryRead:
    """Adiciona uma foto à memória (do dono), respeitando o teto _MAX_IMAGES.

    Tipo por MAGIC BYTES, não pelo Content-Type do multipart (o cliente mente):
    `images.sniff_image_type` fareja os bytes e é a ÚNICA fonte da verdade tanto
    para a extensão do path quanto para o Content-Type gravado no Storage. None
    (não é imagem suportada) -> InvalidImageError.

    Caminho isolado: `${user_id}/${memory_id}/${rand}.${ext}`. Pode levantar
    InvalidImageError (tipo), MemoryNotFoundError (404), TooManyImagesError (409),
    StorageNotConfigured/StorageError (propagam para a rota).

    Escrita em DOIS sistemas (Storage + banco) sem transação distribuída: subimos
    o arquivo primeiro e, se o INSERT falhar por QUALQUER motivo, fazemos o
    delete COMPENSATÓRIO do objeto já enviado (best-effort/silencioso) antes de
    repropagar — sem isso, uma falha no banco deixaria um órfão pagando storage e
    fora de qualquer registro."""
    mime = images.sniff_image_type(data)
    if mime is None:
        raise InvalidImageError()
    ext = _IMAGE_EXT[mime]
    memory = memory_repository.get_by_id(db, user_id=user_id, memory_id=memory_id)
    if memory is None:
        raise MemoryNotFoundError()
    if memory_repository.count_images(db, memory_id=memory.id) >= _MAX_IMAGES:
        raise TooManyImagesError()
    position = memory_repository.next_image_position(db, memory_id=memory.id)
    path = f"{user_id}/{memory_id}/{uuid.uuid4().hex}.{ext}"
    storage.upload(path, data, mime)
    try:
        memory_repository.add_image(
            db, memory_id=memory.id, image_path=path, position=position
        )
    except Exception:
        # Compensa o upload já concluído: remove o órfão e repropaga o erro.
        storage.delete(path)
        raise
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


# --- Música ----------------------------------------------------------------

# Teto por memória. Uma lembrança tem uma trilha, não uma playlist: o limite
# existe para o campo continuar sendo sobre a canção daquele momento.
_MAX_TRACKS = 5


def add_music(
    db: Session,
    *,
    user_id: uuid.UUID,
    memory_id: uuid.UUID,
    data: MemoryMusicIn,
) -> MemoryRead:
    """Anexa uma faixa à memória do usuário.

    O backend NÃO consulta catálogo: recebe o snapshot que o app obteve do
    provedor. Buscar exige rede e é do provedor; guardar é nosso — separar os
    dois deixa o app trocar de catálogo sem que a API precise saber."""
    memory = memory_repository.get_by_id(db, user_id=user_id, memory_id=memory_id)
    if memory is None:
        raise MemoryNotFoundError

    ja = memory_repository.find_music_track(
        db,
        memory_id=memory.id,
        provider=data.provider,
        external_id=data.external_id,
    )
    if ja is not None:
        raise DuplicateMusicError

    if memory_repository.count_music(db, memory_id=memory.id) >= _MAX_TRACKS:
        raise TooManyTracksError

    memory_repository.add_music(
        db,
        memory_id=memory.id,
        data=data.model_dump(),
        position=memory_repository.next_music_position(db, memory_id=memory.id),
    )
    return _read_with_images(db, memory)


def remove_music(
    db: Session,
    *,
    user_id: uuid.UUID,
    memory_id: uuid.UUID,
    music_id: uuid.UUID,
) -> MemoryRead:
    """Remove uma faixa (soft delete). A memória em si não é tocada."""
    memory = memory_repository.get_by_id(db, user_id=user_id, memory_id=memory_id)
    if memory is None:
        raise MemoryNotFoundError

    track = memory_repository.get_music(db, memory_id=memory.id, music_id=music_id)
    if track is None:
        raise MemoryMusicNotFoundError

    memory_repository.soft_delete_music(db, track=track)
    return _read_with_images(db, memory)
