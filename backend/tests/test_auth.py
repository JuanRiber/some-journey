"""Auth: troca de senha do usuário logado (POST /auth/change-password),
rate limit da troca de senha e invalidação de JWT em troca/reset (claim pcat)."""

import uuid
from datetime import timedelta

PW = "Sup3rSecret!pw"


def _account(client):
    """Registra + loga um usuário e devolve (email, headers)."""
    email = f"cp_{uuid.uuid4().hex[:10]}@t.com"
    client.post("/auth/register", json={"name": "T", "email": email, "password": PW})
    tok = client.post("/auth/login", json={"email": email, "password": PW}).json()["access_token"]
    return email, {"Authorization": f"Bearer {tok}"}


def test_change_password_success(client):
    email, h = _account(client)
    r = client.post(
        "/auth/change-password",
        json={"current_password": PW, "new_password": "BrandNewPass99"},
        headers=h,
    )
    assert r.status_code == 204, r.text
    # a NOVA senha loga
    assert client.post("/auth/login", json={"email": email, "password": "BrandNewPass99"}).status_code == 200
    # a antiga NÃO loga mais
    assert client.post("/auth/login", json={"email": email, "password": PW}).status_code == 401


def test_change_password_wrong_current_returns_401(client):
    _email, h = _account(client)
    r = client.post(
        "/auth/change-password",
        json={"current_password": "totallywrong", "new_password": "BrandNewPass99"},
        headers=h,
    )
    assert r.status_code == 401


def test_change_password_too_short_returns_422(client):
    _email, h = _account(client)
    r = client.post(
        "/auth/change-password",
        json={"current_password": PW, "new_password": "short"},
        headers=h,
    )
    assert r.status_code == 422


def test_change_password_unauthenticated_returns_401(client):
    r = client.post(
        "/auth/change-password",
        json={"current_password": PW, "new_password": "BrandNewPass99"},
    )
    assert r.status_code == 401


# --- Rate limit da troca de senha (por usuário + IP) -----------------------


def test_change_password_rate_limited_after_threshold(client, monkeypatch):
    """Chutes repetidos da senha ATUAL são travados: passado o teto, 429 em vez
    de 401 — trava o brute-force de quem já tem um token válido."""
    from app.core.config import settings

    monkeypatch.setattr(settings, "AUTH_RATE_LIMIT_ATTEMPTS", 3)
    _email, h = _account(client)
    codes = [
        client.post(
            "/auth/change-password",
            json={"current_password": "totallywrong", "new_password": "BrandNewPass99"},
            headers=h,
        ).status_code
        for _ in range(5)
    ]
    # As 3 primeiras passam o limiter (senha errada -> 401); a 4a estoura o teto.
    assert codes[:3] == [401, 401, 401]
    assert codes[3] == 429
    assert codes[4] == 429


# --- Invalidação de JWT em troca/reset de senha (claim pcat) ---------------


def _load_user(client, email):
    """Lê o User do banco (id + password_changed_at) por fora do request."""
    from app.db.session import SessionLocal
    from app.repositories import user_repository

    with SessionLocal() as db:
        user = user_repository.get_by_email(db, email)
        return user.id, user.password_changed_at


def test_token_without_pcat_claim_stays_valid(client):
    """Retrocompatibilidade: um token SEM pcat (emitido antes da adoção do claim)
    segue válido até expirar — não é recusado pela nova checagem."""
    from app.core.security import create_access_token

    email, _h = _account(client)
    uid, _pwd = _load_user(client, email)
    tok = create_access_token(uid)  # sem password_changed_at -> sem pcat
    r = client.get("/auth/me", headers={"Authorization": f"Bearer {tok}"})
    assert r.status_code == 200


def test_token_minted_before_password_change_is_rejected(client):
    """Mecanismo do pcat, determinístico: um token cujo pcat é ANTERIOR ao
    password_changed_at do usuário é recusado (401); um token com o pcat vigente
    é aceito (200)."""
    from app.core.security import create_access_token

    email, _h = _account(client)
    uid, pwd_changed = _load_user(client, email)

    tok_current = create_access_token(uid, pwd_changed)
    assert (
        client.get("/auth/me", headers={"Authorization": f"Bearer {tok_current}"}).status_code
        == 200
    )

    tok_old = create_access_token(uid, pwd_changed - timedelta(minutes=1))
    assert (
        client.get("/auth/me", headers={"Authorization": f"Bearer {tok_old}"}).status_code
        == 401
    )


def test_password_change_advances_pcat_and_kills_prior_token(client):
    """Fim a fim: trocar a senha avança password_changed_at no servidor, e um
    token emitido ANTES da troca deixa de ser aceito."""
    from app.core.security import create_access_token

    email, h = _account(client)
    uid, before = _load_user(client, email)

    r = client.post(
        "/auth/change-password",
        json={"current_password": PW, "new_password": "BrandNewPass99"},
        headers=h,
    )
    assert r.status_code == 204, r.text

    _uid, after = _load_user(client, email)
    assert after >= before  # a coluna avançou (ou ao menos não retrocedeu)

    # Um token com pcat anterior à troca é recusado agora.
    tok_before = create_access_token(uid, before - timedelta(seconds=1))
    assert (
        client.get("/auth/me", headers={"Authorization": f"Bearer {tok_before}"}).status_code
        == 401
    )
