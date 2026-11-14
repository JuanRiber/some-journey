"""Cabeçalhos de segurança em toda resposta — middleware ASGI puro.

Esta API só fala JSON, e cada cabeçalho fecha uma porta que ela não usa:

- `X-Content-Type-Options: nosniff` — o navegador não "adivinha" que um JSON é
  HTML ou script.
- `X-Frame-Options: DENY` e `frame-ancestors 'none'` — nenhuma página põe a
  API num iframe.
- `Referrer-Policy: no-referrer` — um link que saia daqui não carrega a URL,
  que pode ter id de memória.
- `Content-Security-Policy: default-src 'none'` — uma resposta desta API não
  tem por que carregar nada. Só em produção: fora dela o /docs carrega o
  Swagger de uma CDN, e a política o deixaria em branco.
- `Strict-Transport-Security` — só em produção, onde a borda serve HTTPS; em
  localhost ele prenderia o navegador num HTTPS que não existe.

`setdefault`: se alguma rota um dia definir o próprio valor, ele vence.
"""

from starlette.datastructures import MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send


class SecurityHeadersMiddleware:
    def __init__(self, app: ASGIApp, *, production: bool) -> None:
        self.app = app
        self.production = production

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def com_cabecalhos(message: Message) -> None:
            if message["type"] == "http.response.start":
                h = MutableHeaders(scope=message)
                h.setdefault("X-Content-Type-Options", "nosniff")
                h.setdefault("X-Frame-Options", "DENY")
                h.setdefault("Referrer-Policy", "no-referrer")
                if self.production:
                    h.setdefault(
                        "Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'"
                    )
                    h.setdefault(
                        "Strict-Transport-Security", "max-age=31536000; includeSubDomains"
                    )
            await send(message)

        await self.app(scope, receive, com_cabecalhos)
