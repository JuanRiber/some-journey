"""Contrato do Perfil (GET /me/profile).

Um único payload com tudo que a tela precisa. Estruturado em BLOCOS (identidade,
estatísticas, passaporte, jornada atual, última aventura) em vez de um dicionário
plano: a tela cresce (conquistas, coleções, avatar, @username) e cada bloco novo
entra sem quebrar quem já consome os anteriores.
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class ProfileIdentity(BaseModel):
    """Quem é a pessoa. `member_since` é a PRIMEIRA memória (a história começa
    quando ela registra algo), com o cadastro como base."""

    id: uuid.UUID
    name: str
    email: str
    joined_at: datetime
    member_since: datetime | None = None
    # Reservados para a evolução da tela — o cliente já pode ler sem novo deploy
    # do contrato quando forem preenchidos.
    username: str | None = None
    avatar_url: str | None = None
    bio: str | None = None


class ProfileUpdate(BaseModel):
    """Edição da identidade pública. Parcial: o que não vier não muda.

    `extra="forbid"` numa fronteira de escrita de conta — um payload com campos
    desconhecidos é sondagem, não descuido, e deve falhar alto (422)."""

    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, min_length=1, max_length=120)
    # O formato do @username é validado no DOMÍNIO (app.domain.username), que
    # tem as mensagens em pt-BR e a lista de reservados; aqui só o teto de tamanho.
    username: str | None = Field(default=None, max_length=30)
    bio: str | None = Field(default=None, max_length=160)


class ProfileStats(BaseModel):
    """Os números do viajante. Todos calculados em SQL."""

    memories: int
    journeys: int
    journeys_finished: int
    cities: int
    countries: int
    continents: int
    photos: int
    tracks: int
    tracked_meters: float
    active_days: int
    # Transparência operacional: quantas memórias ainda esperam geocodificação
    # (o Passaporte fica incompleto até o backfill rodar).
    pending_geocode: int


class PassportStamp(BaseModel):
    """Um continente e se já foi carimbado."""

    continent: str
    visited: bool


class LastAdventure(BaseModel):
    city: str | None = None
    country: str | None = None
    country_code: str | None = None
    occurred_at: datetime | None = None


class CurrentJourney(BaseModel):
    id: uuid.UUID
    title: str
    started_at: datetime | None = None
    points_count: int


class ProfileRead(BaseModel):
    """A resposta completa de GET /me/profile."""

    identity: ProfileIdentity
    stats: ProfileStats
    passport: list[PassportStamp]
    last_adventure: LastAdventure | None = None
    current_journey: CurrentJourney | None = None
