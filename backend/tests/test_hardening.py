"""Testes do hardening de segurança: limite de corpo (Content-Length e por
bytes acumulados), upload em chunks, rate-limit por IP (anti-spraying), dummy
hash Argon2 no login e docs desabilitados em produção."""

import asyncio
import uuid

from fastapi.testclient import TestClient


# --- 1. Limite de corpo: Content-Length acima do teto -> 413 ---------------
def test_oversized_json_body_rejected_413(client):
    # ~2MB > MAX_JSON_BODY_BYTES (1MB): rejeitado antes de chegar no handler.
    body = b'{"email":"a@b.com","password":"' + b"A" * (2 * 1024 * 1024) + b'"}'
    r = client.post(
        "/auth/login", content=body, headers={"content-type": "application/json"}
    )
    assert r.status_code == 413


def test_normal_body_not_rejected(client):
    # Corpo pequeno passa pelo middleware (credencial inválida -> 401).
    r = client.post(
        "/auth/login",
        json={"email": f"n_{uuid.uuid4().hex}@t.com", "password": "whatever12345"},
    )
    assert r.status_code == 401


# --- 2. Limite de corpo: sem Content-Length, contando bytes acumulados ------
def test_body_limit_streaming_without_content_length():
    from app.core.body_limit import BodySizeLimitMiddleware

    async def downstream(scope, receive, send):
        more = True
        while more:
            message = await receive()
            more = message.get("more_body", False)
        await send({"type": "http.response.start", "status": 200, "headers": []})
        await send({"type": "http.response.body", "body": b"ok"})

    mw = BodySizeLimitMiddleware(
        downstream, max_body_bytes=10, upload_max_body_bytes=10
    )
    scope = {"type": "http", "method": "POST", "path": "/x", "headers": []}  # sem CL
    chunks = [b"a" * 8, b"b" * 8]  # 16 bytes > 10

    async def drive():
        it = iter(chunks)

        async def receive():
            try:
                return {"type": "http.request", "body": next(it), "more_body": True}
            except StopIteration:
                return {"type": "http.request", "body": b"", "more_body": False}

        sent: list[dict] = []

        async def send(message):
            sent.append(message)

        await mw(scope, receive, send)
        return sent

    sent = asyncio.run(drive())
    starts = [m for m in sent if m["type"] == "http.response.start"]
    assert starts and starts[0]["status"] == 413


# --- 3. Upload acima do limite -> 413 (sem carregar tudo) -------------------
def test_upload_over_limit_returns_413(client, auth_headers, monkeypatch):
    from app.core.config import settings

    # teto minúsculo: o leitor em chunks corta já no primeiro bloco.
    monkeypatch.setattr(settings, "MAX_IMAGE_BYTES", 16)
    h = auth_headers()
    mid = client.post(
        "/memories",
        json={"title": "m", "text": "t", "latitude": 1.0, "longitude": 2.0, "occurred_at": "2026-01-01T00:00:00Z"},
        headers=h,
    ).json()["id"]
    payload = b"\xff\xd8\xff\xe0" + b"0" * 500  # > 16 bytes
    r = client.post(
        f"/memories/{mid}/image",
        files={"file": ("x.jpg", payload, "image/jpeg")},
        headers=h,
    )
    assert r.status_code == 413


# --- 4. Upload válido continua funcionando ---------------------------------
def test_valid_upload_still_works(client, auth_headers, monkeypatch):
    from app.core import storage

    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "upload", lambda *a, **k: None)
    monkeypatch.setattr(storage, "sign_url", lambda *a, **k: "https://signed.example/x")
    h = auth_headers()
    mid = client.post(
        "/memories",
        json={"title": "m", "text": "t", "latitude": 1.0, "longitude": 2.0, "occurred_at": "2026-01-01T00:00:00Z"},
        headers=h,
    ).json()["id"]
    payload = b"\xff\xd8\xff\xe0" + b"0" * 64
    r = client.post(
        f"/memories/{mid}/image",
        files={"file": ("x.jpg", payload, "image/jpeg")},
        headers=h,
    )
    assert r.status_code == 200, r.text
    assert r.json()["image_url"] is not None


# --- 5. Login com e-mail inexistente: 401 mas roda o dummy hash -------------
def test_login_unknown_email_runs_dummy_verify(client, monkeypatch):
    from app.services import auth_service

    calls = {"n": 0}
    real = auth_service.verify_password

    def spy(pw, h):
        calls["n"] += 1
        return real(pw, h)

    monkeypatch.setattr(auth_service, "verify_password", spy)
    r = client.post(
        "/auth/login",
        json={"email": f"ghost_{uuid.uuid4().hex}@t.com", "password": "whatever12345"},
    )
    assert r.status_code == 401
    assert calls["n"] == 1  # argon2 rodou (dummy) mesmo sem usuário


# --- 6. Rate limit por IP dispara mesmo com e-mails diferentes -------------
def test_ip_rate_limit_blocks_spraying(client, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "AUTH_RATE_LIMIT_IP_ATTEMPTS", 5)
    codes = []
    for _ in range(7):  # e-mail novo a cada vez -> per-conta nunca trava
        codes.append(
            client.post(
                "/auth/login",
                json={"email": f"spray_{uuid.uuid4().hex}@t.com", "password": "whatever12345"},
            ).status_code
        )
    assert 429 in codes  # spraying travado pelo limite por IP
    assert codes.index(429) == 5  # só trava depois de exceder o teto (5)


# --- 7. docs/openapi desabilitados em produção -----------------------------
def test_docs_disabled_in_production(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "APP_ENV", "production")
    from app.main import create_app

    with TestClient(create_app(), base_url="http://localhost") as tc:
        assert tc.get("/openapi.json").status_code == 404
        assert tc.get("/docs").status_code == 404
        assert tc.get("/redoc").status_code == 404


def test_docs_enabled_outside_production(client):
    assert client.get("/openapi.json").status_code == 200
    assert client.get("/docs").status_code == 200


# --- 8. Cadastro fechado em produção, aberto fora dela ---------------------
def test_registration_closed_in_production(client, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "APP_ENV", "production")
    monkeypatch.setattr(settings, "REGISTRATION_OPEN", None)  # herda -> fechado
    r = client.post(
        "/auth/register",
        json={"name": "x", "email": f"prod_{uuid.uuid4().hex}@t.com", "password": "whatever12345"},
    )
    assert r.status_code == 403


def test_registration_open_in_dev(client):
    r = client.post(
        "/auth/register",
        json={"name": "x", "email": f"dev_{uuid.uuid4().hex}@t.com", "password": "whatever12345"},
    )
    assert r.status_code == 201
