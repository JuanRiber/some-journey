"""Schemas do mapa principal (GET /map).

DTOs puros de saída: o service converte os models (GEOGRAPHY) em lat/long e
monta os rastros. Reaproveita JourneyStatus e JourneyRoute do contrato de
jornadas para não duplicar a forma do LineString nem o conjunto de status.
"""

import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.journey import JourneyRoute, JourneyStatus


class MapPoint(BaseModel):
    """Um pin no mapa. `position` só vem preenchido quando o ponto pertence a
    uma jornada (ordem no rastro); pontos soltos não têm posição."""

    memory_id: uuid.UUID
    title: str
    latitude: float
    longitude: float
    occurred_at: datetime
    position: int | None = None


class MapJourney(BaseModel):
    """Uma jornada no mapa: seus pontos ordenados + o rastro (LineString).
    `route` é None quando a jornada tem menos de 2 pontos (sem rastro)."""

    id: uuid.UUID
    title: str
    status: JourneyStatus
    points: list[MapPoint]
    route: JourneyRoute | None


class MapResponse(BaseModel):
    """Tudo que o front precisa para desenhar o mapa do usuário:
    pins soltos + jornadas (pins + rastros)."""

    loose_points: list[MapPoint]
    journeys: list[MapJourney]
