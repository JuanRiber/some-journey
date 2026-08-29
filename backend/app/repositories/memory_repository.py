"""Repository de Memórias: acesso a dados da tabela 'memories'.

Recebe sempre uma Session pronta (de get_db). Camada fina que sabe falar com o
banco — inclusive a parte ESPACIAL (PostGIS) e o ownership/soft delete.

Regras de ouro aplicadas aqui:
- Toda busca filtra por user_id (ownership) E por deleted_at IS NULL (soft delete).
- A localização é guardada como POINT(longitude, latitude) — longitude PRIMEIRO.
"""

import uuid
from datetime import datetime

from geoalchemy2 import Geometry
from sqlalchemy import cast, func, select, tuple_
from sqlalchemy import update as sa_update
from sqlalchemy.orm import Session

from app.domain.location import Location
from app.models.journey import JourneyMemory
from app.models.memory import Memory, MemoryImage, MemoryMusic

# bbox geográfico no formato (min_lng, min_lat, max_lng, max_lat) em WGS84.
Bbox = tuple[float, float, float, float]


def _bbox_filter(bbox: Bbox):
    """Recorta por uma janela retangular (viewport do mapa). Casta a coluna
    GEOGRAPHY para GEOMETRY e usa ST_Intersects com um envelope SRID 4326."""
    min_lng, min_lat, max_lng, max_lat = bbox
    envelope = func.ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326)
    return func.ST_Intersects(cast(Memory.location, Geometry), envelope)


def _point(latitude: float, longitude: float):
    """POINT(longitude latitude) geography. O texto WKT vai como PARÂMETRO
    vinculado (não é concatenado no SQL) e lat/long são floats já validados —
    portanto não há risco de injeção. Atenção à ordem: longitude primeiro."""
    return func.ST_GeogFromText(f"SRID=4326;POINT({longitude} {latitude})")


def create(
    db: Session,
    *,
    user_id: uuid.UUID,
    title: str,
    text: str,
    latitude: float,
    longitude: float,
    occurred_at: datetime,
) -> Memory:
    memory = Memory(
        user_id=user_id,
        title=title,
        text=text,
        location=_point(latitude, longitude),
        occurred_at=occurred_at,
    )
    db.add(memory)
    db.commit()
    db.refresh(memory)
    return memory


def create_pending(
    db: Session,
    *,
    user_id: uuid.UUID,
    title: str,
    text: str,
    latitude: float,
    longitude: float,
    occurred_at: datetime,
) -> Memory:
    """Cria uma memoria na sessao atual sem commit.

    Usado por fluxos compostos que precisam persistir memory + outro vinculo de
    forma atomica, com um unico commit no service.
    """
    memory = Memory(
        user_id=user_id,
        title=title,
        text=text,
        location=_point(latitude, longitude),
        occurred_at=occurred_at,
    )
    db.add(memory)
    db.flush()
    db.refresh(memory)
    return memory


def get_by_id(db: Session, *, user_id: uuid.UUID, memory_id: uuid.UUID) -> Memory | None:
    """Memória do usuário, não apagada. None se não existe ou não é dele — o
    endpoint traduz None em 404 (sem revelar a existência de dado de outro)."""
    return db.scalar(
        select(Memory).where(
            Memory.id == memory_id,
            Memory.user_id == user_id,
            Memory.deleted_at.is_(None),
        )
    )


def list_by_user(
    db: Session,
    *,
    user_id: uuid.UUID,
    limit: int,
    cursor: tuple[datetime, uuid.UUID] | None = None,
) -> list[Memory]:
    """Página de memórias ativas do usuário, da mais recente para a mais antiga.

    Paginação por KEYSET (não offset): ordena por (occurred_at DESC, id DESC) —
    o id é o desempate que torna a ordem TOTAL e estável, sem o qual duas
    memórias com o mesmo occurred_at poderiam trocar de lugar entre requisições
    e o cursor pularia/duplicaria linhas.

    Busca `limit + 1` linhas de propósito: a linha extra é o sinal de que existe
    próxima página (quem chama corta em `limit` e usa a última como cursor). Com
    `cursor = (occurred_at, id)` da página anterior, filtramos as linhas que vêm
    DEPOIS dela na ordem DESC — ou seja, cujo par (occurred_at, id) é MENOR que o
    do cursor. Usamos comparação de tupla (row-value) `tuple_(...) < tuple_(...)`,
    que o Postgres avalia lexicograficamente (occurred_at < c_ts OR (occurred_at
    = c_ts AND id < c_id)) e resolve pelo índice ix_memories_user_occurred.
    """
    stmt = (
        select(Memory)
        .where(Memory.user_id == user_id, Memory.deleted_at.is_(None))
        .order_by(Memory.occurred_at.desc(), Memory.id.desc())
    )
    if cursor is not None:
        cursor_ts, cursor_id = cursor
        stmt = stmt.where(
            tuple_(Memory.occurred_at, Memory.id) < tuple_(cursor_ts, cursor_id)
        )
    return list(db.scalars(stmt.limit(limit + 1)))


def list_loose(
    db: Session, *, user_id: uuid.UUID, bbox: Bbox | None = None
) -> list[Memory]:
    """Memórias "soltas": ativas e SEM vínculo ativo em nenhuma jornada — os pins
    isolados do mapa. bbox opcional recorta pela viewport."""
    has_active_link = (
        select(JourneyMemory.id)
        .where(
            JourneyMemory.memory_id == Memory.id,
            JourneyMemory.deleted_at.is_(None),
        )
        .exists()
    )
    stmt = (
        select(Memory)
        .where(
            Memory.user_id == user_id,
            Memory.deleted_at.is_(None),
            ~has_active_link,
        )
        # id como desempate: ordem determinística mesmo com occurred_at iguais.
        .order_by(Memory.occurred_at.desc(), Memory.id.desc())
    )
    if bbox is not None:
        stmt = stmt.where(_bbox_filter(bbox))
    return list(db.scalars(stmt))


def update(
    db: Session,
    *,
    memory: Memory,
    title: str | None = None,
    text: str | None = None,
    latitude: float | None = None,
    longitude: float | None = None,
    occurred_at: datetime | None = None,
) -> Memory:
    """Atualização parcial de uma memória já carregada (e do dono). Só altera os
    campos passados; latitude/longitude vêm juntas e viram um novo POINT."""
    if title is not None:
        memory.title = title
    if text is not None:
        memory.text = text
    if occurred_at is not None:
        memory.occurred_at = occurred_at
    if latitude is not None and longitude is not None:
        memory.location = _point(latitude, longitude)
    db.commit()
    db.refresh(memory)
    return memory


def set_location(db: Session, *, memory: Memory, location: "Location") -> Memory:
    """Grava o Value Object de lugar nas colunas achatadas de `memories`.

    Este é o ÚNICO lugar do sistema que conhece o mapeamento objeto↔colunas
    (contraparte de `Location.to_columns`). Service e rotas falam só em `Location`.
    """
    for column, value in location.to_columns().items():
        setattr(memory, column, value)
    db.commit()
    db.refresh(memory)
    return memory


def set_image_path(db: Session, *, memory: Memory, image_path: str | None) -> Memory:
    """Grava (após o upload) ou LIMPA (com None, na remoção) o caminho da imagem.
    LEGADO: fotos novas vivem em memory_images; mantido para compatibilidade."""
    memory.image_path = image_path
    db.commit()
    db.refresh(memory)
    return memory


# --- Fotos da memória (memory_images) --------------------------------------


def add_image(
    db: Session, *, memory_id: uuid.UUID, image_path: str, position: int
) -> MemoryImage:
    image = MemoryImage(memory_id=memory_id, image_path=image_path, position=position)
    db.add(image)
    db.commit()
    db.refresh(image)
    return image


def list_images(db: Session, *, memory_id: uuid.UUID) -> list[MemoryImage]:
    """Fotos ativas de uma memória, na ordem (position, depois created_at)."""
    return list(
        db.scalars(
            select(MemoryImage)
            .where(MemoryImage.memory_id == memory_id, MemoryImage.deleted_at.is_(None))
            .order_by(MemoryImage.position, MemoryImage.created_at)
        )
    )


def list_images_for(
    db: Session, *, memory_ids: list[uuid.UUID]
) -> list[MemoryImage]:
    """Fotos ativas de VÁRIAS memórias (para assinar em lote na listagem)."""
    if not memory_ids:
        return []
    return list(
        db.scalars(
            select(MemoryImage)
            .where(
                MemoryImage.memory_id.in_(memory_ids),
                MemoryImage.deleted_at.is_(None),
            )
            .order_by(MemoryImage.position, MemoryImage.created_at)
        )
    )


def get_image(
    db: Session, *, memory_id: uuid.UUID, image_id: uuid.UUID
) -> MemoryImage | None:
    return db.scalar(
        select(MemoryImage).where(
            MemoryImage.id == image_id,
            MemoryImage.memory_id == memory_id,
            MemoryImage.deleted_at.is_(None),
        )
    )


def count_images(db: Session, *, memory_id: uuid.UUID) -> int:
    return (
        db.scalar(
            select(func.count(MemoryImage.id)).where(
                MemoryImage.memory_id == memory_id,
                MemoryImage.deleted_at.is_(None),
            )
        )
        or 0
    )


def next_image_position(db: Session, *, memory_id: uuid.UUID) -> int:
    highest = db.scalar(
        select(func.max(MemoryImage.position)).where(
            MemoryImage.memory_id == memory_id,
            MemoryImage.deleted_at.is_(None),
        )
    )
    return (highest or 0) + 1


def soft_delete_image(db: Session, *, image: MemoryImage) -> None:
    image.deleted_at = func.now()
    db.commit()


def soft_delete(db: Session, *, memory: Memory) -> None:
    """Soft delete: marca deleted_at = now(). A linha permanece no banco.

    Também soft-deleta o vínculo ativo da memória com qualquer jornada, no mesmo
    commit (espelha journey_repository.soft_delete). Sem isso o link órfão segue
    "ocupando o slot" no índice parcial uq_journey_memories_position_active — e
    um reorder posterior dos pontos restantes colide nesse slot, estourando
    IntegrityError (→ 500) numa jornada que nem tem mais essa memória.
    """
    memory.deleted_at = func.now()
    db.execute(
        sa_update(JourneyMemory)
        .where(
            JourneyMemory.memory_id == memory.id,
            JourneyMemory.deleted_at.is_(None),
        )
        .values(deleted_at=func.now())
    )
    db.commit()


# --- Música ----------------------------------------------------------------


def add_music(
    db: Session,
    *,
    memory_id: uuid.UUID,
    data: dict,
    position: int,
) -> MemoryMusic:
    """Anexa uma faixa. A unicidade (mesma faixa duas vezes) é do índice."""
    track = MemoryMusic(memory_id=memory_id, position=position, **data)
    db.add(track)
    db.commit()
    db.refresh(track)
    return track


def list_music(db: Session, *, memory_id: uuid.UUID) -> list[MemoryMusic]:
    """As faixas ativas de uma memória, na ordem em que foram anexadas."""
    return list(
        db.scalars(
            select(MemoryMusic)
            .where(
                MemoryMusic.memory_id == memory_id,
                MemoryMusic.deleted_at.is_(None),
            )
            .order_by(MemoryMusic.position, MemoryMusic.created_at)
        )
    )


def list_music_for(
    db: Session, *, memory_ids: list[uuid.UUID]
) -> dict[uuid.UUID, list[MemoryMusic]]:
    """As faixas de VÁRIAS memórias de uma vez.

    Existe para a listagem não cair em N+1: uma página de 30 memórias faria 30
    consultas se cada uma buscasse as próprias faixas."""
    if not memory_ids:
        return {}
    linhas = db.scalars(
        select(MemoryMusic)
        .where(
            MemoryMusic.memory_id.in_(memory_ids),
            MemoryMusic.deleted_at.is_(None),
        )
        .order_by(MemoryMusic.position, MemoryMusic.created_at)
    )
    saida: dict[uuid.UUID, list[MemoryMusic]] = {}
    for linha in linhas:
        saida.setdefault(linha.memory_id, []).append(linha)
    return saida


def get_music(
    db: Session, *, memory_id: uuid.UUID, music_id: uuid.UUID
) -> MemoryMusic | None:
    return db.scalars(
        select(MemoryMusic).where(
            MemoryMusic.id == music_id,
            MemoryMusic.memory_id == memory_id,
            MemoryMusic.deleted_at.is_(None),
        )
    ).first()


def find_music_track(
    db: Session, *, memory_id: uuid.UUID, provider: str, external_id: str
) -> MemoryMusic | None:
    """A mesma faixa já anexada a esta memória, se houver."""
    return db.scalars(
        select(MemoryMusic).where(
            MemoryMusic.memory_id == memory_id,
            MemoryMusic.provider == provider,
            MemoryMusic.external_id == external_id,
            MemoryMusic.deleted_at.is_(None),
        )
    ).first()


def count_music(db: Session, *, memory_id: uuid.UUID) -> int:
    return (
        db.scalar(
            select(func.count())
            .select_from(MemoryMusic)
            .where(
                MemoryMusic.memory_id == memory_id,
                MemoryMusic.deleted_at.is_(None),
            )
        )
        or 0
    )


def next_music_position(db: Session, *, memory_id: uuid.UUID) -> int:
    maior = db.scalar(
        select(func.max(MemoryMusic.position)).where(
            MemoryMusic.memory_id == memory_id,
            MemoryMusic.deleted_at.is_(None),
        )
    )
    return (maior or 0) + 1


def soft_delete_music(db: Session, *, track: MemoryMusic) -> None:
    track.deleted_at = func.now()
    db.commit()
