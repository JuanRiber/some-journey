"""Repository do percurso real: journey_tracks e journey_track_points.

Camada fina de acesso a dados. Recebe a Session pronta. Toda leitura filtra por
ownership (user_id) e trechos ativos (deleted_at IS NULL). A localização é
gravada como POINT(longitude, latitude) — longitude primeiro.
"""

import uuid
from datetime import datetime

from geoalchemy2 import Geography, Geometry
from sqlalchemy import cast, func, insert, select
from sqlalchemy.dialects.postgresql import aggregate_order_by
from sqlalchemy.orm import Session

from app.models.track import JourneyTrack, JourneyTrackPoint
from app.schemas.track import TrackPointIn


def _point(latitude: float, longitude: float):
    """POINT(longitude latitude) geography. lat/long são floats já validados e o
    WKT vai como parâmetro vinculado — sem risco de injeção. Longitude primeiro."""
    return func.ST_GeogFromText(f"SRID=4326;POINT({longitude} {latitude})")


def create_track(
    db: Session,
    *,
    user_id: uuid.UUID,
    journey_id: uuid.UUID,
    source: str,
    started_at: datetime | None,
) -> JourneyTrack:
    track = JourneyTrack(
        user_id=user_id,
        journey_id=journey_id,
        source=source,
        **({"started_at": started_at} if started_at is not None else {}),
    )
    db.add(track)
    db.commit()
    db.refresh(track)
    return track


def get_open_track(db: Session, *, journey_id: uuid.UUID) -> JourneyTrack | None:
    """O trecho ainda em gravação da jornada (ended_at NULL), se houver."""
    return db.scalar(
        select(JourneyTrack).where(
            JourneyTrack.journey_id == journey_id,
            JourneyTrack.ended_at.is_(None),
            JourneyTrack.deleted_at.is_(None),
        )
    )


def get_track(
    db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID, track_id: uuid.UUID
) -> JourneyTrack | None:
    return db.scalar(
        select(JourneyTrack).where(
            JourneyTrack.id == track_id,
            JourneyTrack.journey_id == journey_id,
            JourneyTrack.user_id == user_id,
            JourneyTrack.deleted_at.is_(None),
        )
    )


def list_tracks(
    db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID
) -> list[JourneyTrack]:
    return list(
        db.scalars(
            select(JourneyTrack)
            .where(
                JourneyTrack.journey_id == journey_id,
                JourneyTrack.user_id == user_id,
                JourneyTrack.deleted_at.is_(None),
            )
            .order_by(JourneyTrack.started_at.asc())
        )
    )


def finish_track(db: Session, *, track: JourneyTrack, ended_at: datetime) -> JourneyTrack:
    track.ended_at = ended_at
    db.commit()
    db.refresh(track)
    return track


def soft_delete_track(db: Session, *, track: JourneyTrack) -> None:
    """Soft-delete do trecho. Os pontos ficam no banco mas somem das consultas
    (sempre lidas via trecho ativo). Não toca nas memórias da jornada."""
    track.deleted_at = func.now()
    db.commit()


def add_points(
    db: Session,
    *,
    track_id: uuid.UUID,
    journey_id: uuid.UUID,
    user_id: uuid.UUID,
    points: list[TrackPointIn],
) -> int:
    """Insere um lote de pontos GPS numa ÚNICA ida ao banco. Retorna quantos.

    Antes cada ponto era um objeto ORM em `add_all`, o que fazia o SQLAlchemy
    emitir um INSERT por linha (N round-trips) — caro para lotes de até 1000
    pontos vindos do GPS. Aqui montamos UM `INSERT ... VALUES (…),(…),…` via Core
    (`insert().values([...])`): um único statement, uma viagem. A coluna
    `location` continua sendo `ST_GeogFromText(...)` POR LINHA (a função entra
    inline em cada tupla do VALUES; lat/long vão como parâmetros vinculados no
    WKT, sem risco de injeção). `created_at` fica a cargo do server_default."""
    db.execute(
        insert(JourneyTrackPoint).values(
            [
                {
                    "track_id": track_id,
                    "journey_id": journey_id,
                    "user_id": user_id,
                    "location": _point(p.latitude, p.longitude),
                    "accuracy": p.accuracy,
                    "altitude": p.altitude,
                    "speed": p.speed,
                    "heading": p.heading,
                    "recorded_at": p.recorded_at,
                }
                for p in points
            ]
        )
    )
    db.commit()
    return len(points)


def count_points(db: Session, *, track_id: uuid.UUID) -> int:
    return (
        db.scalar(
            select(func.count(JourneyTrackPoint.id)).where(
                JourneyTrackPoint.track_id == track_id
            )
        )
        or 0
    )


def point_coords(db: Session, *, track_id: uuid.UUID) -> list[tuple[float, float]]:
    """Coordenadas (longitude, latitude) do trecho, na ordem de captura. Extrai
    lng/lat no banco (ST_X/ST_Y) para não materializar geometrias no Python.

    Ordem CANÔNICA e estável: (recorded_at, id). O id desempata pontos com o
    mesmo instante de captura — sem ele a polyline poderia trocar a ordem de
    pontos coincidentes entre leituras."""
    rows = db.execute(
        select(
            func.ST_X(cast(JourneyTrackPoint.location, Geometry)),
            func.ST_Y(cast(JourneyTrackPoint.location, Geometry)),
        )
        .where(JourneyTrackPoint.track_id == track_id)
        .order_by(JourneyTrackPoint.recorded_at.asc(), JourneyTrackPoint.id.asc())
    ).all()
    return [(float(lng), float(lat)) for lng, lat in rows]


def point_coords_for(
    db: Session, *, track_ids: list[uuid.UUID]
) -> dict[uuid.UUID, list[tuple[float, float]]]:
    """Coordenadas de VÁRIOS trechos numa query só (mata o N+1 do /map e da
    listagem, que antes chamavam `point_coords` uma vez por trecho). Devolve um
    dict track_id -> lista de (longitude, latitude) na ordem de captura; trechos
    sem pontos ficam de fora do dict.

    Ordem CANÔNICA e estável: (recorded_at, id) — mesma de `point_coords`, para
    que a polyline de cada trecho saia idêntica seja lida sozinha ou em lote. Só
    trechos com >= 2 pontos viram LineString no serviço; a filtragem é feita lá."""
    if not track_ids:
        return {}
    rows = db.execute(
        select(
            JourneyTrackPoint.track_id,
            func.ST_X(cast(JourneyTrackPoint.location, Geometry)),
            func.ST_Y(cast(JourneyTrackPoint.location, Geometry)),
        )
        .where(JourneyTrackPoint.track_id.in_(track_ids))
        .order_by(JourneyTrackPoint.recorded_at.asc(), JourneyTrackPoint.id.asc())
    ).all()
    grouped: dict[uuid.UUID, list[tuple[float, float]]] = {}
    for track_id, lng, lat in rows:
        grouped.setdefault(track_id, []).append((float(lng), float(lat)))
    return grouped


def point_stats_for(
    db: Session, *, track_ids: list[uuid.UUID]
) -> dict[uuid.UUID, tuple[int, float]]:
    """Metadados de VÁRIOS trechos (contagem de pontos + distância em metros) numa
    query só, SEM materializar coordenada nenhuma no Python.

    - point_count = `count(*)` agregado no banco.
    - distance_m = comprimento REAL da polyline via PostGIS: liga os pontos na
      ordem de captura (`ST_MakeLine(location::geometry ORDER BY recorded_at)`) e
      mede o resultado como geography (`ST_Length`), que devolve metros sobre o
      elipsoide — mais fiel que o haversine reta-a-reta que fazíamos em Python.
      `ST_MakeLine` de 0/1 ponto não vira linha, então `coalesce(..., 0)` garante
      distância 0 para trechos curtos.

    Devolve dict track_id -> (point_count, distance_m); trechos sem pontos ficam
    de fora (o serviço assume (0, 0.0) para esses)."""
    if not track_ids:
        return {}
    line = func.ST_MakeLine(
        aggregate_order_by(
            cast(JourneyTrackPoint.location, Geometry),
            JourneyTrackPoint.recorded_at.asc(),
            JourneyTrackPoint.id.asc(),
        )
    )
    distance = func.coalesce(func.ST_Length(cast(line, Geography)), 0.0)
    rows = db.execute(
        select(
            JourneyTrackPoint.track_id,
            func.count(JourneyTrackPoint.id),
            distance,
        )
        .where(JourneyTrackPoint.track_id.in_(track_ids))
        .group_by(JourneyTrackPoint.track_id)
    ).all()
    return {
        track_id: (int(count), float(dist))
        for track_id, count, dist in rows
    }
