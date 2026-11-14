from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.core import email as email_delivery
from app.core import google_oauth
from app.core.config import settings
from app.core.rate_limit import check_rate_limit
from app.db.session import get_db
from app.dependencies.auth import get_current_user
from app.models.user import User
from app.schemas.auth import (
    GoogleLoginRequest,
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
    # O peer que o uvicorn entrega. Em produção ele sobe com --proxy-headers e
    # --forwarded-allow-ips='*' (scripts/start.sh), e com '*' o uvicorn devolve
    # a entrada MAIS À ESQUERDA do X-Forwarded-For — que é o que o cliente
    # quiser escrever, se o proxy da plataforma acrescenta em vez de
    # sobrescrever. Por isso nenhum limite que importa depende só daqui: o
    # balde por E-MAIL (em _limit_auth) não lê IP nenhum.
    return request.client.host if request.client else "unknown"


def _limit_auth(
    request: Request, scope: str, email: str, *, per_email: bool = True
) -> None:
    """Três camadas, todas checadas sempre (cada uma conta a tentativa); 429 se
    qualquer uma estourar:

    - por CONTA neste IP (IP+email): brute-force numa conta, apertado;
    - por IP (independe do email): password spraying;
    - por E-MAIL, de qualquer IP: o teto que um X-Forwarded-For forjado não
      fura. Sem ele, quem troca o IP a cada tentativa cai sempre num balde
      novo nas duas camadas acima e adivinha a senha de uma conta sem limite —
      ou enche de e-mails de recuperação a caixa de alguém. É mais folgado que
      o por-conta porque trava a conta para todo mundo, inclusive para a dona.

    `per_email=False` só para quem não tem e-mail na chave (o login do Google
    usa o começo do token, que é igual para todo token do mesmo emissor — um
    balde "por e-mail" ali seria um teto GLOBAL de logins pelo Google).
    """
    ip = _client_ip(request)
    conta = email.lower().strip()
    ok_account, retry_account = check_rate_limit(
        scope,
        [ip, conta],
        max_attempts=settings.AUTH_RATE_LIMIT_ATTEMPTS,
        window_seconds=settings.AUTH_RATE_LIMIT_WINDOW_SECONDS,
    )
    ok_ip, retry_ip = check_rate_limit(
        f"{scope}:ip",
        [ip],
        max_attempts=settings.AUTH_RATE_LIMIT_IP_ATTEMPTS,
        window_seconds=settings.AUTH_RATE_LIMIT_WINDOW_SECONDS,
    )
    ok_email, retry_email = (True, 0)
    if per_email:
        ok_email, retry_email = check_rate_limit(
            f"{scope}:email",
            [conta],
            max_attempts=settings.AUTH_RATE_LIMIT_EMAIL_ATTEMPTS,
            window_seconds=settings.AUTH_RATE_LIMIT_WINDOW_SECONDS,
        )
    if ok_account and ok_ip and ok_email:
        return
    retry_after = max(
        0 if ok_account else retry_account,
        0 if ok_ip else retry_ip,
        0 if ok_email else retry_email,
    )
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


@router.post("/google", response_model=LoginResponse)
def login_with_google(
    data: GoogleLoginRequest,
    request: Request,
    db: Session = Depends(get_db),
) -> LoginResponse:
    """Entra com o Google. Cria a conta na primeira vez, vincula se o e-mail
    já existir, e nunca cria uma segunda.

    Os status: **503** quando o GOOGLE_CLIENT_ID não está configurado (o
    recurso não existe neste ambiente — melhor dizer isso do que aceitar um
    token sem saber para quem foi emitido), **401** para token inválido,
    expirado, de outro cliente ou com e-mail não verificado, e **403** para
    conta inativa, igual ao login por senha.

    O limitador usa o próprio token como chave de balde: sem e-mail no corpo,
    é o que identifica a tentativa antes de sabermos quem é. Sem o balde por
    e-mail: o começo do token é o cabeçalho do JWT, igual para todo token do
    Google, e ali ele viraria um teto global.

    **409** quando o e-mail já está ligado a OUTRA conta Google (outro `sub`).
    """
    _limit_auth(request, "google", data.id_token[:64], per_email=False)
    try:
        return auth_service.login_with_google(db, data.id_token)
    except google_oauth.GoogleNotConfigured:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Google sign-in is not configured.",
        )
    except google_oauth.InvalidGoogleToken:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Google token.",
        )
    except auth_service.InactiveUserError:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account is inactive.",
        )
    except auth_service.GoogleAccountConflictError:
        # Quem pede provou controlar o e-mail (o token veio verificado), então
        # dizer que ele já tem dono no Google não vaza nada a um estranho.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "Este e-mail já está ligado a outra conta Google. Entre com "
                "e-mail e senha — ou use \"Esqueci minha senha\" para criar uma."
            ),
        )


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
    except auth_service.PasswordNotSetError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "Esta conta entra pelo Google e ainda não tem senha. Para criar "
                "uma, use \"Esqueci minha senha\" na tela de entrada."
            ),
        )
