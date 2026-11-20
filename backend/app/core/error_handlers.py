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

E um terceiro, de idioma: as mensagens de validação do Pydantic vêm em inglês
("Field required", "String should have at least 8 characters") e o app mostra
`detail[0].msg` como está. Aqui o `msg` sai em português, com o nome do campo
na frente quando ele tem um nome que se diga para a pessoa; o resto do erro
(`type`, `loc`, `ctx`) fica igual, para quem trata o erro pelo tipo.
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


# O nome de cada campo como a pessoa o conhece na tela. Campo fora daqui fica
# sem prefixo: "occurred_at: data inválida" diria menos que "Data inválida."
_CAMPOS = {
    "email": "E-mail",
    "password": "Senha",
    "new_password": "Nova senha",
    "current_password": "Senha atual",
    "name": "Nome",
    "username": "Nome de usuário",
    "bio": "Bio",
    "title": "Título",
    "text": "Texto",
    "description": "Descrição",
    "mood": "Humor",
    "color": "Cor",
    "latitude": "Latitude",
    "longitude": "Longitude",
    "occurred_at": "Data",
    "memory_date": "Data",
    "started_at": "Início",
    "ended_at": "Fim",
    "token": "Link de redefinição",
}


def _limite(ctx: dict, chave: str) -> object:
    """O limite como se escreve em português: 90, não 90.0; 0,5, não 0.5."""
    valor = ctx.get(chave, "?")
    if isinstance(valor, float):
        return int(valor) if valor.is_integer() else str(valor).replace(".", ",")
    return valor


def _frase(erro: dict) -> str | None:
    """A mensagem em português para um erro do Pydantic, ou None se o tipo não
    tem tradução (aí fica a original — melhor em inglês que vazia)."""
    tipo = erro.get("type", "")
    ctx = erro.get("ctx") or {}
    msg = str(erro.get("msg", ""))
    match tipo:
        case "missing":
            return "é obrigatório."
        case "string_too_short":
            n = _limite(ctx, "min_length")
            return f"precisa ter pelo menos {n} {'caractere' if n == 1 else 'caracteres'}."
        case "string_too_long":
            return f"pode ter no máximo {_limite(ctx, 'max_length')} caracteres."
        case "too_short":
            return f"precisa ter pelo menos {_limite(ctx, 'min_length')} item(ns)."
        case "too_long":
            return f"pode ter no máximo {_limite(ctx, 'max_length')} itens."
        case "greater_than":
            return f"precisa ser maior que {_limite(ctx, 'gt')}."
        case "greater_than_equal":
            return f"precisa ser no mínimo {_limite(ctx, 'ge')}."
        case "less_than":
            return f"precisa ser menor que {_limite(ctx, 'lt')}."
        case "less_than_equal":
            return f"precisa ser no máximo {_limite(ctx, 'le')}."
        case "int_parsing" | "int_type" | "int_from_float":
            return "precisa ser um número inteiro."
        case "float_parsing" | "float_type" | "finite_number":
            return "precisa ser um número."
        case "string_type":
            return "precisa ser um texto."
        case "bool_parsing" | "bool_type":
            return "precisa ser sim ou não."
        case "list_type":
            return "precisa ser uma lista."
        case "dict_type" | "model_type" | "model_attributes_type":
            return "está num formato que não dá para ler."
        case (
            "datetime_parsing"
            | "datetime_type"
            | "datetime_from_date_parsing"
            | "date_parsing"
            | "date_type"
            | "date_from_datetime_parsing"
        ):
            return "não é uma data válida."
        case "timezone_aware":
            return "precisa vir com o fuso horário."
        case "uuid_parsing" | "uuid_type":
            return "não é um identificador válido."
        case "url_parsing" | "url_type" | "url_scheme" | "url_syntax_violation":
            return "não é um endereço válido."
        case "string_pattern_mismatch":
            return "está num formato que não é aceito."
        case "enum" | "literal_error":
            return f"precisa ser um destes: {_limite(ctx, 'expected')}."
        case "extra_forbidden":
            return "não é um campo aceito aqui."
        case "json_invalid":
            return "O corpo do pedido não é um JSON válido."
        case "value_error" if "email address" in msg:
            return "não é um e-mail válido."
        case "value_error" | "assertion_error":
            # A mensagem é NOSSA (um ValueError de um validador, já em
            # português); o Pydantic só põe "Value error, " na frente.
            for prefixo in ("Value error, ", "Assertion failed, "):
                if msg.startswith(prefixo):
                    msg = msg[len(prefixo):]
            return msg[:1].upper() + msg[1:] if msg else None
    return None


def _em_portugues(erro: dict) -> dict:
    frase = _frase(erro)
    if frase is None:
        return erro
    if frase[:1].isupper():
        texto = frase  # já é uma frase inteira (nossa, ou do JSON inválido)
    elif erro.get("type") == "extra_forbidden":
        texto = "O pedido traz um campo que não é aceito aqui."
    else:
        campo = next(
            (p for p in reversed(erro.get("loc") or ()) if isinstance(p, str)), None
        )
        texto = f"{_CAMPOS.get(campo, 'Um dos campos')} {frase}"
    return {**erro, "msg": texto}


async def _validacao(_request: Request, exc: RequestValidationError) -> JSONResponse:
    # O mesmo corpo do handler padrão do FastAPI ({"detail": [...]}) — os
    # clientes leem `detail[0].msg` —, só que serializável sempre e em
    # português.
    erros = [_em_portugues(e) for e in jsonable_encoder(exc.errors())]
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        content={"detail": _finito(erros)},
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
