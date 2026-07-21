"""Recuperação de senha real: POST /auth/forgot-password + /auth/reset-password.

Cobre o contrato anti-enumeração (202 genérico sempre), o ciclo feliz (token do
e-mail redefine a senha), uso único, expiração, invalidação do token anterior e
validação da nova senha.
"""

import uuid
from datetime import UTC, datetime, timedelta

import pytest

from app.db.session import SessionLocal
from app.models.password_reset import PasswordResetToken
from app.services import auth_service

PW = "Sup3rSecret!pw"
NEW_PW = "BrandNewPass99"


def _register(client, email: str) -> None:
    client.post("/auth/register", json={"name": "T", "email": email, "password": PW})


@pytest.fixture()
def captured_tokens(monkeypatch):
    """Captura (email, raw_token) que a rota entregaria por e-mail em 2º plano.
    Substitui o envio real — o BackgroundTask roda de forma síncrona no TestClient."""
    sent: list[tuple[str, str]] = []

    def _fake_send(to_email: str, raw_token: str) -> None:
        sent.append((to_email, raw_token))

    monkeypatch.setattr(
        "app.core.email.send_password_reset", _fake_send, raising=True
    )
    return sent


def test_forgot_password_is_generic_202_for_known_and_unknown(client, captured_tokens):
    email = f"fp_{uuid.uuid4().hex[:8]}@t.com"
    _register(client, email)

    known = client.post("/auth/forgot-password", json={"email": email})
    unknown = client.post(
        "/auth/forgot-password", json={"email": f"nobody_{uuid.uuid4().hex[:8]}@t.com"}
    )

    # Mesma resposta para conta existente e inexistente (anti-enumeração).
    assert known.status_code == 202
    assert unknown.status_code == 202
    assert known.json() == unknown.json()
    # Só a conta existente gerou token de fato.
    assert len(captured_tokens) == 1
    assert captured_tokens[0][0] == email


def test_reset_password_full_cycle(client, captured_tokens):
    email = f"rp_{uuid.uuid4().hex[:8]}@t.com"
    _register(client, email)
    client.post("/auth/forgot-password", json={"email": email})
    token = captured_tokens[-1][1]

    r = client.post(
        "/auth/reset-password", json={"token": token, "new_password": NEW_PW}
    )
    assert r.status_code == 204, r.text
    # A nova senha loga; a antiga não.
    assert client.post("/auth/login", json={"email": email, "password": NEW_PW}).status_code == 200
    assert client.post("/auth/login", json={"email": email, "password": PW}).status_code == 401


def test_reset_password_token_is_single_use(client, captured_tokens):
    email = f"su_{uuid.uuid4().hex[:8]}@t.com"
    _register(client, email)
    client.post("/auth/forgot-password", json={"email": email})
    token = captured_tokens[-1][1]

    first = client.post(
        "/auth/reset-password", json={"token": token, "new_password": NEW_PW}
    )
    assert first.status_code == 204
    # Reusar o mesmo token falha (400).
    again = client.post(
        "/auth/reset-password", json={"token": token, "new_password": "AnotherPass123"}
    )
    assert again.status_code == 400


def test_reset_password_invalid_token_returns_400(client):
    r = client.post(
        "/auth/reset-password",
        json={"token": "not-a-real-token-abcdefghij", "new_password": NEW_PW},
    )
    assert r.status_code == 400


def test_reset_password_expired_token_returns_400(client, captured_tokens):
    email = f"ex_{uuid.uuid4().hex[:8]}@t.com"
    _register(client, email)
    client.post("/auth/forgot-password", json={"email": email})
    token = captured_tokens[-1][1]

    # Força a expiração no banco (expires_at no passado).
    with SessionLocal() as db:
        db.query(PasswordResetToken).filter(
            PasswordResetToken.token_hash == auth_service._hash_token(token)
        ).update({"expires_at": datetime.now(UTC) - timedelta(minutes=1)})
        db.commit()

    r = client.post(
        "/auth/reset-password", json={"token": token, "new_password": NEW_PW}
    )
    assert r.status_code == 400


def test_new_forgot_invalidates_previous_token(client, captured_tokens):
    email = f"iv_{uuid.uuid4().hex[:8]}@t.com"
    _register(client, email)
    client.post("/auth/forgot-password", json={"email": email})
    old_token = captured_tokens[-1][1]
    client.post("/auth/forgot-password", json={"email": email})
    new_token = captured_tokens[-1][1]
    assert old_token != new_token

    # O token antigo não vale mais; o novo, sim.
    assert client.post(
        "/auth/reset-password", json={"token": old_token, "new_password": NEW_PW}
    ).status_code == 400
    assert client.post(
        "/auth/reset-password", json={"token": new_token, "new_password": NEW_PW}
    ).status_code == 204


def test_reset_password_too_short_returns_422(client, captured_tokens):
    email = f"sh_{uuid.uuid4().hex[:8]}@t.com"
    _register(client, email)
    client.post("/auth/forgot-password", json={"email": email})
    token = captured_tokens[-1][1]
    r = client.post(
        "/auth/reset-password", json={"token": token, "new_password": "short"}
    )
    assert r.status_code == 422
