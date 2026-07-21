"""Serviço de autenticação: orquestra as regras de negócio de cadastro e login.

Junta as camadas de baixo — repository (dados), security (hash/JWT) e schemas
(contratos) — e decide o "quê" (as regras), delegando o "como". NÃO conhece
HTTP: sinaliza falhas com exceções de domínio que a camada de rotas (9.9)
traduz em status (409/401/403). Assim o service é testável sem FastAPI, e a
mensagem genérica de credencial inválida nasce aqui (anti-enumeração).
"""

import hashlib
import secrets
from datetime import UTC, datetime, timedelta

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_access_token, hash_password, verify_password
from app.models.user import User
from app.repositories import password_reset_repository, user_repository
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
    # pcat = password_changed_at vigente: o token só vale enquanto a senha não
    # for trocada/redefinida (ver get_current_user).
    access_token = create_access_token(user.id, user.password_changed_at)
    return LoginResponse(
        access_token=access_token,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


def change_password(
    db: Session, *, user: User, current_password: str, new_password: str
) -> None:
    """Troca a senha do usuário logado: confere a atual e grava a nova (hash).
    Levanta InvalidCredentialsError se a senha atual estiver errada.

    Ao trocar, avança password_changed_at (func.now(), avaliado no servidor) — o
    set_password_hash comita a mesma entidade, então a coluna vai junto no UPDATE.
    Isso invalida NA HORA os tokens emitidos antes (claim pcat < novo valor)."""
    if not verify_password(current_password, user.password_hash):
        raise InvalidCredentialsError()
    user.password_changed_at = func.now()
    user_repository.set_password_hash(
        db, user=user, password_hash=hash_password(new_password)
    )


# --- Recuperação de senha --------------------------------------------------


class InvalidResetTokenError(Exception):
    """Token de reset inexistente, expirado ou já usado — a rota traduz em 400."""


def _hash_token(raw_token: str) -> str:
    """SHA-256 hex do token cru — é isto que fica no banco (nunca o cru)."""
    return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


def request_password_reset(db: Session, *, email: str) -> str | None:
    """Emite um token de recuperação para o e-mail, se a conta existir.

    Retorna o TOKEN CRU (para a rota entregar por e-mail) quando há conta ativa;
    None caso contrário. A ROTA responde de forma genérica nos dois casos — quem
    decide não vazar a existência da conta é a rota, não este service.

    Só um token vivo por vez: invalida os pendentes antes de criar o novo, tudo
    no mesmo commit (o create comita)."""
    user = user_repository.get_by_email(db, email)
    if user is None or not user.is_active:
        return None
    raw_token = secrets.token_urlsafe(32)
    expires_at = datetime.now(UTC) + timedelta(
        minutes=settings.PASSWORD_RESET_TOKEN_TTL_MINUTES
    )
    password_reset_repository.invalidate_user_tokens(db, user_id=user.id)
    password_reset_repository.create(
        db, user_id=user.id, token_hash=_hash_token(raw_token), expires_at=expires_at
    )
    return raw_token


def reset_password(db: Session, *, raw_token: str, new_password: str) -> None:
    """Redefine a senha a partir de um token válido (uso único).

    Confere o token pelo hash; se válido, grava a nova senha, marca o token como
    usado e invalida quaisquer outros pendentes do usuário — tudo num commit.
    Levanta InvalidResetTokenError se o token não vale mais."""
    token = password_reset_repository.get_valid_by_hash(
        db, token_hash=_hash_token(raw_token)
    )
    if token is None:
        raise InvalidResetTokenError()
    user = user_repository.get_by_id(db, token.user_id)
    if user is None or not user.is_active:
        # Conta sumiu/desativada entre o pedido e o uso: trata como token morto.
        raise InvalidResetTokenError()
    user.password_hash = hash_password(new_password)
    # Avança password_changed_at (func.now(), no servidor): invalida os tokens
    # emitidos antes do reset (claim pcat < novo valor -> get_current_user recusa).
    user.password_changed_at = func.now()
    # Consome ESTE token e derruba qualquer outro pendente do usuário.
    password_reset_repository.invalidate_user_tokens(db, user_id=user.id)
    db.commit()
