"""Schemas Pydantic (v2) dos contratos de Memórias.

A API fala em linguagem humana — `latitude`/`longitude`; o model guarda
`GEOGRAPHY(POINT, 4326)`. A conversão lat/long ↔ POINT acontece no SERVICE,
não aqui: estes são DTOs puros.

Segurança: `image_path` NUNCA entra por estes schemas (upload é um fluxo
separado, controlado pelo backend). `user_id` também não — vem do token.
Na saída só aparece `image_url` (URL temporária; por ora None).
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, model_validator


class MemoryCreate(BaseModel):
    """Entrada do POST /memories."""

    # extra="forbid": bloqueia campos não declarados (ex.: image_path, user_id).
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=120)
    text: str = Field(min_length=1, max_length=5000)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    occurred_at: datetime


class MemoryUpdate(BaseModel):
    """Entrada do PATCH /memories/{id}. Tudo opcional (atualização parcial)."""

    model_config = ConfigDict(extra="forbid")

    title: str | None = Field(default=None, min_length=1, max_length=120)
    text: str | None = Field(default=None, min_length=1, max_length=5000)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    occurred_at: datetime | None = None

    @model_validator(mode="after")
    def _lat_long_juntas(self) -> "MemoryUpdate":
        # Não dá pra mover só metade do ponto: latitude e longitude andam juntas.
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("latitude e longitude devem ser enviadas juntas")
        return self


class MemoryRead(BaseModel):
    """Saída: o que a API devolve de uma memória. Sem user_id, sem location
    crua, sem image_path — o service constrói este DTO a partir do model."""

    id: uuid.UUID
    title: str
    text: str
    latitude: float
    longitude: float
    occurred_at: datetime
    created_at: datetime
    image_url: str | None = None
