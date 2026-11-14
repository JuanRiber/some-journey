"""Respostas de erro que o FastAPI, sozinho, transforma em 500.

Dois casos, os dois achados num ataque simulado — e nos dois a culpa é do que
o cliente mandou, então a resposta certa é 422, não "o servidor quebrou":

- **Número que não é número.** O parser JSON do Python aceita `NaN`,
  `Infinity` e `1e400`. A validação recusa a latitude — e o erro 422 repete o
  valor recebido, que não cabe em JSON: a resposta de erro quebrava com
  ValueError e saía 500. Aqui o valor é devolvido como texto.
- **Valor que o banco não guarda.** O Postgres recusa o caractere NUL (0x00)
  em texto, e nenhum schema o barra antes: o INSERT levantava DataError. A
  transação é desfeita pelo `get_db` ao fechar a sessão; aqui só a resposta.
"""

import logging
import math

from fastapi import FastAPI, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import DataError

logger = logging.getLogger("app.errors")


def _finito(valor: object) -> object:
    """O mesmo valor, com todo float não finito trocado pelo texto dele."""
    if isinstance(valor, float) and not math.isfinite(valor):
        return str(valor)
    if isinstance(valor, dict):
        return {chave: _finito(item) for chave, item in valor.items()}
    if isinstance(valor, list | tuple):
        return [_finito(item) for item in valor]
    return valor


async def _validacao(_request: Request, exc: RequestValidationError) -> JSONResponse:
    # O mesmo corpo do handler padrão do FastAPI ({"detail": [...]}) — os
    # clientes leem `detail[0].msg` —, só que serializável sempre.
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        content={"detail": _finito(jsonable_encoder(exc.errors()))},
    )


async def _dado_recusado(_request: Request, exc: DataError) -> JSONResponse:
    # Loga o tipo do erro do driver, nunca o valor: ele veio do cliente e pode
    # ser qualquer coisa, inclusive dado pessoal.
    logger.warning("Banco recusou um valor: %s", type(exc.orig).__name__)
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        content={
            "detail": (
                "Algum valor enviado não pode ser guardado — por exemplo, um "
                "caractere de controle invisível no texto."
            )
        },
    )


def register_error_handlers(application: FastAPI) -> None:
    application.add_exception_handler(RequestValidationError, _validacao)
    application.add_exception_handler(DataError, _dado_recusado)
