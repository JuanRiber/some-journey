"""Schemas (Pydantic v2) do percurso real (GPS) e do mapa da jornada.

Entrada: iniciar trecho, enviar pontos em lote, finalizar. Saída: leitura de
trecho (com contagem e distância) e o mapa da jornada em GeoJSON pronto para o
frontend desenhar (percurso real em LineString + memórias em Point + rastro
simbólico opcional).
"""

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.journey import JourneyRoute

TrackSource = Literal["manual", "gps_live", "imported"]

# Teto do lote de pontos por request (protege contra payloads absurdos).
MAX_TRACK_POINTS_PER_BATCH = 1000


# --- Entrada ---------------------------------------------------------------


class TrackStart(BaseModel):
    """POST /journeys/{id}/tracks/start — abre um trecho de gravação."""

    model_config = ConfigDict(extra="forbid")

    source: TrackSource = "gps_live"
    started_at: datetime | None = None


class TrackPointIn(BaseModel):
    """Um ponto GPS. lat/long validados; metadados opcionais; recorded_at é
    quando o device capturou o ponto."""

    model_config = ConfigDict(extra="forbid")

    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy: float | None = None
    altitude: float | None = None
    speed: float | None = None
    heading: float | None = None
    recorded_at: datetime


class TrackPointsBatch(BaseModel):
    """POST .../tracks/{track_id}/points — envio em lote (aceita 1..N pontos)."""

    model_config = ConfigDict(extra="forbid")

    points: list[TrackPointIn] = Field(
        min_length=1, max_length=MAX_TRACK_POINTS_PER_BATCH
    )


# --- Saída -----------------------------------------------------------------


class TrackRead(BaseModel):
    """Um trecho: metadados + contagem de pontos + distância aproximada (m)."""

    id: uuid.UUID
    journey_id: uuid.UUID
    source: str
    started_at: datetime
    ended_at: datetime | None
    is_active: bool
    point_count: int
    distance_m: float
    created_at: datetime


# --- GeoJSON do mapa da jornada --------------------------------------------


class GeoLineString(BaseModel):
    type: Literal["LineString"] = "LineString"
    coordinates: list[list[float]]  # [[lng, lat], ...]


class GeoPoint(BaseModel):
    type: Literal["Point"] = "Point"
    coordinates: list[float]  # [lng, lat]


class TrackFeatureProps(BaseModel):
    track_id: uuid.UUID
    source: str
    started_at: datetime
    ended_at: datetime | None
    point_count: int
    distance_m: float


class TrackFeature(BaseModel):
    type: Literal["Feature"] = "Feature"
    properties: TrackFeatureProps
    geometry: GeoLineString


class TrackFeatureCollection(BaseModel):
    type: Literal["FeatureCollection"] = "FeatureCollection"
    features: list[TrackFeature]


class MemoryFeatureProps(BaseModel):
    memory_id: uuid.UUID
    title: str
    image_url: str | None
    memory_date: datetime


class MemoryFeature(BaseModel):
    type: Literal["Feature"] = "Feature"
    properties: MemoryFeatureProps
    geometry: GeoPoint


class MemoryFeatureCollection(BaseModel):
    type: Literal["FeatureCollection"] = "FeatureCollection"
    features: list[MemoryFeature]


class JourneyMapRef(BaseModel):
    id: uuid.UUID
    title: str


class JourneyMapResponse(BaseModel):
    """GET /journeys/{id}/map — tudo para desenhar o capítulo:
    - tracks: percurso REAL (uma LineString por trecho com >= 2 pontos);
    - memories: pins das memórias da jornada (com image_url e memory_date);
    - symbolic_route: rastro simbólico (liga as memórias na ordem) para o modo
      "Conectar memórias" quando não há GPS — None se < 2 memórias;
    - distance_m: distância total aproximada dos trechos reais (metros)."""

    journey: JourneyMapRef
    tracks: TrackFeatureCollection
    memories: MemoryFeatureCollection
    symbolic_route: JourneyRoute | None
    distance_m: float
