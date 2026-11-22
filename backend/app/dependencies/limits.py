"""Teto de uso por pessoa nas rotas que GRAVAM.

O limite de tentativas cobria só a porta de entrada (login, recuperação de
senha). Quem já estava dentro podia gravar sem teto nenhum: um laço — por
defeito num cliente, ou de propósito — criaria memórias ou subiria fotos até
encher os 500 MB do banco e o 1 GB do Storage do plano grátis, e o serviço
pararia para todo mundo.

Dois baldes por pessoa, na mesma janela, contados no banco pelo limitador que
já existe (app/core/rate_limit.py):

- **escritas** (POST, PATCH, PUT, DELETE nas rotas de conteúdo): folgado. Uma
  gravação de percurso sobe um lote a cada vinte e poucos segundos; salvar uma
  memória com cinco fotos são seis pedidos. O teto fica muito acima disso.
- **uploads** (foto, capa, avatar): mais apertado, porque cada um custa
  megabytes de Storage e de banda.

Leitura nunca é contada. A chave é o id de quem está logado — não o IP: aqui a
pessoa já se identificou, e várias atrás do mesmo roteador não podem gastar o
teto umas das outras.

Custa uma ida ao banco por escrita (um `INSERT ... ON CONFLICT`), na mesma
região: da ordem de um milissegundo.
"""

from fastapi import Depends, HTTPException, Request, status

from app.core.config import settings
from app.core.rate_limit import check_rate_limit
from app.dependencies.auth import get_current_user
from app.models.user import User

_SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})


def _enforce(scope: str, user: User, max_attempts: int) -> None:
    ok, retry = check_rate_limit(
        scope,
        [str(user.id)],
        max_attempts=max_attempts,
        window_seconds=settings.USAGE_RATE_LIMIT_WINDOW_SECONDS,
    )
    if ok:
        return
    raise HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail="Muitas alterações em pouco tempo. Espere um pouco e tente de novo.",
        headers={"Retry-After": str(max(1, retry))},
    )


def limit_writes(
    request: Request, current_user: User = Depends(get_current_user)
) -> None:
    """Dependência de ROUTER: conta cada escrita de quem está logado.

    Vai no `APIRouter(dependencies=[...])`, então cobre toda rota do router sem
    que cada uma precise lembrar — inclusive as que nascerem depois. O
    `get_current_user` é o mesmo da rota: o FastAPI resolve uma vez por pedido.
    """
    if request.method in _SAFE_METHODS:
        return
    _enforce("write", current_user, settings.WRITE_RATE_LIMIT_ATTEMPTS)


def limit_uploads(current_user: User = Depends(get_current_user)) -> None:
    """Dependência das rotas de upload: o balde próprio, mais apertado."""
    _enforce("upload", current_user, settings.UPLOAD_RATE_LIMIT_ATTEMPTS)
