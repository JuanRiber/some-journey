"""Agregações do Perfil — TUDO em SQL, nada materializado em Python.

Regra que justifica este módulo: o Perfil mostra "142 memórias · 37 cidades ·
2.430 km". Contar isso no cliente significaria baixar todas as memórias — o
oposto da paginação por keyset que a listagem usa. Aqui cada número sai de um
`COUNT`/`SUM` que o Postgres resolve com os índices parciais da 0009.

Cada função é uma consulta independente e barata (índice + agregação), em vez de
um join gigante: são poucas, executam em paralelo do ponto de vista do plano e
ficam legíveis/testáveis uma a uma.
"""

import uuid
from datetime import datetime

from sqlalchemy import Integer, func, select
from sqlalchemy import text as sa_text
from sqlalchemy.orm import Session

from app.models.journey import Journey, JourneyMemory
from app.models.memory import Memory, MemoryImage, MemoryMusic


def _active_memories(user_id: uuid.UUID):
    """Filtro base: memórias vivas do dono. Repetido em toda consulta porque
    ownership + soft delete não são opcionais."""
    return (Memory.user_id == user_id, Memory.deleted_at.is_(None))


def counts(db: Session, *, user_id: uuid.UUID) -> dict[str, int]:
    """Contagens principais numa varredura só das memórias.

    `COUNT(DISTINCT ...)` ignora NULL por definição — então memórias ainda não
    geocodificadas simplesmente não contam cidade/país, sem precisar de filtro."""
    row = db.execute(
        select(
            func.count(Memory.id),
            func.count(func.distinct(Memory.city)),
            func.count(func.distinct(Memory.country_code)),
            func.count(func.distinct(Memory.continent)),
            # Fila de backfill: quantas ainda não têm lugar resolvido.
            func.coalesce(
                func.sum(
                    func.cast(Memory.geocoded_at.is_(None), Integer)
                ),
                0,
            ),
        ).where(*_active_memories(user_id))
    ).one()
    return {
        "memories": int(row[0] or 0),
        "cities": int(row[1] or 0),
        "countries": int(row[2] or 0),
        "continents": int(row[3] or 0),
        "pending_geocode": int(row[4] or 0),
    }


def journey_counts(db: Session, *, user_id: uuid.UUID) -> dict[str, int]:
    """Total de jornadas e quantas foram CONCLUÍDAS (o capítulo fechado)."""
    row = db.execute(
        select(
            func.count(Journey.id),
            func.coalesce(
                func.sum(func.cast(Journey.status == "finished", Integer)), 0
            ),
        ).where(Journey.user_id == user_id, Journey.deleted_at.is_(None))
    ).one()
    return {"journeys": int(row[0] or 0), "journeys_finished": int(row[1] or 0)}


def photo_count(db: Session, *, user_id: uuid.UUID) -> int:
    """Fotos vivas de memórias vivas (join necessário: a foto não guarda o dono)."""
    return int(
        db.scalar(
            select(func.count(MemoryImage.id))
            .join(Memory, Memory.id == MemoryImage.memory_id)
            .where(MemoryImage.deleted_at.is_(None), *_active_memories(user_id))
        )
        or 0
    )


def music_count(db: Session, *, user_id: uuid.UUID) -> int:
    """Faixas vivas de memórias vivas — o "56 músicas" do cartão do viajante.

    Mesmo join das fotos, pela mesma razão: a faixa pertence à memória, e o
    dono está na memória."""
    return int(
        db.scalar(
            select(func.count(MemoryMusic.id))
            .join(Memory, Memory.id == MemoryMusic.memory_id)
            .where(MemoryMusic.deleted_at.is_(None), *_active_memories(user_id))
        )
        or 0
    )


def tracked_meters(db: Session, *, user_id: uuid.UUID) -> float:
    """Distância REAL percorrida (metros), calculada no banco com PostGIS.

    `ST_MakeLine(... ORDER BY recorded_at)` reconstrói o traço de cada trecho e
    `ST_Length(::geography)` mede sobre o elipsoide. Fazer isso em Python exigiria
    trazer todos os pontos GPS do usuário para a aplicação — inviável.

    Trechos com menos de 2 pontos viram linha degenerada; o filtro
    `count(*) > 1` os descarta antes de medir.
    """
    # SQL cru: os casts geometry/geography e o ORDER BY dentro do agregado são
    # mais claros (e mais confiáveis) escritos à mão do que montados no ORM.
    # user_id vai como PARÂMETRO vinculado — nada é concatenado.
    sql = sa_text(
        """
        SELECT COALESCE(SUM(meters), 0.0) FROM (
            SELECT ST_Length(
                       ST_MakeLine(location::geometry ORDER BY recorded_at, id)::geography
                   ) AS meters
            FROM journey_track_points
            WHERE user_id = :user_id
            GROUP BY track_id
            HAVING COUNT(*) > 1
        ) AS per_track
        """
    )
    return float(db.scalar(sql, {"user_id": user_id}) or 0.0)


def visited_continents(db: Session, *, user_id: uuid.UUID) -> list[str]:
    """Continentes com carimbo no passaporte (ordem alfabética; a UI reordena)."""
    rows = db.execute(
        select(Memory.continent)
        .where(*_active_memories(user_id), Memory.continent.is_not(None))
        .distinct()
        .order_by(Memory.continent)
    ).all()
    return [r[0] for r in rows]


def last_adventure(db: Session, *, user_id: uuid.UUID) -> dict[str, object] | None:
    """A memória geocodificada mais RECENTE (por quando aconteceu) — alimenta a
    linha "última aventura: Fortaleza"."""
    row = db.execute(
        select(Memory.city, Memory.country, Memory.country_code, Memory.occurred_at)
        .where(*_active_memories(user_id), Memory.city.is_not(None))
        .order_by(Memory.occurred_at.desc(), Memory.id.desc())
        .limit(1)
    ).first()
    if row is None:
        return None
    return {
        "city": row[0],
        "country": row[1],
        "country_code": row[2],
        "occurred_at": row[3],
    }


def current_journey(db: Session, *, user_id: uuid.UUID) -> dict[str, object] | None:
    """A jornada ATIVA (só existe uma por usuário) + quantos pontos ela tem —
    base do cartão "Continue sua jornada"."""
    row = db.execute(
        select(
            Journey.id,
            Journey.title,
            Journey.started_at,
            func.count(JourneyMemory.id),
        )
        .outerjoin(
            JourneyMemory,
            (JourneyMemory.journey_id == Journey.id)
            & (JourneyMemory.deleted_at.is_(None)),
        )
        .where(
            Journey.user_id == user_id,
            Journey.deleted_at.is_(None),
            Journey.status == "active",
        )
        .group_by(Journey.id)
        .limit(1)
    ).first()
    if row is None:
        return None
    return {
        "id": row[0],
        "title": row[1],
        "started_at": row[2],
        "points_count": int(row[3] or 0),
    }


def member_since(db: Session, *, user_id: uuid.UUID) -> datetime | None:
    """Primeira memória registrada — "explorador desde 2026" conta a história
    melhor que a data de cadastro."""
    return db.scalar(
        select(func.min(Memory.created_at)).where(*_active_memories(user_id))
    )


def active_days(db: Session, *, user_id: uuid.UUID) -> int:
    """Dias DISTINTOS em que a pessoa registrou algo.

    É "dias usando o app" de forma honesta e derivável do que já temos — sem
    inventar um log de atividade. Conta pela data de criação (uso real), não por
    occurred_at (que é a data do acontecimento, podendo ser antiga)."""
    return int(
        db.scalar(
            select(func.count(func.distinct(func.date(Memory.created_at)))).where(
                *_active_memories(user_id)
            )
        )
        or 0
    )
