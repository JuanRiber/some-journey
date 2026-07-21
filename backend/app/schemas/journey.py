import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.schemas._fields import AwareUtcDatetime


JourneyStatus = Literal["draft", "active", "paused", "finished"]


class JourneyCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=5000)
    # Atmosfera livre (ex.: "noturno, nostálgico"). Opcional.
    mood: str | None = Field(default=None, max_length=120)
    # Nasce privada por padrão (compartilhamento é V3).
    is_private: bool = True
    # Período descritivo da jornada. Opcional; o ciclo de vida (start/finish)
    # também preenche started_at/ended_at por conta própria. Normalizados para
    # UTC-aware (AwareUtcDatetime) — as colunas são TIMESTAMPTZ.
    started_at: AwareUtcDatetime | None = None
    ended_at: AwareUtcDatetime | None = None

    @model_validator(mode="after")
    def _dates_consistent(self) -> "JourneyCreate":
        # Só valida quando o cliente informa AMBOS: um período com fim antes do
        # início é incoerente. ValueError vira 422 nativo do Pydantic (mesmo
        # status que a rota mapeia para o InvalidJourneyDatesError do finish()).
        if (
            self.started_at is not None
            and self.ended_at is not None
            and self.ended_at < self.started_at
        ):
            raise ValueError("ended_at nao pode ser anterior a started_at")
        return self


class JourneyUpdate(BaseModel):
    """Entrada do PATCH /journeys/{id}: edita os METADADOS (título, descrição,
    atmosfera, privacidade e período). As transições de status têm endpoints
    próprios (start/pause/resume/finish). Tudo opcional (atualização parcial);
    só os campos enviados são alterados."""

    model_config = ConfigDict(extra="forbid")

    title: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=5000)
    mood: str | None = Field(default=None, max_length=120)
    is_private: bool | None = None
    started_at: datetime | None = None
    ended_at: datetime | None = None


class JourneyRead(BaseModel):
    id: uuid.UUID
    title: str
    description: str | None
    mood: str | None
    is_private: bool
    # URL assinada da capa (por ora sempre None: upload de capa é evolução).
    cover_image_url: str | None
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

    # UTC-aware (a coluna é TIMESTAMPTZ); o serviço valida ended_at >= started_at.
    ended_at: AwareUtcDatetime | None = None


class JourneyMemoryAdd(BaseModel):
    model_config = ConfigDict(extra="forbid")

    memory_id: uuid.UUID


class JourneyMemoryCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=120)
    # Descrição OPCIONAL (mesmo critério da memória avulsa).
    text: str = Field(default="", max_length=5000)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    # UTC-aware (a coluna occurred_at da memória é TIMESTAMPTZ).
    occurred_at: AwareUtcDatetime


class JourneyReorder(BaseModel):
    model_config = ConfigDict(extra="forbid")

    memory_ids: list[uuid.UUID] = Field(min_length=1)

    @model_validator(mode="after")
    def _memory_ids_unique(self) -> "JourneyReorder":
        if len(set(self.memory_ids)) != len(self.memory_ids):
            raise ValueError("memory_ids nao pode conter duplicatas")
        return self
