"""Serviço de autenticação: orquestra as regras de negócio de cadastro e login.

Junta as camadas de baixo — repository (dados), security (hash/JWT) e schemas
(contratos) — e decide o "quê" (as regras), delegando o "como". NÃO conhece
HTTP: sinaliza falhas com exceções de domínio que a camada de rotas (9.9)
traduz em status (409/401/403). Assim o service é testável sem FastAPI, e a
mensagem genérica de credencial inválida nasce aqui (anti-enumeração).
"""

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_access_token, hash_password, verify_password
from app.models.user import User
from app.repositories import user_repository
from app.schemas.auth import LoginRequest, LoginResponse, RegisterRequest


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
    return user_repository.create(
        db,
        name=data.name,
        email=data.email,
        password_hash=password_hash,
    )


def login(db: Session, data: LoginRequest) -> LoginResponse:
    """Autentica e emite o token.

    Ordem proposital: primeiro confere a credencial (e-mail + senha) com mensagem
    GENÉRICA (não revela se errou e-mail ou senha — anti-enumeração); só então
    checa se a conta está ativa. Assim, só quem tem a credencial certa descobre
    que a conta está inativa.
    """
    user = user_repository.get_by_email(db, data.email)
    if user is None or not verify_password(data.password, user.password_hash):
        raise InvalidCredentialsError()
    if not user.is_active:
        raise InactiveUserError()
    access_token = create_access_token(user.id)
    return LoginResponse(
        access_token=access_token,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )
