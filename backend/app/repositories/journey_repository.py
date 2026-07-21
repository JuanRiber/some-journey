import uuid
from datetime import datetime

from sqlalchemy import and_, func, or_, select, update
from sqlalchemy.orm import Session

from app.models.journey import Journey, JourneyMemory
from app.models.memory import Memory, MemoryImage
from app.models.track import JourneyTrack


def create_journey(
    db: Session,
    *,
    user_id: uuid.UUID,
    title: str,
    description: str | None,
    started_at: datetime | None,
    ended_at: datetime | None = None,
    mood: str | None = None,
    is_private: bool = True,
) -> Journey:
    journey = Journey(
        user_id=user_id,
        title=title,
        description=description,
        started_at=started_at,
        ended_at=ended_at,
        mood=mood,
        is_private=is_private,
    )
    db.add(journey)
    db.commit()
    db.refresh(journey)
    return journey


def update_journey(
    db: Session,
    *,
    journey: Journey,
    title: str | None = None,
    description: str | None = None,
    mood: str | None = None,
    is_private: bool | None = None,
    started_at: datetime | None = None,
    ended_at: datetime | None = None,
) -> Journey:
    """Atualização parcial dos metadados de uma jornada já carregada (e do dono).
    Só altera os campos passados; o status continua a cargo das transições."""
    if title is not None:
        journey.title = title
    if description is not None:
        journey.description = description
    if mood is not None:
        journey.mood = mood
    if is_private is not None:
        journey.is_private = is_private
    if started_at is not None:
        journey.started_at = started_at
    if ended_at is not None:
        journey.ended_at = ended_at
    db.commit()
    db.refresh(journey)
    return journey


def list_journeys(
    db: Session,
    *,
    user_id: uuid.UUID,
    limit: int | None = None,
    cursor: tuple[datetime, uuid.UUID] | None = None,
) -> list[tuple[Journey, int]]:
    """Jornadas do usuário (com a contagem de pontos ativos), da mais recente
    para a mais antiga.

    Ordenação CANÔNICA e estável: (created_at DESC, id DESC). O id é o desempate
    único — sem ele, duas jornadas com o mesmo created_at poderiam trocar de
    lugar entre requisições e a paginação por keyset pularia/duplicaria linhas.

    Paginação por keyset (opcional, retrocompatível):
    - `limit=None` (default) devolve TODAS as linhas — preserva o contrato antigo
      para chamadores que não paginam (ex.: montagem do mapa).
    - `limit=int` busca limit+1 linhas: o serviço detecta "há próxima página" pela
      linha extra e monta o cursor. `cursor` é o par (created_at, id) do fim da
      página anterior; como a ordem é DESC, a próxima página é tudo que vem DEPOIS
      dele, i.e. (created_at, id) estritamente MENOR que o cursor.
    """
    stmt = (
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
        .order_by(Journey.created_at.desc(), Journey.id.desc())
    )
    if cursor is not None:
        cursor_created, cursor_id = cursor
        stmt = stmt.where(
            or_(
                Journey.created_at < cursor_created,
                and_(
                    Journey.created_at == cursor_created,
                    Journey.id < cursor_id,
                ),
            )
        )
    if limit is not None:
        stmt = stmt.limit(limit + 1)
    rows = db.execute(stmt)
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


def list_points_for_journeys(
    db: Session, *, journey_ids: list[uuid.UUID], user_id: uuid.UUID
) -> dict[uuid.UUID, list[tuple[JourneyMemory, Memory]]]:
    """Pontos de VÁRIAS jornadas numa query só (evita o N+1 do /map). Devolve
    um dict journey_id -> lista ordenada por posição; jornadas sem pontos ficam
    de fora do dict."""
    if not journey_ids:
        return {}
    rows = db.execute(
        select(JourneyMemory, Memory)
        .join(Memory, Memory.id == JourneyMemory.memory_id)
        .where(
            JourneyMemory.journey_id.in_(journey_ids),
            JourneyMemory.deleted_at.is_(None),
            Memory.user_id == user_id,
            Memory.deleted_at.is_(None),
        )
        .order_by(JourneyMemory.journey_id, JourneyMemory.position.asc())
    )
    grouped: dict[uuid.UUID, list[tuple[JourneyMemory, Memory]]] = {}
    for link, memory in rows:
        grouped.setdefault(link.journey_id, []).append((link, memory))
    return grouped


def set_cover_path(db: Session, *, journey: Journey, path: str | None) -> Journey:
    """Grava (após upload) ou LIMPA (None) o caminho da capa no Storage."""
    journey.cover_image_path = path
    db.commit()
    db.refresh(journey)
    return journey


def first_memory_image_paths(
    db: Session, *, journey_ids: list[uuid.UUID]
) -> dict[uuid.UUID, str]:
    """Capa de FALLBACK: a primeira foto (da primeira memória do rastro) de cada
    jornada. Uma query só (DISTINCT ON) para a listagem não fazer N idas ao banco.
    Jornadas sem nenhuma foto simplesmente não aparecem no dict."""
    if not journey_ids:
        return {}
    rows = db.execute(
        select(JourneyMemory.journey_id, MemoryImage.image_path)
        .join(Memory, Memory.id == JourneyMemory.memory_id)
        .join(MemoryImage, MemoryImage.memory_id == Memory.id)
        .where(
            JourneyMemory.journey_id.in_(journey_ids),
            JourneyMemory.deleted_at.is_(None),
            Memory.deleted_at.is_(None),
            MemoryImage.deleted_at.is_(None),
        )
        .distinct(JourneyMemory.journey_id)
        .order_by(
            JourneyMemory.journey_id,
            JourneyMemory.position.asc(),
            MemoryImage.position.asc(),
        )
    ).all()
    return {journey_id: image_path for journey_id, image_path in rows}


def list_memories_chronological(
    db: Session, *, journey_id: uuid.UUID, user_id: uuid.UUID
) -> list[Memory]:
    """Memórias ativas da jornada (do dono), ordenadas por data do acontecimento
    (occurred_at asc) — a leitura cronológica da timeline da jornada, diferente da
    ordem do rastro (position)."""
    return list(
        db.scalars(
            select(Memory)
            .join(JourneyMemory, JourneyMemory.memory_id == Memory.id)
            .where(
                JourneyMemory.journey_id == journey_id,
                JourneyMemory.deleted_at.is_(None),
                Memory.user_id == user_id,
                Memory.deleted_at.is_(None),
            )
            # Desempate estável por id ASC: memórias com o MESMO occurred_at
            # mantêm sempre a mesma ordem entre requisições (sem isso a timeline
            # poderia embaralhar itens de mesma data a cada leitura).
            .order_by(Memory.occurred_at.asc(), Memory.id.asc())
        )
    )


def reorder(
    db: Session, *, items: list[JourneyMemory], positions: dict[uuid.UUID, int]
) -> None:
    for item in items:
        item.position = -positions[item.memory_id]
    db.flush()
    for item in items:
        item.position = positions[item.memory_id]
    db.commit()


def close_open_tracks(db: Session, *, journey_id: uuid.UUID) -> None:
    """Fecha (ended_at = now()) qualquer trecho de percurso AINDA ABERTO da
    jornada. Chamado ao finalizar a jornada: uma jornada 'finished' não pode
    ficar com gravação de GPS em aberto.

    NÃO faz commit — o UPDATE participa da mesma transação de quem chama (o
    finish() comita junto ao mudar o status), mantendo a operação atômica. Só
    lê/escreve JourneyTrack (não toca no ciclo de vida do percurso além de
    encerrar o trecho aberto)."""
    db.execute(
        update(JourneyTrack)
        .where(
            JourneyTrack.journey_id == journey_id,
            JourneyTrack.ended_at.is_(None),
            JourneyTrack.deleted_at.is_(None),
        )
        .values(ended_at=func.now())
    )


def soft_delete(db: Session, *, journey: Journey) -> None:
    # Soft-delete a jornada E seus vínculos ativos no mesmo commit (atômico).
    # Sem isso os links ficariam vivos: a memória continuaria "ocupando o slot"
    # (índice único parcial uq_journey_memories_memory_active) — não entraria em
    # outra jornada (409) e sumiria dos pontos soltos do mapa, embora a jornada
    # já não exista. Excluir a jornada não apaga as memórias, só os vínculos.
    journey.deleted_at = func.now()
    db.execute(
        update(JourneyMemory)
        .where(
            JourneyMemory.journey_id == journey.id,
            JourneyMemory.deleted_at.is_(None),
        )
        .values(deleted_at=func.now())
    )
    # Mesma cascata para os percursos (tracks) ativos: excluir a jornada
    # soft-deleta os trechos de GPS no mesmo commit. Sem isso um trecho ABERTO
    # continuaria ocupando o slot do índice único parcial
    # uq_journey_tracks_one_open_per_journey e sobraria dado de localização
    # (sensível) vivo de uma jornada que já não existe. Espelha o bloco de
    # JourneyMemory acima.
    db.execute(
        update(JourneyTrack)
        .where(
            JourneyTrack.journey_id == journey.id,
            JourneyTrack.deleted_at.is_(None),
        )
        .values(deleted_at=func.now())
    )
    db.commit()
