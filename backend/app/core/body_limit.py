"""Middleware ASGI PURO de limite de tamanho de corpo.

Rejeita requests grandes ANTES de o app materializar o corpo inteiro:
1) checa o header Content-Length e responde 413 na hora se ele já exceder;
2) mesmo sem Content-Length (ou se ele mentir), envolve o receive() e conta os
   bytes dos eventos http.request — ao ultrapassar o teto, aborta com 413.

Evita BaseHTTPMiddleware de propósito (ele bufferiza o corpo). Rotas de upload
recebem um teto maior (o multipart embrulha o arquivo); as demais usam o teto
padrão de JSON.
"""

from starlette.types import ASGIApp, Message, Receive, Scope, Send


class _BodyTooLarge(Exception):
    """Sinaliza corpo acima do teto (contado no receive)."""


class BodySizeLimitMiddleware:
    def __init__(
        self,
        app: ASGIApp,
        *,
        max_body_bytes: int,
        upload_max_body_bytes: int,
        upload_path_suffix: str = "/image",
    ) -> None:
        self.app = app
        self.max_body_bytes = max_body_bytes
        self.upload_max_body_bytes = upload_max_body_bytes
        self.upload_path_suffix = upload_path_suffix

    def _limit_for(self, scope: Scope) -> int:
        # Rotas de upload (POST .../image) têm teto maior por causa do multipart.
        if scope.get("method") == "POST" and scope.get("path", "").endswith(
            self.upload_path_suffix
        ):
            return self.upload_max_body_bytes
        return self.max_body_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        limit = self._limit_for(scope)

        # 1) Content-Length declarado — rejeita antes de tocar no corpo.
        for name, value in scope.get("headers", []):
            if name == b"content-length":
                try:
                    if int(value) > limit:
                        await self._reject(send)
                        return
                except ValueError:
                    pass  # header inválido: cai no contador de bytes abaixo
                break

        # 2) Conta os bytes recebidos (cobre ausência/mentira de Content-Length).
        total = 0

        async def counting_receive() -> Message:
            nonlocal total
            message = await receive()
            if message["type"] == "http.request":
                total += len(message.get("body", b""))
                if total > limit:
                    raise _BodyTooLarge()
            return message

        started = False

        async def guarded_send(message: Message) -> None:
            nonlocal started
            if message["type"] == "http.response.start":
                started = True
            await send(message)

        try:
            await self.app(scope, counting_receive, guarded_send)
        except _BodyTooLarge:
            # Se a resposta ainda não começou, devolve 413 limpo; senão, propaga.
            if started:
                raise
            await self._reject(send)

    async def _reject(self, send: Send) -> None:
        body = b'{"detail":"Request body too large."}'
        await send(
            {
                "type": "http.response.start",
                "status": 413,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"content-length", str(len(body)).encode()),
                ],
            }
        )
        await send({"type": "http.response.body", "body": body})
