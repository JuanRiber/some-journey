"""Repository do percurso real: journey_tracks e journey_track_points.

Camada fina de acesso a dados. Recebe a Session pronta. Toda leitura filtra por
ownership (user_id) e trechos ativos (deleted_at IS NULL). A localização é
gravada como POINT(longitude, latitude) — longitude primeiro.
"""

import uuid
from datetime import datetime

from geoalchemy2 import Geometry
from sqlalchemy import cast, func, select
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
    """Insere um lote de pontos GPS. Retorna quantos foram inseridos."""
    db.add_all(
        [
            JourneyTrackPoint(
                track_id=track_id,
                journey_id=journey_id,
                user_id=user_id,
                location=_point(p.latitude, p.longitude),
                accuracy=p.accuracy,
                altitude=p.altitude,
                speed=p.speed,
                heading=p.heading,
                recorded_at=p.recorded_at,
            )
            for p in points
        ]
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
    lng/lat no banco (ST_X/ST_Y) para não materializar geometrias no Python."""
    rows = db.execute(
        select(
            func.ST_X(cast(JourneyTrackPoint.location, Geometry)),
            func.ST_Y(cast(JourneyTrackPoint.location, Geometry)),
        )
        .where(JourneyTrackPoint.track_id == track_id)
        .order_by(JourneyTrackPoint.recorded_at.asc())
    ).all()
    return [(float(lng), float(lat)) for lng, lat in rows]
