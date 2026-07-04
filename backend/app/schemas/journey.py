import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


JourneyStatus = Literal["draft", "active", "paused", "finished"]


class JourneyCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=5000)
    started_at: datetime | None = None


class JourneyUpdate(BaseModel):
    """Entrada do PATCH /journeys/{id}: edita os METADADOS (título/descrição).
    O ciclo de vida (status/datas) tem endpoints próprios. Tudo opcional
    (atualização parcial); só os campos enviados são alterados."""

    model_config = ConfigDict(extra="forbid")

    title: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=5000)


class JourneyRead(BaseModel):
    id: uuid.UUID
    title: str
    description: str | None
    status: JourneyStatus
    started_at: datetime | None
    ended_at: datetime | None
    points_count: int
    created_at: datetime


class JourneyPointRead(BaseModel):
    memory_id: uuid.UUID
    position: int
    title: str
    text: str
    latitude: float
    longitude: float
    occurred_at: datetime
    created_at: datetime


class JourneyRoute(BaseModel):
    type: Literal["LineString"] = "LineString"
    coordinates: list[list[float]]


class JourneyDetailRead(JourneyRead):
    points: list[JourneyPointRead]
    # route é o rastro no mapa. Um LineString GeoJSON exige >= 2 posições; com 0
    # ou 1 ponto não há rastro, então route vem como null (o front desenha só os
    # pins). Ver journey_service._detail.
    route: JourneyRoute | None


class JourneyFinish(BaseModel):
    model_config = ConfigDict(extra="forbid")

    ended_at: datetime | None = None


class JourneyMemoryAdd(BaseModel):
    model_config = ConfigDict(extra="forbid")

    memory_id: uuid.UUID


class JourneyMemoryCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=120)
    text: str = Field(min_length=1, max_length=5000)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    occurred_at: datetime


class JourneyReorder(BaseModel):
    model_config = ConfigDict(extra="forbid")

    memory_ids: list[uuid.UUID] = Field(min_length=1)

    @model_validator(mode="after")
    def _memory_ids_unique(self) -> "JourneyReorder":
        if len(set(self.memory_ids)) != len(self.memory_ids):
            raise ValueError("memory_ids nao pode conter duplicatas")
        return self
