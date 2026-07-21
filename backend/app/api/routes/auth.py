from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.core import email as email_delivery
from app.core.config import settings
from app.core.rate_limit import check_rate_limit
from app.db.session import get_db
from app.dependencies.auth import get_current_user
from app.models.user import User
from app.schemas.auth import (
    ChangePasswordRequest,
    ForgotPasswordRequest,
    LoginRequest,
    LoginResponse,
    RegisterRequest,
    RegisterResponse,
    ResetPasswordRequest,
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


def _limit_change_password(request: Request, user_id: object) -> None:
    """Throttle da troca de senha por (usuário autenticado + IP). Diferente do
    login, aqui a identidade vem do TOKEN (não do corpo), então a chave é o
    user_id + IP: trava o brute-force da senha ATUAL de quem já porta um token
    válido, sem deixar um usuário legítimo estourar o limite de outro. Reusa o
    mesmo balde/tetos do por-conta do _limit_auth."""
    ok, retry = check_rate_limit(
        "change-password",
        [str(user_id), _client_ip(request)],
        max_attempts=settings.AUTH_RATE_LIMIT_ATTEMPTS,
        window_seconds=settings.AUTH_RATE_LIMIT_WINDOW_SECONDS,
    )
    if ok:
        return
    raise HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail="Too many attempts. Try again later.",
        headers={"Retry-After": str(max(1, retry))},
    )


def _limit_auth_ip(request: Request, scope: str) -> None:
    """Limite por IP para endpoints sem e-mail no corpo (ex.: reset-password).
    Trava tentativa em massa de adivinhar tokens de um mesmo IP."""
    ok, retry = check_rate_limit(
        f"{scope}:ip",
        [_client_ip(request)],
        max_attempts=settings.AUTH_RATE_LIMIT_IP_ATTEMPTS,
        window_seconds=settings.AUTH_RATE_LIMIT_WINDOW_SECONDS,
    )
    if ok:
        return
    raise HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail="Too many attempts. Try again later.",
        headers={"Retry-After": str(max(1, retry))},
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


@router.post("/forgot-password", status_code=status.HTTP_202_ACCEPTED)
def forgot_password(
    data: ForgotPasswordRequest,
    request: Request,
    background: BackgroundTasks,
    db: Session = Depends(get_db),
) -> dict[str, str]:
    """Inicia a recuperação de senha. SEMPRE responde 202 com a MESMA mensagem
    genérica — exista a conta ou não (anti-enumeração). Quando existe, um token
    de uso único é gerado e o link é enviado por e-mail em segundo plano (não
    soma latência ao request nem cria oráculo de timing)."""
    _limit_auth(request, "forgot", data.email)
    raw_token = auth_service.request_password_reset(db, email=data.email)
    if raw_token is not None:
        background.add_task(
            email_delivery.send_password_reset, data.email, raw_token
        )
    return {
        "detail": "If an account exists for that email, a reset link has been sent."
    }


@router.post("/reset-password", status_code=status.HTTP_204_NO_CONTENT)
def reset_password(
    data: ResetPasswordRequest,
    request: Request,
    db: Session = Depends(get_db),
) -> None:
    """Conclui a recuperação: valida o token (uso único, com validade) e grava a
    nova senha. Token inválido/expirado/usado -> 400 genérico."""
    _limit_auth_ip(request, "reset")
    try:
        auth_service.reset_password(
            db, raw_token=data.token, new_password=data.new_password
        )
    except auth_service.InvalidResetTokenError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired reset token.",
        )


@router.get("/me", response_model=UserResponse)
def me(current_user: User = Depends(get_current_user)) -> User:
    return current_user


@router.post("/change-password", status_code=status.HTTP_204_NO_CONTENT)
def change_password(
    data: ChangePasswordRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    """Usuário logado troca a própria senha (confere a atual)."""
    _limit_change_password(request, current_user.id)
    try:
        auth_service.change_password(
            db,
            user=current_user,
            current_password=data.current_password,
            new_password=data.new_password,
        )
    except auth_service.InvalidCredentialsError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password is incorrect.",
        )
