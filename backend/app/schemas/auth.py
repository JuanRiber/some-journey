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
from typing import Annotated

from pydantic import BaseModel, BeforeValidator, ConfigDict, EmailStr, Field


def _normalize_email(value: object) -> object:
    """Canoniza o e-mail ANTES da validação de formato: remove espaços nas
    pontas e passa para minúsculo — exatamente o `raw.strip().lower()` que os
    scripts (seed_users/reset_password) já aplicam. Assim register, login e seed
    convergem para a MESMA forma canônica: não nasce conta duplicada por case
    (`A@x.com` vs `a@x.com`) e o login não falha só porque a pessoa digitou o
    e-mail com maiúsculas diferentes de como foi cadastrado.

    Roda como BeforeValidator (antes do EmailStr), então também salva e-mails com
    espaço acidental nas pontas, que o EmailStr sozinho rejeitaria. Valores não
    string passam intactos para o EmailStr levantar o erro de tipo adequado.
    """
    return value.strip().lower() if isinstance(value, str) else value


# E-mail já normalizado (strip + lowercase) e com formato validado pelo EmailStr.
# Usado só na ENTRADA (register/login); as saídas leem o valor já canônico do banco.
NormalizedEmail = Annotated[EmailStr, BeforeValidator(_normalize_email)]


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
    # email obrigatório, VÁLIDO e NORMALIZADO (strip + lowercase) na entrada.
    email: NormalizedEmail
    # password obrigatório, no mínimo 10 caracteres. Só entrada, nunca sai.
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

    # Mesma normalização do cadastro: o login precisa achar a conta pela forma
    # canônica, senão um e-mail com case diferente não casaria com o gravado.
    email: NormalizedEmail
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
