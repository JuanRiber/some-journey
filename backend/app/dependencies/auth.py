"""Dependencies de autenticação do FastAPI.

get_current_user é a "porta" das rotas protegidas: extrai o Bearer token,
valida via core.security, carrega o usuário do banco e bloqueia conta inativa.
Qualquer falha vira 401 genérico ("Could not validate credentials.") — não
revelamos se o token expirou, é inválido, ou se a conta não existe/está
inativa (anti-enumeração).
"""

import uuid

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.security import decode_access_token
from app.db.session import get_db
from app.models.user import User
from app.repositories import user_repository

# auto_error=False: sem header Authorization, credentials vem None e nós mesmos
# levantamos 401 (o default do HTTPBearer seria 403; queremos o 401 do contrato).
_bearer_scheme = HTTPBearer(auto_error=False)

_credentials_exception = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Could not validate credentials.",
    headers={"WWW-Authenticate": "Bearer"},
)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    """Resolve o usuário autenticado a partir do Bearer token, ou 401."""
    if credentials is None:
        raise _credentials_exception

    sub = decode_access_token(credentials.credentials)
    if sub is None:
        raise _credentials_exception

    # O sub é string; o id da tabela é UUID. Não confiamos no formato do token.
    try:
        user_id = uuid.UUID(sub)
    except ValueError:
        raise _credentials_exception

    user = user_repository.get_by_id(db, user_id)
    if user is None or not user.is_active:
        raise _credentials_exception

    return user
