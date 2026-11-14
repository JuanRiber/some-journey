"""Tipos de campo compartilhados pelos schemas (contratos Pydantic v2).

AwareUtcDatetime: todo datetime de ENTRADA vira UTC timezone-aware antes de
persistir. As colunas são TIMESTAMPTZ e os defaults do serviço usam
datetime.now(UTC) (aware) — sem esta normalização, um cliente que enviasse um
horário NAIVE (sem offset) teria o instante reinterpretado no fuso da sessão do
Postgres, corrompendo ordenação e cálculos temporais. Usa AfterValidator: roda
DEPOIS de o Pydantic converter string/número em datetime, então recebe sempre um
datetime — naive vira UTC (assume-se UTC), aware é convertido para UTC.

E LIMITA o ano. Sem limite, uma memória datada do ano 1 era aceita, gravada — e
depois não voltava: lida no fuso da sessão do banco, caía antes do ano 1, que o
Python não representa. A criação respondia 500 com a memória já gravada, e daí
em diante a timeline e o mapa da dona davam 500 para sempre, sem nem o id para
ela apagar a memória pelo app. Datas no limite oposto quebram igual em fusos
positivos. Mil a 2999 cobre qualquer vida, com folga para os dois lados.
"""

from datetime import datetime, timedelta, timezone
from typing import Annotated

from pydantic import AfterValidator

ANO_MINIMO = 1000
ANO_MAXIMO = 2999


def _no_intervalo(value: datetime) -> None:
    if not ANO_MINIMO <= value.year <= ANO_MAXIMO:
        raise ValueError(
            f"a data precisa estar entre os anos {ANO_MINIMO} e {ANO_MAXIMO}"
        )


def _ensure_utc(value: datetime) -> datetime:
    # Confere ANTES de converter: perto do ano 1, a conversão de fuso estoura
    # com OverflowError, que o Pydantic não transforma em 422.
    _no_intervalo(value)
    if value.tzinfo is None:
        utc = value.replace(tzinfo=timezone.utc)
    else:
        utc = value.astimezone(timezone.utc)
    # E depois: um fuso de +14h leva 1000-01-01 para o ano 999.
    _no_intervalo(utc)
    return utc


AwareUtcDatetime = Annotated[datetime, AfterValidator(_ensure_utc)]


# Folga para o fuso, não para o futuro. O app manda o DIA escolhido ancorado ao
# meio-dia UTC; "hoje" em UTC+14 chega a ficar 26 h à frente do relógio do
# servidor. 36 h cobre qualquer fuso da Terra e ainda recusa amanhã.
TOLERANCIA_FUTURO = timedelta(hours=36)


def _ja_aconteceu(value: datetime) -> datetime:
    if value > datetime.now(timezone.utc) + TOLERANCIA_FUTURO:
        raise ValueError("a memória não pode ser de um dia que ainda não chegou")
    return value


# A data de uma MEMÓRIA: tudo o que AwareUtcDatetime garante, mais a regra de
# negócio de que uma lembrança é de algo que já aconteceu. O seletor do app já
# não deixa escolher amanhã; sem isto o backend aceitava de qualquer outro
# cliente, e a timeline abriria com um capítulo do ano que vem.
# Jornadas, fases e pontos de GPS NÃO usam: uma viagem pode estar planejada, uma
# fase pode ter fim marcado, e o relógio de um celular adiantado não pode custar
# o rastro inteiro de um trecho.
OccurredAt = Annotated[AwareUtcDatetime, AfterValidator(_ja_aconteceu)]
