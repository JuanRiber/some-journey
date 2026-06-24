"""Schemas Pydantic (v2) dos contratos de autenticação.

Camada de contrato da API: define o formato de ENTRADA e SAÍDA dos endpoints
de auth, separada do model ORM (app.models.user.User). Estilo Pydantic v2
moderno: BaseModel, Field(...) com constraints, ConfigDict, EmailStr, uuid.UUID
e datetime.

Segurança (fronteira de exposição): o ORM contém password_hash, mas NENHUM
schema daqui o expõe. `password` é SOMENTE entrada (jamais sai). As saídas que
leem do ORM usam ConfigDict(from_attributes=True) e listam apenas campos
públicos — a proteção do hash vem da AUSÊNCIA do campo, nunca de um exclude.

Dependência: EmailStr exige o pacote `email-validator` (pinado no
requirements.txt). Sem ele, o import deste módulo falharia já na definição da
classe (no startup), não por requisição.
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field


# --- POST /auth/register ---------------------------------------------------


class RegisterRequest(BaseModel):
    """Corpo do cadastro. `password` é texto puro de ENTRADA (vira hash no
    service); nunca é persistido nem retornado em texto puro."""

    # extra="forbid": rejeita campos não declarados com 422 em vez de
    # descartá-los em silêncio — bloqueia payloads de sondagem como
    # {"password_hash": "..."} numa fronteira de autenticação.
    model_config = ConfigDict(extra="forbid")

    # name obrigatório; a tabela limita a 120 chars (String(120)).
    name: str = Field(min_length=1, max_length=120)
    # email obrigatório e VÁLIDO (EmailStr).
    email: EmailStr
    # password obrigatório, no mínimo 7 caracteres. Só entrada, nunca sai.
    password: str = Field(min_length=10, max_length=128)


class RegisterResponse(BaseModel):
    """Resposta 201: {id, name, email, created_at}. NÃO retorna JWT nem
    password/password_hash. Lida a partir da instância ORM recém-criada."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    email: EmailStr
    created_at: datetime


# --- POST /auth/login ------------------------------------------------------


class LoginRequest(BaseModel):
    """Credenciais de login em JSON. `password` é só entrada e NÃO tem
    min_length (o login apenas confere a credencial existente; a regra de
    força de senha vale no cadastro)."""

    model_config = ConfigDict(extra="forbid")

    email: EmailStr
    password: str = Field(max_length=128)


class LoginResponse(BaseModel):
    """Resposta 200: {access_token, token_type, expires_in}. Schema de saída
    puro (não lê do ORM): o token é emitido pelo service."""

    access_token: str
    token_type: str = "bearer"  # default do contrato
    # expires_in em SEGUNDOS.
    expires_in: int


# --- GET /auth/me ----------------------------------------------------------


class UserResponse(BaseModel):
    """Resposta 200 do GET /auth/me: {id, name, email, is_active, created_at}.
    Dados públicos do usuário autenticado (lidos do ORM)."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    email: EmailStr
    is_active: bool
    created_at: datetime
