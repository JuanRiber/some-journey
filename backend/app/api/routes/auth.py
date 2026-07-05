from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.rate_limit import check_rate_limit
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


def _client_ip(request: Request) -> str:
    # Usa o peer direto (request.client.host). NÃO lemos X-Forwarded-For aqui:
    # confiar nele sem validação deixaria forjar o IP e furar o rate limit. Em
    # produção atrás de proxy, suba o uvicorn com --proxy-headers e
    # --forwarded-allow-ips=<ip do proxy> para que request.client venha do XFF
    # SOMENTE do proxy confiável.
    return request.client.host if request.client else "unknown"


def _limit_auth(request: Request, scope: str, email: str) -> None:
    """Duas camadas: por CONTA (IP+email) contra brute-force numa conta, e por
    IP (independe do email) contra password spraying. Ambas são checadas sempre
    (as duas contam a tentativa); 429 se qualquer uma estourar."""
    ip = _client_ip(request)
    ok_account, retry_account = check_rate_limit(
        scope,
        [ip, email.lower().strip()],
        max_attempts=settings.AUTH_RATE_LIMIT_ATTEMPTS,
        window_seconds=settings.AUTH_RATE_LIMIT_WINDOW_SECONDS,
    )
    ok_ip, retry_ip = check_rate_limit(
        f"{scope}:ip",
        [ip],
        max_attempts=settings.AUTH_RATE_LIMIT_IP_ATTEMPTS,
        window_seconds=settings.AUTH_RATE_LIMIT_WINDOW_SECONDS,
    )
    if ok_account and ok_ip:
        return
    retry_after = max(0 if ok_account else retry_account, 0 if ok_ip else retry_ip)
    raise HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail="Too many attempts. Try again later.",
        headers={"Retry-After": str(max(1, retry_after))},
    )


@router.post(
    "/register",
    response_model=RegisterResponse,
    status_code=status.HTTP_201_CREATED,
)
def register(
    data: RegisterRequest,
    request: Request,
    db: Session = Depends(get_db),
) -> User:
    # Cadastro fechado (produção): contas são criadas via scripts/seed_users.
    if not settings.registration_open:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Registration is closed.",
        )
    _limit_auth(request, "register", data.email)
    try:
        return auth_service.register(db, data)
    except auth_service.EmailAlreadyRegisteredError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered.",
        )


@router.post("/login", response_model=LoginResponse)
def login(
    data: LoginRequest,
    request: Request,
    db: Session = Depends(get_db),
) -> LoginResponse:
    _limit_auth(request, "login", data.email)
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
    return current_user
