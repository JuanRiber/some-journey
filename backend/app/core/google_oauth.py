"""Verificação do `id_token` do Google — o único ponto que confia no Google.

O cliente (app ou web) faz o fluxo do Google, recebe um `id_token` e manda
PARA CÁ. Nada do que ele diz sobre si é aceito: o token é um JWT assinado pelo
Google, e é a assinatura que vale. O cliente poderia mandar qualquer e-mail;
só a chave pública do Google decide quem ele é.

PORQUÊ PyJWT e não `google-auth`: o projeto já depende de PyJWT (emite os
nossos próprios tokens) e o `PyJWKClient` resolve JWKS com cache embutido.
Uma dependência a menos num caminho de autenticação é uma superfície a menos
para auditar.

Sem `GOOGLE_CLIENT_ID` configurado a verificação levanta [GoogleNotConfigured]
e a rota responde 503 — o mesmo contrato honesto do storage de imagens. Melhor
dizer "não está ligado" do que aceitar token sem saber para quem ele foi
emitido.
"""

from dataclasses import dataclass

import jwt
from jwt import PyJWKClient

from app.core.config import settings

# Emissores aceitos. O Google usa as duas formas, com e sem esquema, e recusar
# uma delas quebra em produção de um jeito difícil de diagnosticar.
_ISSUERS = frozenset({"accounts.google.com", "https://accounts.google.com"})

# Chaves públicas do Google. O `PyJWKClient` faz cache e só rebusca quando
# aparece um `kid` desconhecido (rotação de chave).
_CERTS_URL = "https://www.googleapis.com/oauth2/v3/certs"

_jwk_client: PyJWKClient | None = None


class GoogleNotConfigured(Exception):
    """Sem GOOGLE_CLIENT_ID — a rota traduz em 503."""


class InvalidGoogleToken(Exception):
    """Token ausente, expirado, mal assinado, de outro cliente, ou com e-mail
    não verificado. A rota traduz em 401 com mensagem genérica."""


@dataclass(frozen=True)
class GoogleIdentity:
    """O que o Google afirma, já verificado.

    `sub` é o identificador estável da conta Google e é por ele que vinculamos
    — nunca pelo e-mail, que a pessoa pode trocar.
    """

    sub: str
    email: str
    name: str | None


def audiencias() -> list[str]:
    """Os client ids que aceitamos como `aud`.

    É uma LISTA porque o Google emite um client id por plataforma: web,
    Android e iOS têm os seus, e o `aud` do id_token é o de quem pediu. Um
    único valor funcionaria na web e recusaria todo login de celular — com
    "token inválido", que manda a pessoa depurar o lugar errado.
    """
    bruto = settings.GOOGLE_CLIENT_ID or ""
    return [p.strip() for p in bruto.split(",") if p.strip()]


def enabled() -> bool:
    return bool(audiencias())


def _client() -> PyJWKClient:
    global _jwk_client
    if _jwk_client is None:
        _jwk_client = PyJWKClient(_CERTS_URL)
    return _jwk_client


def verify(id_token: str) -> GoogleIdentity:
    """Verifica a assinatura e as claims; devolve quem é, ou levanta.

    O que é conferido, e por quê cada um:
    - **assinatura** contra a chave pública do Google (é o que impede forjar);
    - **`aud`** igual ao nosso client id — sem isso, um token emitido para
      OUTRO aplicativo seria aceito aqui, e qualquer desenvolvedor poderia
      entrar como qualquer pessoa ("confused deputy");
    - **`iss`** do Google;
    - **`exp`** (o PyJWT já recusa expirado);
    - **`email_verified`** — o Google permite contas com e-mail não
      confirmado, e aceitar uma delas deixaria alguém reivindicar o e-mail de
      outra pessoa e cair na conta dela pelo vínculo por e-mail.
    """
    if not enabled():
        raise GoogleNotConfigured()
    if not id_token:
        raise InvalidGoogleToken("empty token")
    try:
        chave = _client().get_signing_key_from_jwt(id_token)
        claims = jwt.decode(
            id_token,
            chave.key,
            algorithms=["RS256"],
            audience=audiencias(),
            issuer=list(_ISSUERS),
            options={"require": ["sub", "aud", "iss", "exp"]},
        )
    except Exception as exc:  # PyJWKClientError, DecodeError, ExpiredSignature…
        raise InvalidGoogleToken(str(exc)) from exc

    email = (claims.get("email") or "").strip().lower()
    if not email:
        raise InvalidGoogleToken("token without email")
    if claims.get("email_verified") is not True:
        raise InvalidGoogleToken("unverified email")
    sub = claims["sub"]
    nome = (claims.get("name") or "").strip() or None
    return GoogleIdentity(sub=sub, email=email, name=nome)
