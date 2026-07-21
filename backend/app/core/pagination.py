"""Paginação por keyset (cursor) — contrato ÚNICO e compartilhado das listagens.

Por que keyset e não offset: páginas profundas continuam O(limit) e não pulam
nem duplicam linhas quando algo é inserido/removido entre requisições — desde
que a ordenação tenha um desempate único (o id). Cada listagem ordena por
(timestamp, id) e o cursor carrega exatamente esse par.

CONTRATO HTTP (idêntico em todas as rotas de lista, para os clientes e o Design
System dependerem de UMA forma só):
- A resposta continua sendo um ARRAY JSON puro (retrocompatível com os clientes
  atuais, que iteram a lista direto).
- Query params: `?limit` (default DEFAULT_LIMIT, teto MAX_LIMIT) e `?cursor`
  (opaco; o do fim da página anterior).
- Quando há próxima página, a rota devolve o cursor no HEADER `X-Next-Cursor`
  (e expõe esse header no CORS). Sem o header => acabou.

O cursor é opaco para o cliente: base64url de "<iso8601>|<uuid>". Inválido =>
CursorError (a rota traduz em 400), nunca 500.
"""

import base64
import uuid
from datetime import datetime

DEFAULT_LIMIT = 30
MAX_LIMIT = 100
NEXT_CURSOR_HEADER = "X-Next-Cursor"


class CursorError(ValueError):
    """Cursor malformado — a rota traduz em 400 Bad Request."""


def clamp_limit(limit: int | None) -> int:
    """Normaliza o limite pedido para [1, MAX_LIMIT], com default se ausente."""
    if limit is None:
        return DEFAULT_LIMIT
    if limit < 1:
        return 1
    return min(limit, MAX_LIMIT)


def encode_cursor(moment: datetime, row_id: uuid.UUID) -> str:
    """(timestamp, id) -> cursor opaco (base64url)."""
    raw = f"{moment.isoformat()}|{row_id}"
    return base64.urlsafe_b64encode(raw.encode("utf-8")).decode("ascii")


def decode_cursor(cursor: str) -> tuple[datetime, uuid.UUID]:
    """cursor opaco -> (timestamp, id). Levanta CursorError se inválido."""
    try:
        raw = base64.urlsafe_b64decode(cursor.encode("ascii")).decode("utf-8")
        iso, id_str = raw.rsplit("|", 1)
        return datetime.fromisoformat(iso), uuid.UUID(id_str)
    except (ValueError, TypeError) as exc:
        raise CursorError("Invalid pagination cursor.") from exc
