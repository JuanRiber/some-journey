"""Contratos das fases da vida.

O que NÃO está aqui é tão importante quanto o que está: não há lista de fases
predefinidas, não há campo obrigatório além do nome, e `color` é validada
contra os papéis da paleta no domínio — não contra um hexadecimal livre.
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.domain.life_phase import DESCRICAO_MAX, NOME_MAX
from app.schemas._fields import AwareUtcDatetime


class LifePhaseCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=NOME_MAX)
    description: str | None = Field(default=None, max_length=DESCRICAO_MAX)
    # O formato é validado no DOMÍNIO (app.domain.life_phase), que tem a lista
    # de papéis e a mensagem em pt-BR; aqui só o teto de tamanho.
    color: str | None = Field(default=None, max_length=20)
    # UTC-aware: uma data naive ao lado de uma aware (a do banco, ou a outra do
    # mesmo corpo) quebrava a comparação do período com TypeError — 500.
    started_at: AwareUtcDatetime | None = None
    ended_at: AwareUtcDatetime | None = None


class LifePhaseUpdate(BaseModel):
    """Edição PARCIAL: o que não vier não muda.

    `description`, `started_at` e `ended_at` aceitam `null` para LIMPAR — ao
    contrário do PATCH de jornada, onde null é um no-op silencioso. Aqui a
    diferença importa: uma fase que ganhou fim por engano precisa poder voltar
    a ser a fase em curso, e "mandar string vazia" não funciona para data.
    """

    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, min_length=1, max_length=NOME_MAX)
    description: str | None = Field(default=None, max_length=DESCRICAO_MAX)
    color: str | None = Field(default=None, max_length=20)
    started_at: AwareUtcDatetime | None = None
    ended_at: AwareUtcDatetime | None = None


class LifePhaseRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    description: str | None
    color: str
    started_at: datetime | None
    ended_at: datetime | None
    created_at: datetime
