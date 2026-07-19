"""Serviço do mapa principal.

Junta as duas camadas de dados que o mapa precisa — pins soltos (memórias sem
jornada) e jornadas (pins ordenados + rastro) — convertendo GEOGRAPHY em
lat/long. Todo acesso passa pelos repositories, que já filtram por user_id
(ownership) e deleted_at (soft delete).
"""

import uuid

from geoalchemy2.shape import to_shape
from sqlalchemy.orm import Session

from app.models.journey import Journey
from app.models.memory import Memory
from app.repositories import journey_repository, memory_repository
from app.repositories.memory_repository import Bbox
from app.schemas.journey import JourneyRoute
from app.schemas.map import MapJourney, MapPoint, MapResponse
from app.services.journey_service import JourneyNotFoundError


def _memory_to_point(memory: Memory, *, position: int | None = None) -> MapPoint:
    point = to_shape(memory.location)
    return MapPoint(
        memory_id=memory.id,
        title=memory.title,
        latitude=point.y,
        longitude=point.x,
        occurred_at=memory.occurred_at,
        position=position,
    )


def _route(points: list[MapPoint]) -> JourneyRoute | None:
    """LineString exige >= 2 posições; com 0/1 ponto não há rastro."""
    if len(points) < 2:
        return None
    return JourneyRoute(
        coordinates=[[p.longitude, p.latitude] for p in points]
    )


def _in_bbox(point: MapPoint, bbox: Bbox) -> bool:
    min_lng, min_lat, max_lng, max_lat = bbox
    return min_lng <= point.longitude <= max_lng and min_lat <= point.latitude <= max_lat


def _journey_to_map(
    journey: Journey,
    rows: list[tuple[object, Memory]],
) -> MapJourney:
    points = [_memory_to_point(memory, position=item.position) for item, memory in rows]
    return MapJourney(
        id=journey.id,
        title=journey.title,
        status=journey.status,  # type: ignore[arg-type]
        points=points,
        route=_route(points),
    )


def get_map(
    db: Session,
    *,
    user_id: uuid.UUID,
    bbox: Bbox | None = None,
    journey_id: uuid.UUID | None = None,
) -> MapResponse:
    # Filtro por jornada: devolve só aquela jornada (destaque), sem pins soltos.
    if journey_id is not None:
        journey = journey_repository.get_journey(
            db, user_id=user_id, journey_id=journey_id
        )
        if journey is None:
            raise JourneyNotFoundError()
        rows = journey_repository.list_points(
            db, journey_id=journey.id, user_id=user_id
        )
        return MapResponse(
            loose_points=[],
            journeys=[_journey_to_map(journey, rows)],
        )

    loose = [
        _memory_to_point(m)
        for m in memory_repository.list_loose(db, user_id=user_id, bbox=bbox)
    ]
    all_journeys = [j for j, _count in journey_repository.list_journeys(db, user_id=user_id)]
    # Pontos de TODAS as jornadas numa query só (sem N+1).
    points_by_journey = journey_repository.list_points_for_journeys(
        db, journey_ids=[j.id for j in all_journeys], user_id=user_id
    )
    journeys: list[MapJourney] = []
    for journey in all_journeys:
        mapped = _journey_to_map(journey, points_by_journey.get(journey.id, []))
        # Com bbox, mantém só jornadas que tocam a viewport — mas o rastro vem
        # inteiro (não corta a linha no meio). Sem pontos = não aparece no mapa.
        if bbox is not None and not any(_in_bbox(p, bbox) for p in mapped.points):
            continue
        if mapped.points:
            journeys.append(mapped)
    return MapResponse(loose_points=loose, journeys=journeys)
