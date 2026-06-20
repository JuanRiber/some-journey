"""Rotas de autenticação: POST /auth/register, POST /auth/login, GET /auth/me.

Camada HTTP fina: recebe a entrada (schemas validam), chama o auth_service e
traduz as exceções de domínio do service em status codes (409/401/403). O
response_model de cada rota garante que a saída segue o contrato — e que
password_hash NUNCA vaza (o ORM até passa por aqui, mas só os campos do schema
são serializados).
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.dependencies.auth import get_current_user
from app.models.user import User
from app.schemas.auth import (
    LoginRequest,
    LoginResponse,
    RegisterRequest,
    RegisterResponse,
    UserResponse,
)
from app.services import auth_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post(
    "/register",
    response_model=RegisterResponse,
    status_code=status.HTTP_201_CREATED,
)
def register(data: RegisterRequest, db: Session = Depends(get_db)) -> User:
    """Cria uma conta. Não retorna JWT — o app volta para a tela de login."""
    try:
        return auth_service.register(db, data)
    except auth_service.EmailAlreadyRegisteredError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered.",
        )


@router.post("/login", response_model=LoginResponse)
def login(data: LoginRequest, db: Session = Depends(get_db)) -> LoginResponse:
    """Autentica e devolve o access token (JWT)."""
    try:
        return auth_service.login(db, data)
    except auth_service.InvalidCredentialsError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password.",
        )
    except auth_service.InactiveUserError:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User account is inactive.",
        )


@router.get("/me", response_model=UserResponse)
def me(current_user: User = Depends(get_current_user)) -> User:
    """Devolve o usuário autenticado a partir do Bearer token."""
    return current_user
