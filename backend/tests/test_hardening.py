"""Testes do hardening de segurança: limite de corpo (Content-Length e por
bytes acumulados), upload em chunks, rate-limit por IP (anti-spraying), dummy
hash Argon2 no login e docs desabilitados em produção."""

import asyncio
import uuid

import pytest
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
        f"/memories/{mid}/images",
        files={"file": ("x.jpg", payload, "image/jpeg")},
        headers=h,
    )
    assert r.status_code == 413


# --- 4. Upload válido continua funcionando ---------------------------------
def test_valid_upload_still_works(client, auth_headers, monkeypatch):
    from app.core import storage

    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "upload", lambda *a, **k: None)
    monkeypatch.setattr(storage, "sign_urls", lambda paths, ttl=None: {p: "https://signed.example/x" for p in paths})
    h = auth_headers()
    mid = client.post(
        "/memories",
        json={"title": "m", "text": "t", "latitude": 1.0, "longitude": 2.0, "occurred_at": "2026-01-01T00:00:00Z"},
        headers=h,
    ).json()["id"]
    payload = b"\xff\xd8\xff\xe0" + b"0" * 64
    r = client.post(
        f"/memories/{mid}/images",
        files={"file": ("x.jpg", payload, "image/jpeg")},
        headers=h,
    )
    assert r.status_code == 200, r.text
    assert r.json()["image_url"] is not None


# --- 4b. Upload entre o teto JSON e o de imagem NÃO é barrado ---------------
def test_upload_between_json_and_image_limits_not_rejected(client, auth_headers, monkeypatch):
    """Regressão: a isenção de tamanho do middleware precisa reconhecer as rotas
    de upload reais (/images e /cover). Um arquivo acima de MAX_JSON_BODY_BYTES
    (1MB) mas abaixo de MAX_IMAGE_BYTES (5MB) deve passar do middleware — antes
    a isenção mirava "/image" e nunca casava, então tudo >1MB virava 413."""
    from app.core import storage

    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "upload", lambda *a, **k: None)
    monkeypatch.setattr(storage, "delete", lambda *a, **k: None)
    monkeypatch.setattr(
        storage, "sign_urls", lambda paths, ttl=None: {p: "https://signed.example/x" for p in paths}
    )
    monkeypatch.setattr(storage, "sign_url", lambda path, ttl=None: "https://signed.example/x")
    h = auth_headers()
    big = b"\xff\xd8\xff\xe0" + b"0" * (1_500_000)  # ~1.5MB: >1MB JSON, <5MB imagem

    mid = client.post(
        "/memories",
        json={"title": "m", "text": "t", "latitude": 1.0, "longitude": 2.0, "occurred_at": "2026-01-01T00:00:00Z"},
        headers=h,
    ).json()["id"]
    r_img = client.post(
        f"/memories/{mid}/images", files={"file": ("x.jpg", big, "image/jpeg")}, headers=h
    )
    assert r_img.status_code != 413, "upload de memória barrado pelo limite JSON"
    assert r_img.status_code == 200, r_img.text

    jid = client.post("/journeys", json={"title": "J"}, headers=h).json()["id"]
    r_cov = client.post(
        f"/journeys/{jid}/cover", files={"file": ("c.jpg", big, "image/jpeg")}, headers=h
    )
    assert r_cov.status_code != 413, "upload de capa barrado pelo limite JSON"
    assert r_cov.status_code == 200, r_cov.text


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


# --- 8. Balde por E-MAIL: o teto que um X-Forwarded-For forjado não fura ----
def _ip_a_cada_chamada(monkeypatch):
    """Faz cada requisição parecer vir de um IP novo — o que um cliente consegue
    escrevendo o X-Forwarded-For quando o uvicorn confia em '*'."""
    import itertools

    from app.api.routes import auth as auth_routes

    contador = itertools.count()
    monkeypatch.setattr(auth_routes, "_client_ip", lambda _r: f"10.0.0.{next(contador)}")


def test_email_bucket_holds_when_ip_changes_every_attempt(client, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "AUTH_RATE_LIMIT_EMAIL_ATTEMPTS", 3)
    _ip_a_cada_chamada(monkeypatch)
    alvo = f"alvo_{uuid.uuid4().hex}@t.com"

    codes = [
        client.post("/auth/login", json={"email": alvo, "password": "chute12345"}).status_code
        for _ in range(5)
    ]
    # Com IP novo a cada tentativa, o por-conta e o por-IP nunca enchem; só o
    # por-e-mail segura o brute-force.
    assert codes == [401, 401, 401, 429, 429]

    # E ele é por e-mail, não global: outra conta continua respondendo normal.
    outro = client.post(
        "/auth/login", json={"email": f"outro_{uuid.uuid4().hex}@t.com", "password": "x" * 10}
    )
    assert outro.status_code == 401


def test_email_bucket_also_guards_forgot_password(client, monkeypatch):
    # Sem ele, trocar de IP a cada pedido enche a caixa de alguém de e-mails de
    # recuperação.
    from app.core.config import settings

    monkeypatch.setattr(settings, "AUTH_RATE_LIMIT_EMAIL_ATTEMPTS", 2)
    _ip_a_cada_chamada(monkeypatch)
    alvo = f"caixa_{uuid.uuid4().hex}@t.com"

    codes = [
        client.post("/auth/forgot-password", json={"email": alvo}).status_code
        for _ in range(3)
    ]
    assert codes == [202, 202, 429]


# --- 9. STARTTLS confere o certificado do servidor SMTP --------------------
def test_starttls_verifies_the_server_certificate(monkeypatch):
    import ssl

    from app.core import email as email_delivery
    from app.core.config import settings

    monkeypatch.setattr(settings, "SMTP_HOST", "smtp.exemplo.test")
    monkeypatch.setattr(settings, "SMTP_FROM", "Some Journey <nao-responda@exemplo.test>")
    monkeypatch.setattr(settings, "SMTP_STARTTLS", True)
    visto: dict[str, object] = {}

    class _SMTPFalso:
        def __init__(self, *_a, **_k):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *_a):
            return False

        def starttls(self, context=None):
            visto["contexto"] = context

        def login(self, *_a):
            pass

        def send_message(self, _m):
            visto["enviado"] = True

    monkeypatch.setattr(email_delivery.smtplib, "SMTP", _SMTPFalso)
    email_delivery.send_password_reset("alguem@exemplo.test", "token-cru")

    contexto = visto["contexto"]
    # Sem contexto o smtplib usa um que aceita qualquer certificado: quem
    # estivesse no meio leria a senha do SMTP e todo link de recuperação.
    assert isinstance(contexto, ssl.SSLContext)
    assert contexto.verify_mode == ssl.CERT_REQUIRED
    assert contexto.check_hostname is True
    assert visto.get("enviado") is True


# --- 10. A foto do perfil tem o teto de upload, não o de JSON --------------
def test_avatar_between_json_and_image_limits_not_rejected(client, auth_headers, monkeypatch):
    """Regressão: /me/avatar não estava entre as rotas de upload do middleware,
    então todo avatar acima de 1 MB (o teto de JSON) virava 413, longe dos 5 MB
    prometidos."""
    from app.core import storage

    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "upload", lambda *a, **k: None)
    monkeypatch.setattr(storage, "delete", lambda *a, **k: None)
    monkeypatch.setattr(
        storage, "sign_urls", lambda paths, ttl=None: {p: "https://signed.example/x" for p in paths}
    )
    monkeypatch.setattr(storage, "sign_url", lambda path, ttl=None: "https://signed.example/x")
    big = b"\xff\xd8\xff\xe0" + b"0" * 1_500_000  # ~1.5MB: >1MB JSON, <5MB imagem

    r = client.post(
        "/me/avatar", files={"file": ("a.jpg", big, "image/jpeg")}, headers=auth_headers()
    )
    assert r.status_code != 413, "avatar barrado pelo limite JSON"
    assert r.status_code == 200, r.text


# --- 11. O que um ataque simulado transformou em 500 -----------------------
# Cada caso abaixo veio de um ataque contra uma cópia local da API em modo
# produção. Nos cinco a culpa é do que o cliente mandou: a resposta tem de ser
# uma recusa (4xx), nunca "o servidor quebrou".

_MEMORIA = {"title": "x", "latitude": 1.0, "longitude": 1.0, "occurred_at": "2024-01-01T12:00:00Z"}


@pytest.mark.parametrize(
    "quando",
    [
        "0001-01-01T00:00:00Z",       # o que envenenava a conta
        "0999-12-31T23:59:59Z",
        "1000-01-01T00:00:00+14:00",  # vira o ano 999 em UTC
        "3000-01-01T00:00:00Z",
    ],
)
def test_data_fora_do_intervalo_e_recusada_antes_de_gravar(client, auth_headers, quando):
    """Regressão: o ano 1 era gravado e depois não voltava — lido no fuso da
    sessão do banco, caía antes do ano 1. A criação dava 500 com a memória já
    gravada, e a timeline e o mapa da dona davam 500 para sempre."""
    h = auth_headers()
    r = client.post("/memories", json={**_MEMORIA, "occurred_at": quando}, headers=h)
    assert r.status_code == 422, r.text
    assert client.get("/memories", headers=h).json() == []
    assert client.get("/map", headers=h).status_code == 200


def test_datas_de_uma_vida_continuam_valendo(client, auth_headers):
    h = auth_headers()
    for quando in ["1900-01-01T00:00:00Z", "1000-01-01T12:00:00Z"]:
        r = client.post("/memories", json={**_MEMORIA, "occurred_at": quando}, headers=h)
        assert r.status_code == 201, (quando, r.text)
    assert client.get("/memories", headers=h).status_code == 200
    # O teto vale para quem pode olhar para frente: memória não pode ser do
    # futuro (regra de negócio à parte), jornada planejada pode.
    r = client.post("/journeys", json={"title": "J", "started_at": "2999-06-01T00:00:00Z"}, headers=h)
    assert r.status_code == 201, r.text


def test_o_limite_vale_para_todas_as_datas_de_entrada(client, auth_headers):
    # O mesmo tipo protege fases, jornadas e pontos de GPS.
    h = auth_headers()
    assert client.post(
        "/life-phases", json={"name": "Antiga", "started_at": "0001-01-01T00:00:00Z"}, headers=h
    ).status_code == 422
    assert client.post(
        "/journeys", json={"title": "J", "started_at": "0001-01-01T00:00:00Z"}, headers=h
    ).status_code == 422


@pytest.mark.parametrize("numero", ["NaN", "Infinity", "-Infinity", "1e400"])
def test_numero_que_nao_e_numero_da_422_e_nao_500(client, auth_headers, numero):
    """Regressão: a validação recusava a latitude, mas o 422 repete o valor
    recebido, e NaN/Infinity não cabem em JSON — a resposta de erro quebrava."""
    corpo = (
        '{"title":"x","latitude":%s,"longitude":1,"occurred_at":"2024-01-01T12:00:00Z"}' % numero
    )
    r = client.post(
        "/memories", content=corpo,
        headers={**auth_headers(), "Content-Type": "application/json"},
    )
    assert r.status_code == 422
    detalhe = r.json()["detail"]  # a resposta é JSON válido
    assert detalhe[0]["loc"] == ["body", "latitude"]
    assert isinstance(detalhe[0]["input"], str)


def test_o_422_comum_continua_no_mesmo_formato(client, auth_headers):
    # O tratador novo não pode mudar o contrato que os clientes já leem.
    r = client.post("/memories", json={**_MEMORIA, "latitude": 91}, headers=auth_headers())
    assert r.status_code == 422
    assert r.json()["detail"][0]["loc"] == ["body", "latitude"]
    assert "msg" in r.json()["detail"][0]


@pytest.mark.parametrize(
    "rota,corpo",
    [
        ("/memories", {**_MEMORIA, "title": "nulo\x00byte"}),
        ("/life-phases", {"name": "fase\x00nula"}),
        ("/journeys", {"title": "j\x00"}),
    ],
)
def test_byte_nul_no_texto_e_recusado_sem_gravar(client, auth_headers, rota, corpo):
    """Regressão: o Postgres não guarda NUL em texto e nada barrava antes — o
    INSERT levantava DataError e a resposta era 500."""
    h = auth_headers()
    r = client.post(rota, json=corpo, headers=h)
    assert r.status_code == 422, r.text
    assert "caractere" in r.json()["detail"]
    assert client.get(rota, headers=h).json() == []
    # A sessão desfeita não contamina a próxima requisição.
    assert client.post("/memories", json=_MEMORIA, headers=h).status_code == 201


def test_troca_de_senha_no_mesmo_segundo_derruba_o_token_antigo(client):
    """Regressão: o `pcat` é em segundos inteiros. Trocar a senha no mesmo
    segundo em que ela foi definida empatava os dois valores, e o token antigo
    sobrevivia à troca. O relógio da senha anterior vai para o futuro aqui só
    para tornar o empate certo, em vez de depender da sorte do relógio."""
    from sqlalchemy import func, text

    from app.db.session import SessionLocal
    from app.models.user import User

    email = f"pcat_{uuid.uuid4().hex[:10]}@t.com"
    senha = "Sup3rSecret!pw"
    client.post("/auth/register", json={"name": "P", "email": email, "password": senha})
    with SessionLocal() as db:
        user = db.query(User).filter(User.email == email).one()
        user.password_changed_at = func.now() + text("interval '10 seconds'")
        db.commit()
    token = client.post("/auth/login", json={"email": email, "password": senha}).json()["access_token"]
    h = {"Authorization": f"Bearer {token}"}
    assert client.get("/auth/me", headers=h).status_code == 200

    r = client.post(
        "/auth/change-password",
        json={"current_password": senha, "new_password": "OutraSenhaForte123"},
        headers=h,
    )
    assert r.status_code == 204, r.text
    assert client.get("/auth/me", headers=h).status_code == 401

    # E quem entra com a senha nova não é derrubado pelo segundo adiantado.
    novo = client.post(
        "/auth/login", json={"email": email, "password": "OutraSenhaForte123"}
    ).json()["access_token"]
    assert client.get("/auth/me", headers={"Authorization": f"Bearer {novo}"}).status_code == 200


def test_corpo_em_pedacos_acima_do_teto_da_413_e_nao_400(client, auth_headers):
    """Regressão: sem Content-Length, o estouro era detectado durante a leitura
    — e o FastAPI engole qualquer exceção ali e responde 400. O corpo já era
    recusado; o motivo é que estava errado."""

    def pedacos():
        for _ in range(40):
            yield b"x" * 65536  # ~2,6 MB > 1 MB

    r = client.post(
        "/memories",
        content=pedacos(),
        headers={**auth_headers(), "Content-Type": "application/json"},
    )
    assert r.status_code == 413
    assert r.json()["detail"] == "Request body too large."
