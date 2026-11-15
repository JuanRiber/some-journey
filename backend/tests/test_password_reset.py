"""Recuperação de senha real: POST /auth/forgot-password + /auth/reset-password.

Cobre o contrato anti-enumeração (202 genérico sempre), o ciclo feliz (token do
e-mail redefine a senha), uso único, expiração, invalidação do token anterior e
validação da nova senha.
"""

import re
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path
from urllib.parse import urlsplit

import pytest

from app.core import email
from app.core.config import Settings
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


def test_reset_link_default_points_to_the_published_app():
    """O link do e-mail leva o token na querystring: quem é dono do host recebe
    o token. O padrão tem de ser o endereço onde o app é publicado — o projeto
    do Cloudflare Pages do workflow de deploy —, nunca um site de terceiro
    (`some-journey.pages.dev`, sem o sufixo, já é de outro)."""
    # O padrão do CAMPO, não `settings`: um .env local pode sobrepor o valor.
    default = Settings.model_fields["PASSWORD_RESET_URL_BASE"].default
    workflow = (
        Path(__file__).resolve().parents[2] / ".github" / "workflows" / "deploy-web.yml"
    ).read_text(encoding="utf-8")
    project = re.search(r"vars\.CF_PAGES_PROJECT \|\| '([^']+)'", workflow)
    assert project, "padrão de CF_PAGES_PROJECT não encontrado no deploy-web.yml"

    url = urlsplit(default)
    assert url.scheme == "https"
    assert url.hostname == f"{project.group(1)}.pages.dev"


def test_reset_link_default_opens_the_new_password_screen():
    """O link tem de cair numa rota que o app conhece — senão abre no login e a
    pessoa fica com um token na URL e nenhum lugar onde usá-lo. A rota mora
    depois do `#` (é onde o app web guarda as rotas, e o que vem depois do `#`
    não é enviado a servidor nenhum), e é a mesma que o app declara."""
    default = Settings.model_fields["PASSWORD_RESET_URL_BASE"].default
    url = urlsplit(default)
    assert url.path == "/" and not url.query, "a rota do app vai depois do #"

    startup = (
        Path(__file__).resolve().parents[2]
        / "app_flutter" / "lib" / "features" / "auth" / "startup_domain.dart"
    ).read_text(encoding="utf-8")
    route = re.search(r"const rotaResetSenha = '([^']+)';", startup)
    assert route, "rotaResetSenha não encontrada no startup_domain.dart"
    assert url.fragment == route.group(1)


@pytest.mark.parametrize(
    ("base", "link"),
    [
        # A forma do padrão: rota do app depois do `#`, token na querystring dela.
        (
            "https://app.exemplo.test/#/reset-password",
            "https://app.exemplo.test/#/reset-password?token=tok123",
        ),
        (
            "https://app.exemplo.test/reset-password/",
            "https://app.exemplo.test/reset-password?token=tok123",
        ),
        (
            "https://app.exemplo.test/reset?lang=pt",
            "https://app.exemplo.test/reset?lang=pt&token=tok123",
        ),
    ],
)
def test_reset_link_carries_the_token_on_the_configured_base(monkeypatch, base, link):
    monkeypatch.setattr(email.settings, "PASSWORD_RESET_URL_BASE", base)
    assert email._reset_link("tok123") == link
