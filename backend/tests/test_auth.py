"""Auth: troca de senha do usuário logado (POST /auth/change-password)."""

import uuid

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
