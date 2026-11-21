"""Serviço de autenticação: orquestra as regras de negócio de cadastro e login.

Junta as camadas de baixo — repository (dados), security (hash/JWT) e schemas
(contratos) — e decide o "quê" (as regras), delegando o "como". NÃO conhece
HTTP: sinaliza falhas com exceções de domínio que a camada de rotas (9.9)
traduz em status (409/401/403). Assim o service é testável sem FastAPI, e a
mensagem genérica de credencial inválida nasce aqui (anti-enumeração).
"""

import hashlib
import secrets
import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import google_oauth
from app.core.config import settings
from app.core.security import create_access_token, hash_password, verify_password
from app.models.user import User
from app.repositories import (
    password_reset_repository,
    refresh_token_repository,
    user_repository,
)
from app.services import purge_service
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


class GoogleAccountConflictError(Exception):
    """O e-mail já tem conta ligada a OUTRA conta Google — a rota traduz em 409."""


class PasswordNotSetError(Exception):
    """Conta que só entra pelo Google: não há senha atual para conferir — 409."""


class InactiveUserError(Exception):
    """Conta inativa — a rota traduz para 403 Forbidden."""


class InvalidRefreshTokenError(Exception):
    """Refresh token inexistente, vencido, revogado ou reusado — 401."""


# Um refresh token já trocado ainda é aceito por este tempo, e só para gerar
# OUTRO sucessor na mesma sessão. Cobre os dois casos honestos de reuso: duas
# abas do navegador renovando ao mesmo tempo com o mesmo token guardado, e a
# resposta da renovação que se perdeu no caminho (o servidor trocou, o app não
# soube e tenta de novo). Fora desta folga, token trocado que reaparece é cópia.
_REFRESH_REUSE_GRACE = timedelta(seconds=20)


def _hash_token(raw_token: str) -> str:
    """SHA-256 hex do token cru — é isto que fica no banco (nunca o cru)."""
    return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


def _issue_session(
    db: Session, user: User, *, family_id: uuid.UUID | None = None
) -> LoginResponse:
    """Emite o par da sessão: access token (JWT) + refresh token (opaco).

    Sem `family_id` é um login — nasce uma sessão nova. Com ele é uma
    renovação: o refresh token novo entra na MESMA família do que foi trocado.
    Quem chama já conferiu a credencial (senha, Google ou refresh token) e que
    a conta está ativa. Comita: o par só existe se o refresh token foi gravado.
    """
    raw_refresh = secrets.token_urlsafe(48)
    refresh_token_repository.purge_stale_for_user(db, user_id=user.id)
    refresh_token_repository.create(
        db,
        user_id=user.id,
        family_id=family_id or uuid.uuid4(),
        token_hash=_hash_token(raw_refresh),
        expires_at=datetime.now(UTC)
        + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
    )
    db.commit()
    # pcat = password_changed_at vigente: o token só vale enquanto a senha não
    # for trocada/redefinida (ver get_current_user).
    return LoginResponse(
        access_token=create_access_token(user.id, user.password_changed_at),
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        refresh_token=raw_refresh,
    )


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
    if user.password_hash is None:
        # Conta que só tem Google: não há senha para conferir. Roda o argon2
        # contra o hash dummy e devolve a MESMA mensagem genérica — dizer
        # "esta conta usa Google" revelaria que o e-mail existe, que é
        # exatamente o que o resto deste fluxo evita.
        verify_password(data.password, _DUMMY_PASSWORD_HASH)
        raise InvalidCredentialsError()
    if not verify_password(data.password, user.password_hash):
        raise InvalidCredentialsError()
    if not user.is_active:
        raise InactiveUserError()
    return _issue_session(db, user)


def login_with_google(db: Session, id_token: str) -> LoginResponse:
    """Entra (ou cadastra) pelo Google e emite NOSSO token.

    Três caminhos, nesta ordem, e a ordem é a regra:

    1. **Já conhecemos este `sub`** — é a mesma conta Google de antes; entra.
    2. **Não, mas o e-mail já tem cadastro** — VINCULA em vez de criar. É isto
       que impede a segunda conta: quem usava e-mail e senha e um dia toca em
       "entrar com Google" cai no próprio cadastro, com as próprias memórias,
       e não num perfil vazio de mesmo nome.
    3. **Nenhum dos dois** — cria, sem senha (`password_hash=None`).

    O vínculo é pelo `sub`, nunca pelo e-mail, porque o e-mail de uma conta
    Google pode mudar; e o e-mail só serve de ponte no passo 2 porque o
    verificador já exigiu `email_verified`.

    A corrida entre dois logins simultâneos do mesmo Google novo é resolvida
    pelo banco: `google_sub` e `email` são UNIQUE, o INSERT perdedor levanta
    IntegrityError, e aqui relemos a linha que o vencedor gravou em vez de
    devolver erro para alguém que apenas tocou no botão duas vezes.
    """
    identidade = google_oauth.verify(id_token)

    user = user_repository.get_by_google_sub(db, identidade.sub)
    if user is None:
        existente = user_repository.get_by_email(db, identidade.email)
        if existente is not None and existente.google_sub is not None:
            # O e-mail já está ligado a OUTRO `sub` (o passo 1 teria achado o
            # mesmo). É o caso que o vínculo pelo `sub` existe para barrar: um
            # e-mail de domínio que trocou de dono. Sobrescrever entregaria as
            # memórias da pessoa anterior a quem herdou o endereço.
            raise GoogleAccountConflictError()
        if existente is not None:
            user = user_repository.link_google(
                db, user=existente, google_sub=identidade.sub
            )
        else:
            try:
                user = user_repository.create(
                    db,
                    name=identidade.name or identidade.email.split("@")[0],
                    email=identidade.email,
                    password_hash=None,
                    google_sub=identidade.sub,
                )
            except IntegrityError:
                user = user_repository.get_by_google_sub(db, identidade.sub)
                if user is None:
                    raise

    if not user.is_active:
        raise InactiveUserError()
    return _issue_session(db, user)


def refresh_session(db: Session, *, raw_token: str) -> LoginResponse:
    """Troca um refresh token por um par novo (rotação).

    O token vale UMA troca. Os caminhos, na ordem em que são decididos:

    - **não existe, foi revogado ou venceu** — a sessão acabou;
    - **é o vigente** — é consumido e nasce o sucessor, na mesma família;
    - **já foi trocado, há instantes** — a folga (`_REFRESH_REUSE_GRACE`): outro
      sucessor na mesma família, sem derrubar ninguém;
    - **já foi trocado, e não foi agora** — é cópia. A família inteira é
      revogada: quem copiou perde o acesso, e a dona volta ao login — que é o
      aviso que ela pode receber.

    Tudo o que falha levanta a MESMA exceção: a rota responde um 401 só, sem
    dizer qual dos motivos foi.
    """
    token = refresh_token_repository.get_by_hash(
        db, token_hash=_hash_token(raw_token)
    )
    agora = datetime.now(UTC)
    if token is None or token.revoked_at is not None or token.expires_at <= agora:
        raise InvalidRefreshTokenError()

    user = user_repository.get_by_id(db, token.user_id)
    if user is None or not user.is_active:
        raise InvalidRefreshTokenError()

    consumiu = token.used_at is None and refresh_token_repository.mark_used(
        db, token_id=token.id
    )
    if not consumiu:
        # Já estava trocado — ou outra requisição o trocou entre a leitura e o
        # UPDATE. Relê para decidir com o instante que o banco gravou.
        db.refresh(token)
        usado_em = token.used_at
        if (
            token.revoked_at is not None
            or usado_em is None
            or agora - usado_em > _REFRESH_REUSE_GRACE
        ):
            refresh_token_repository.revoke_family(db, family_id=token.family_id)
            db.commit()
            raise InvalidRefreshTokenError()

    return _issue_session(db, user, family_id=token.family_id)


def logout(db: Session, *, raw_token: str) -> None:
    """Encerra a sessão do refresh token dado. Idempotente e silencioso: token
    desconhecido, vencido ou já revogado não é erro — quem está saindo quer
    sair, e a resposta não deve servir para testar se um token existe."""
    token = refresh_token_repository.get_by_hash(
        db, token_hash=_hash_token(raw_token)
    )
    if token is None:
        return
    refresh_token_repository.revoke_family(db, family_id=token.family_id)
    db.commit()


def change_password(
    db: Session, *, user: User, current_password: str, new_password: str
) -> None:
    """Troca a senha do usuário logado: confere a atual e grava a nova (hash).
    Levanta InvalidCredentialsError se a senha atual estiver errada.

    Quem avança password_changed_at é o set_password_hash, no mesmo UPDATE do
    hash — é lá que a regra vive, para nenhum chamador poder esquecê-la. Isso
    invalida NA HORA os tokens emitidos antes (claim pcat < novo valor).

    Conta que só entra pelo Google não tem senha atual para conferir: levanta
    PasswordNotSetError em vez de passar None ao verificador, que quebraria
    com TypeError (500).

    As sessões abertas caem junto: os refresh tokens da pessoa são revogados na
    MESMA transação do hash novo (o set_password_hash é quem comita). Sem isso
    o access token antigo morria e o refresh antigo emitia outro."""
    if user.password_hash is None:
        raise PasswordNotSetError()
    if not verify_password(current_password, user.password_hash):
        raise InvalidCredentialsError()
    refresh_token_repository.revoke_all_for_user(db, user_id=user.id)
    user_repository.set_password_hash(
        db, user=user, password_hash=hash_password(new_password)
    )


# --- Excluir conta ---------------------------------------------------------


class AccountConfirmationError(Exception):
    """O e-mail digitado não é o da conta — a rota traduz em 400."""


def delete_account(
    db: Session, *, user: User, email: str, password: str | None
) -> None:
    """Exclui a conta de quem pede, depois de conferir que é a própria pessoa.

    Duas travas, nesta ordem:

    1. **O e-mail digitado é o da conta.** Não é segredo — é a confirmação de
       que a pessoa sabe o que está apagando, e de qual conta.
    2. **A senha atual**, quando a conta tem uma. É o que impede um token de
       sessão copiado de apagar tudo. Conta que só entra pelo Google não tem
       senha: para ela vale a primeira trava e a sessão.

    Passou, não tem volta: quem apaga é o purge_service.delete_account.
    """
    if email != user.email:
        raise AccountConfirmationError()
    if user.password_hash is not None and not (
        password and verify_password(password, user.password_hash)
    ):
        raise InvalidCredentialsError()
    purge_service.delete_account(db, user=user)


# --- Recuperação de senha --------------------------------------------------


class InvalidResetTokenError(Exception):
    """Token de reset inexistente, expirado ou já usado — a rota traduz em 400."""


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
    # E encerra as sessões abertas: quem redefine a senha porque perdeu o
    # controle da conta não pode deixar um refresh token vivo com outra pessoa.
    refresh_token_repository.revoke_all_for_user(db, user_id=user.id)
    db.commit()
