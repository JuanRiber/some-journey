"""Tipos de campo compartilhados pelos schemas (contratos Pydantic v2).

AwareUtcDatetime: todo datetime de ENTRADA vira UTC timezone-aware antes de
persistir. As colunas são TIMESTAMPTZ e os defaults do serviço usam
datetime.now(UTC) (aware) — sem esta normalização, um cliente que enviasse um
horário NAIVE (sem offset) teria o instante reinterpretado no fuso da sessão do
Postgres, corrompendo ordenação e cálculos temporais. Usa AfterValidator: roda
DEPOIS de o Pydantic converter string/número em datetime, então recebe sempre um
datetime — naive vira UTC (assume-se UTC), aware é convertido para UTC.
"""

from datetime import datetime, timezone
from typing import Annotated

from pydantic import AfterValidator


def _ensure_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


AwareUtcDatetime = Annotated[datetime, AfterValidator(_ensure_utc)]
