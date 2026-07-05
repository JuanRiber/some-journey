"""Serviço de autenticação: orquestra as regras de negócio de cadastro e login.

Junta as camadas de baixo — repository (dados), security (hash/JWT) e schemas
(contratos) — e decide o "quê" (as regras), delegando o "como". NÃO conhece
HTTP: sinaliza falhas com exceções de domínio que a camada de rotas (9.9)
traduz em status (409/401/403). Assim o service é testável sem FastAPI, e a
mensagem genérica de credencial inválida nasce aqui (anti-enumeração).
"""

import secrets

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_access_token, hash_password, verify_password
from app.models.user import User
from app.repositories import user_repository
from app.schemas.auth import LoginRequest, LoginResponse, RegisterRequest

# Hash Argon2 "dummy" calculado UMA vez no import. No login, quando o e-mail não
# existe, verificamos a senha contra ele: roda o mesmo custo do argon2 e a
# resposta leva ~o mesmo tempo de uma senha errada — sem oráculo de timing que
# revele se o e-mail está cadastrado (anti-enumeração).
_DUMMY_PASSWORD_HASH = hash_password(secrets.token_urlsafe(32))


class EmailAlreadyRegisteredError(Exception):
    """E-mail já cadastrado — a rota traduz para 409 Conflict."""


class InvalidCredentialsError(Exception):
    """E-mail ou senha inválidos — a rota traduz para 401 (mensagem genérica)."""


class InactiveUserError(Exception):
    """Conta inativa — a rota traduz para 403 Forbidden."""


def register(db: Session, data: RegisterRequest) -> User:
    """Cadastra um usuário: e-mail único, senha vira hash, persiste.

    A checagem de e-mail aqui dá a mensagem limpa (409); a constraint UNIQUE do
    banco é a garantia final contra corrida (o repository propaga o IntegrityError).
    """
    if user_repository.get_by_email(db, data.email) is not None:
        raise EmailAlreadyRegisteredError()
    password_hash = hash_password(data.password)
    try:
        return user_repository.create(
            db,
            name=data.name,
            email=data.email,
            password_hash=password_hash,
        )
    except IntegrityError:
        raise EmailAlreadyRegisteredError()


def login(db: Session, data: LoginRequest) -> LoginResponse:
    """Autentica e emite o token.

    Ordem proposital: primeiro confere a credencial (e-mail + senha) com mensagem
    GENÉRICA (não revela se errou e-mail ou senha — anti-enumeração); só então
    checa se a conta está ativa. Assim, só quem tem a credencial certa descobre
    que a conta está inativa.
    """
    user = user_repository.get_by_email(db, data.email)
    if user is None:
        # E-mail inexistente: roda argon2 contra o hash dummy para que o tempo de
        # resposta seja ~igual ao de uma senha errada (não vaza se o e-mail existe).
        verify_password(data.password, _DUMMY_PASSWORD_HASH)
        raise InvalidCredentialsError()
    if not verify_password(data.password, user.password_hash):
        raise InvalidCredentialsError()
    if not user.is_active:
        raise InactiveUserError()
    access_token = create_access_token(user.id)
    return LoginResponse(
        access_token=access_token,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )
