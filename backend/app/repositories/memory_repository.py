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
from sqlalchemy import cast, func, select
from sqlalchemy.orm import Session

from app.models.journey import JourneyMemory
from app.models.memory import Memory

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


def list_by_user(db: Session, *, user_id: uuid.UUID) -> list[Memory]:
    """Memórias ativas do usuário, da mais recente para a mais antiga (occurred_at)."""
    return list(
        db.scalars(
            select(Memory)
            .where(Memory.user_id == user_id, Memory.deleted_at.is_(None))
            .order_by(Memory.occurred_at.desc())
        )
    )


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
        .order_by(Memory.occurred_at.desc())
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


def set_image_path(db: Session, *, memory: Memory, image_path: str) -> Memory:
    """Grava o caminho da imagem no Storage (após o upload pelo service)."""
    memory.image_path = image_path
    db.commit()
    db.refresh(memory)
    return memory


def soft_delete(db: Session, *, memory: Memory) -> None:
    """Soft delete: marca deleted_at = now(). A linha permanece no banco."""
    memory.deleted_at = func.now()
    db.commit()
