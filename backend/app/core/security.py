"""Núcleo de segurança de autenticação: hashing de senha (argon2) e JWT.

Este módulo é o CORAÇÃO da auth. Concentra DUAS responsabilidades de baixo
nível e nada mais: (1) transformar senha pura em hash e conferir senha contra
hash (pwdlib[argon2]); (2) emitir e validar o access token JWT (PyJWT). Aqui
NÃO há rotas, schemas, acesso a banco, dependencies do FastAPI nem MFA — isso
vive nas camadas de cima (auth_service, dependencies/auth.py). São funções de
módulo (não classe), stateless, no mesmo estilo de user_repository.py.

Quem usa:
  - auth_service (register): chama hash_password e passa o resultado ao
    user_repository.create(..., password_hash=...).
  - auth_service (login): chama verify_password e, se OK, create_access_token.
  - dependencies/auth.py (get_current_user): chama decode_access_token e extrai
    o `sub` (o user_id em string).

Segurança (regras inegociáveis):
- NUNCA logar senha, token, hash ou o secret. Este módulo não loga nada.
- O secret SEMPRE vem de settings (app.core.config), jamais hardcoded.
- O algoritmo é FIXADO em jwt.decode (algorithms=[settings.JWT_ALGORITHM]):
  nunca aceitamos "none" nem uma lista aberta -> bloqueia alg confusion.
- O token SEMPRE expira; o exp usa datetime timezone-aware em UTC
  (datetime.now(timezone.utc)), NUNCA datetime.utcnow() (deprecado no 3.12+).
  Além disso o decode EXIGE o claim exp (options require): um token sem
  expiração — que o PyJWT, por padrão, trataria como eterno — é recusado.
- verify_password é timing-safe (o pwdlib/argon2 cuida disso) e devolve só
  bool — quem decide a mensagem genérica de erro é o service (não revelar se
  falhou e-mail ou senha).
"""

import uuid
from datetime import datetime, timedelta, timezone

import jwt
from pwdlib import PasswordHash
from pwdlib.exceptions import UnknownHashError

from app.core.config import settings

# Hasher único do módulo (estado imutável, criado uma vez no import).
# PasswordHash.recommended() usa argon2id (Argon2Hasher) com parâmetros
# recomendados pela lib — não fixamos custo à mão para herdar o default seguro
# e poder evoluir junto com a pwdlib. Reaproveitar a instância evita recriar o
# hasher a cada chamada.
_password_hash = PasswordHash.recommended()


# --- Senha (argon2 via pwdlib) ---------------------------------------------


def hash_password(password: str) -> str:
    """Gera o hash argon2id da senha pura.

    É ESTE retorno que o service entrega ao user_repository.create como
    password_hash (a coluna Text do model User). O hash já embute salt e
    parâmetros (formato PHC, "$argon2id$v=19$...") — nunca guardamos salt à
    parte. Não logamos a senha nem o hash.
    """
    return _password_hash.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    """Confere a senha pura contra o hash armazenado; retorna True/False.

    A comparação é timing-safe (responsabilidade do argon2/pwdlib), o que evita
    vazar informação por tempo de resposta. A ordem dos argumentos casa com a
    API da pwdlib 0.3.0 -> verify(password, hash) (assinatura confirmada na
    versão instalada: verify(password: str | bytes, hash: str | bytes)).

    Retornamos só bool: NÃO revelamos aqui se o que falhou foi a senha ou o
    e-mail — a mensagem genérica de credencial inválida é decidida no
    auth_service (para não dar pistas a quem enumera contas).

    UnknownHashError: se o hash gravado estiver corrompido/em formato
    desconhecido (ex.: linha legada ou adulterada), a pwdlib levanta exceção.
    Tratamos como falha de credencial (return False) em vez de deixar estourar
    um 500 no login — o resultado externo continua sendo "credencial inválida",
    sem revelar o motivo. Não logamos nada (senha e hash são sensíveis).
    """
    try:
        return _password_hash.verify(password, password_hash)
    except UnknownHashError:
        return False


# --- JWT (PyJWT 2.13.0) ----------------------------------------------------


def create_access_token(
    subject: uuid.UUID | str,
    password_changed_at: datetime | None = None,
) -> str:
    """Emite um access token JWT com payload {"sub", "exp"} (+ "pcat" opcional).

    `subject` é o user_id (UUID). Por decisão de design o token carrega o mínimo
    — nada de nome/e-mail (menos PII no token, menos a corrigir se vazar). O sub
    vira STRING via str(subject): no PyJWT 2.x o claim "sub" deve ser string —
    passar um uuid.UUID estoura TypeError no encode (não é JSON-serializável) e
    um sub não-string faria o próprio decode levantar InvalidSubjectError. str()
    resolve para UUID, str ou int.

    exp = agora + ACCESS_TOKEN_EXPIRE_MINUTES, em UTC timezone-aware
    (datetime.now(timezone.utc)); o PyJWT serializa o datetime aware para o
    timestamp NumericDate do JWT. O secret e o algoritmo vêm de settings.
    jwt.encode no 2.x já devolve str.

    `password_changed_at` (OPCIONAL, retrocompatível): quando informado, grava o
    claim "pcat" = epoch (segundos, int) do instante da senha vigente NA EMISSÃO.
    O get_current_user compara esse pcat com o password_changed_at ATUAL do
    usuário e recusa tokens anteriores a uma troca/reset de senha (revogação
    imediata). O parâmetro é opcional de propósito: tokens já em circulação (sem
    pcat) continuam válidos até expirar naturalmente — nada quebra ao adotar o
    claim. Não incluímos pcat quando None (mantém o payload enxuto).
    """
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
    )
    payload: dict[str, object] = {"sub": str(subject), "exp": expire}
    if password_changed_at is not None:
        payload["pcat"] = int(password_changed_at.timestamp())
    return jwt.encode(
        payload,
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM,
    )


def decode_access_token(token: str) -> dict | None:
    """Valida o token e devolve o PAYLOAD (claims) já verificado, ou None.

    Devolve o dict completo de claims (contém no mínimo "sub" e "exp"; pode
    conter "pcat") para que o get_current_user leia tanto o sub quanto o pcat sem
    decodificar o token duas vezes. Antes esta função devolvia só o sub; passou a
    devolver o payload inteiro porque a revogação por troca de senha precisa do
    claim pcat. O único consumidor é o get_current_user (mesma lane).

    Validação feita pelo PyJWT:
      - assinatura (secret de settings);
      - ALGORITMO FIXADO em algorithms=[settings.JWT_ALGORITHM] — uma lista de
        um único algoritmo, jamais "none" nem aberta (corta alg confusion);
      - expiração (exp; ExpiredSignatureError);
      - claims exp E sub OBRIGATÓRIOS via options={"require": ["exp", "sub"]}:
        um token sem exp (que o PyJWT trataria como eterno) ou sem sub (que não
        identificaria ninguém) é recusado com MissingRequiredClaimError.

    Sinalização de invalidez por valor (return None), não por exceção: token
    expirado, sem exp, sem sub, com assinatura errada, malformado ou com
    algoritmo recusado resultam todos em None. Todas essas exceções do PyJWT
    (ExpiredSignatureError, MissingRequiredClaimError, InvalidAlgorithmError,
    InvalidSignatureError, InvalidSubjectError, ...) são subclasses de
    InvalidTokenError, então um único except cobre todos os casos. Quem
    transforma None em 401 é a dependency get_current_user — aqui só dizemos
    "válido (payload)" ou "inválido (None)". Não logamos o token nem a exceção.
    """
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
            options={"require": ["exp", "sub"]},
        )
    except jwt.InvalidTokenError:
        # Cobre expirado, sem exp, sem sub, assinatura inválida, algoritmo
        # recusado ("none" incluso) e token malformado.
        return None
    # require garante "sub" e "exp"; devolvemos o payload inteiro (inclui pcat
    # quando presente) para o get_current_user avaliar a revogação.
    return payload
