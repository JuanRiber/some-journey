"""Storage de imagens via Supabase Storage (bucket PRIVADO).

Fluxo de segurança: o cliente envia o arquivo para o backend; o backend repassa
ao Supabase usando o SERVICE KEY (que nunca chega ao cliente). Na leitura, o
backend gera URLs ASSINADAS de curta duração — nunca uma URL pública. Guardamos
apenas o caminho no banco (memories.image_path); a URL é efêmera.

Sem SUPABASE_URL + SUPABASE_SERVICE_KEY o storage fica desabilitado: upload
levanta StorageNotConfigured (rota -> 503) e as assinaturas viram None.

Usa httpx síncrono (o backend é síncrono) contra a REST API do Storage.
"""

import httpx

from app.core.config import settings


class StorageNotConfigured(Exception):
    """Supabase não configurado (faltam URL/Service Key)."""


class StorageError(Exception):
    """Falha de comunicação com o Storage."""


def enabled() -> bool:
    return settings.storage_enabled


def _base() -> str:
    assert settings.SUPABASE_URL is not None
    return settings.SUPABASE_URL.rstrip("/")


def _auth_headers() -> dict[str, str]:
    # O gateway do Supabase exige o header `apikey` em TODA requisição, além do
    # Authorization: Bearer. Sem o `apikey` a API responde 401 ("No API key
    # found in request"). Usamos o service key nos dois (é o que autentica).
    key = settings.SUPABASE_SERVICE_KEY or ""
    return {"Authorization": f"Bearer {key}", "apikey": key}


def upload(path: str, data: bytes, content_type: str) -> None:
    """Sobe os bytes para `${bucket}/${path}` (upsert). Levanta em qualquer falha."""
    if not enabled():
        raise StorageNotConfigured()
    url = f"{_base()}/storage/v1/object/{settings.SUPABASE_BUCKET}/{path}"
    try:
        with httpx.Client(timeout=20) as client:
            resp = client.post(
                url,
                headers={**_auth_headers(), "Content-Type": content_type, "x-upsert": "true"},
                content=data,
            )
    except httpx.HTTPError as exc:
        raise StorageError(str(exc)) from exc
    if resp.status_code >= 300:
        raise StorageError(f"upload {resp.status_code}: {resp.text[:200]}")


def _normalize_signed(signed: str) -> str:
    # A API devolve algo como "/object/sign/<bucket>/<path>?token=..." (relativo
    # a /storage/v1). Normaliza para uma URL absoluta.
    return f"{_base()}/storage/v1/{signed.lstrip('/')}"


def sign_url(path: str, ttl: int | None = None) -> str | None:
    """URL assinada para um único objeto. None se desabilitado/sem path/erro."""
    if not enabled() or not path:
        return None
    result = sign_urls([path], ttl)
    return result.get(path)


def sign_urls(paths: list[str], ttl: int | None = None) -> dict[str, str]:
    """Assina vários objetos em UMA chamada (evita N round-trips na listagem).
    Caminhos que falharem simplesmente não entram no dict. Nunca levanta — uma
    miniatura ausente não pode derrubar a listagem inteira."""
    clean = [p for p in dict.fromkeys(paths) if p]
    if not enabled() or not clean:
        return {}
    ttl = ttl or settings.IMAGE_SIGNED_URL_TTL
    url = f"{_base()}/storage/v1/object/sign/{settings.SUPABASE_BUCKET}"
    try:
        with httpx.Client(timeout=10) as client:
            resp = client.post(url, headers=_auth_headers(), json={"expiresIn": ttl, "paths": clean})
        if resp.status_code >= 300:
            return {}
        items = resp.json()
    except (httpx.HTTPError, ValueError):
        return {}
    out: dict[str, str] = {}
    if isinstance(items, list):
        for item in items:
            p = item.get("path")
            signed = item.get("signedURL") or item.get("signedUrl")
            if p and signed:
                out[p] = _normalize_signed(signed)
    return out


def delete(path: str) -> None:
    """Best-effort: remove um objeto. Silencioso em falha (não bloqueia o fluxo)."""
    if not enabled() or not path:
        return
    url = f"{_base()}/storage/v1/object/{settings.SUPABASE_BUCKET}/{path}"
    try:
        with httpx.Client(timeout=10) as client:
            client.request("DELETE", url, headers=_auth_headers())
    except httpx.HTTPError:
        pass
