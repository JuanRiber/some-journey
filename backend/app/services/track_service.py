"""Serviço do percurso real (GPS) e do mapa da jornada.

Orquestra as regras: iniciar/finalizar trecho (com "no máximo um aberto por
jornada"), receber pontos em lote e montar o mapa da jornada em GeoJSON
(percurso real + memórias + rastro simbólico). Não conhece HTTP — sinaliza com
exceções de domínio que a rota traduz em 404/409. Ownership sempre pelo token.
"""

import uuid
from datetime import UTC, datetime

from geoalchemy2.shape import to_shape
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.track import JourneyTrack
from app.repositories import journey_repository, track_repository
from app.schemas.journey import JourneyRoute
from app.schemas.track import (
    GeoLineString,
    GeoPoint,
    JourneyMapRef,
    JourneyMapResponse,
    MemoryFeature,
    MemoryFeatureCollection,
    MemoryFeatureProps,
    TrackFeature,
    TrackFeatureCollection,
    TrackFeatureProps,
    TrackPointsBatch,
    TrackRead,
    TrackStart,
)
from app.services import memory_service
from app.services.journey_service import JourneyClosedError, JourneyNotFoundError


class TrackNotFoundError(Exception):
    """Trecho inexistente, apagado, ou de outra jornada/usuário — vira 404."""


class TrackAlreadyActiveError(Exception):
    """Já existe um trecho aberto (em gravação) nesta jornada — vira 409."""


class TrackClosedError(Exception):
    """Não dá para adicionar pontos a um trecho já finalizado — vira 409."""


def _build_read(track: JourneyTrack, point_count: int, distance_m: float) -> TrackRead:
    """Monta o DTO de saída de um trecho a partir de metadados JÁ calculados no
    banco (contagem + distância em metros). Separado de `_track_to_read` para que
    a listagem possa reaproveitar estatísticas buscadas EM LOTE (uma query só)
    sem uma ida ao banco por trecho."""
    return TrackRead(
        id=track.id,
        journey_id=track.journey_id,
        source=track.source,
        started_at=track.started_at,
        ended_at=track.ended_at,
        is_active=track.ended_at is None,
        point_count=point_count,
        distance_m=round(distance_m, 1),
        created_at=track.created_at,
    )


def _track_to_read(db: Session, track: JourneyTrack) -> TrackRead:
    """Leitura de UM trecho: contagem e distância vêm do banco (count(*) +
    ST_Length da polyline), sem materializar as coordenadas no Python — o cliente
    de start/points/finish só quer os números, não a geometria."""
    count, distance = track_repository.point_stats_for(
        db, track_ids=[track.id]
    ).get(track.id, (0, 0.0))
    return _build_read(track, count, distance)


def start_track(
    db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID, data: TrackStart
) -> TrackRead:
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is None:
        raise JourneyNotFoundError()
    # Jornada 'finished' é terminal: não abre gravação nova (mesma regra que o
    # caminho das memórias, que já recusa pontos numa jornada encerrada).
    if journey.status == "finished":
        raise JourneyClosedError()
    if track_repository.get_open_track(db, journey_id=journey.id) is not None:
        raise TrackAlreadyActiveError()
    try:
        track = track_repository.create_track(
            db,
            user_id=user_id,
            journey_id=journey.id,
            source=data.source,
            started_at=data.started_at,
        )
    except IntegrityError as exc:
        # Corrida: outro request abriu um trecho ao mesmo tempo (índice único).
        db.rollback()
        raise TrackAlreadyActiveError() from exc
    return _track_to_read(db, track)


def add_points(
    db: Session,
    *,
    user_id: uuid.UUID,
    journey_id: uuid.UUID,
    track_id: uuid.UUID,
    data: TrackPointsBatch,
) -> TrackRead:
    track = track_repository.get_track(
        db, user_id=user_id, journey_id=journey_id, track_id=track_id
    )
    if track is None:
        raise TrackNotFoundError()
    if track.ended_at is not None:
        raise TrackClosedError()
    # Jornada 'finished' é terminal: não recebe mais GPS, ainda que o trecho em si
    # continue aberto (consistente com o bloqueio do caminho das memórias). Leitura
    # read-only da jornada pai; o trecho já garante ownership (user_id/journey_id).
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is not None and journey.status == "finished":
        raise JourneyClosedError()
    track_repository.add_points(
        db,
        track_id=track.id,
        journey_id=journey_id,
        user_id=user_id,
        points=data.points,
    )
    return _track_to_read(db, track)


def finish_track(
    db: Session,
    *,
    user_id: uuid.UUID,
    journey_id: uuid.UUID,
    track_id: uuid.UUID,
    ended_at: datetime | None = None,
) -> TrackRead:
    track = track_repository.get_track(
        db, user_id=user_id, journey_id=journey_id, track_id=track_id
    )
    if track is None:
        raise TrackNotFoundError()
    if track.ended_at is None:  # idempotente: finalizar já finalizado não muda nada
        track_repository.finish_track(
            db, track=track, ended_at=ended_at or datetime.now(UTC)
        )
    return _track_to_read(db, track)


def list_tracks(
    db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID
) -> list[TrackRead]:
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is None:
        raise JourneyNotFoundError()
    tracks = track_repository.list_tracks(db, user_id=user_id, journey_id=journey.id)
    # Estatísticas (contagem + distância) de TODOS os trechos numa query só —
    # antes era um `point_coords` por trecho (N+1). Trechos sem pontos não voltam
    # no dict; assume-se (0, 0.0) para eles.
    stats = track_repository.point_stats_for(db, track_ids=[t.id for t in tracks])
    return [_build_read(t, *stats.get(t.id, (0, 0.0))) for t in tracks]


def delete_track(
    db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID, track_id: uuid.UUID
) -> None:
    """Remove o percurso (soft-delete do trecho). NÃO apaga as memórias."""
    track = track_repository.get_track(
        db, user_id=user_id, journey_id=journey_id, track_id=track_id
    )
    if track is None:
        raise TrackNotFoundError()
    track_repository.soft_delete_track(db, track=track)


def get_journey_map(
    db: Session, *, user_id: uuid.UUID, journey_id: uuid.UUID
) -> JourneyMapResponse:
    """Monta o mapa da jornada: percurso real (LineString por trecho) + memórias
    (Point) + rastro simbólico (liga as memórias na ordem). 404 se não é do
    usuário. Só devolve dados DESTA jornada."""
    journey = journey_repository.get_journey(db, user_id=user_id, journey_id=journey_id)
    if journey is None:
        raise JourneyNotFoundError()

    rows = journey_repository.list_points(db, journey_id=journey.id, user_id=user_id)
    memories = [memory for _, memory in rows]
    reads = memory_service.reads_for(db, memories)
    image_by_id = {read.id: read.image_url for read in reads}

    mem_features: list[MemoryFeature] = []
    symbolic_coords: list[list[float]] = []
    for _link, memory in rows:
        point = to_shape(memory.location)
        lng, lat = point.x, point.y
        mem_features.append(
            MemoryFeature(
                properties=MemoryFeatureProps(
                    memory_id=memory.id,
                    title=memory.title,
                    image_url=image_by_id.get(memory.id),
                    memory_date=memory.occurred_at,
                ),
                geometry=GeoPoint(coordinates=[lng, lat]),
            )
        )
        symbolic_coords.append([lng, lat])
    symbolic_route = (
        JourneyRoute(coordinates=symbolic_coords) if len(symbolic_coords) >= 2 else None
    )

    # Percurso real: uma query para os trechos, UMA para todas as coordenadas
    # (a LineString precisa da geometria) e UMA para contagem+distância — em vez
    # de duas idas ao banco POR trecho (N+1). A distância vem do PostGIS
    # (point_stats_for), a mesma fonte de `list_tracks`, para que o mesmo trecho
    # relate a mesma distância nos dois endpoints.
    tracks = track_repository.list_tracks(db, user_id=user_id, journey_id=journey.id)
    track_ids = [t.id for t in tracks]
    coords_by_track = track_repository.point_coords_for(db, track_ids=track_ids)
    stats_by_track = track_repository.point_stats_for(db, track_ids=track_ids)

    track_features: list[TrackFeature] = []
    total_distance = 0.0
    for track in tracks:
        coords = coords_by_track.get(track.id, [])
        count, dist = stats_by_track.get(track.id, (0, 0.0))
        total_distance += dist
        if len(coords) >= 2:
            track_features.append(
                TrackFeature(
                    properties=TrackFeatureProps(
                        track_id=track.id,
                        source=track.source,
                        started_at=track.started_at,
                        ended_at=track.ended_at,
                        point_count=count,
                        distance_m=round(dist, 1),
                    ),
                    geometry=GeoLineString(coordinates=[[lng, lat] for lng, lat in coords]),
                )
            )

    return JourneyMapResponse(
        journey=JourneyMapRef(id=journey.id, title=journey.title),
        tracks=TrackFeatureCollection(features=track_features),
        memories=MemoryFeatureCollection(features=mem_features),
        symbolic_route=symbolic_route,
        distance_m=round(total_distance, 1),
    )
