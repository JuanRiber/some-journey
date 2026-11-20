"""A sessão dura mais que o access token: POST /auth/refresh e /auth/logout.

Cobre a rotação (cada refresh token vale uma troca), a folga curta do reuso
honesto, a revogação da família quando o reuso não é honesto, e os três
caminhos que encerram sessões: logout, troca de senha e redefinição de senha.
"""

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import select, text

from app.models.refresh_token import RefreshToken
from app.services import auth_service

PW = "Sup3rSecret!pw"
NEW_PW = "BrandNewPass99"


def _entrar(client, email: str | None = None) -> tuple[str, dict]:
    email = email or f"r_{uuid.uuid4().hex[:10]}@test.com"
    client.post("/auth/register", json={"name": "T", "email": email, "password": PW})
    r = client.post("/auth/login", json={"email": email, "password": PW})
    assert r.status_code == 200, r.text
    return email, r.json()


def _renovar(client, refresh_token: str):
    return client.post("/auth/refresh", json={"refresh_token": refresh_token})


def _me(client, access_token: str) -> int:
    return client.get(
        "/auth/me", headers={"Authorization": f"Bearer {access_token}"}
    ).status_code


def _envelhecer_uso(db_session, segundos: int) -> None:
    """Faz as trocas já feitas parecerem ter acontecido há `segundos`."""
    db_session.execute(
        text(
            "UPDATE refresh_tokens SET used_at = used_at - make_interval(secs => :s) "
            "WHERE used_at IS NOT NULL"
        ),
        {"s": segundos},
    )
    db_session.commit()


# --- emissão ---------------------------------------------------------------


def test_login_devolve_refresh_token_e_guarda_so_o_hash(client, db_session):
    _, sessao = _entrar(client)

    cru = sessao["refresh_token"]
    assert len(cru) >= 43  # 32+ bytes em base64url
    (linha,) = db_session.scalars(select(RefreshToken)).all()
    assert linha.token_hash != cru
    assert linha.token_hash == auth_service._hash_token(cru)
    assert linha.used_at is None and linha.revoked_at is None
    restante = linha.expires_at - datetime.now(UTC)
    assert timedelta(days=29) < restante <= timedelta(days=30)


def test_cada_login_e_uma_sessao_separada(client, db_session):
    email, _ = _entrar(client)
    client.post("/auth/login", json={"email": email, "password": PW})

    familias = {t.family_id for t in db_session.scalars(select(RefreshToken))}
    assert len(familias) == 2


# --- rotação ---------------------------------------------------------------


def test_renovar_devolve_um_par_novo_que_funciona(client):
    _, sessao = _entrar(client)

    r = _renovar(client, sessao["refresh_token"])

    assert r.status_code == 200, r.text
    novo = r.json()
    assert set(novo) == {"access_token", "token_type", "expires_in", "refresh_token"}
    assert novo["refresh_token"] != sessao["refresh_token"]
    assert _me(client, novo["access_token"]) == 200


def test_o_sucessor_fica_na_mesma_familia_e_renova_de_novo(client, db_session):
    _, sessao = _entrar(client)

    segundo = _renovar(client, sessao["refresh_token"]).json()
    terceiro = _renovar(client, segundo["refresh_token"])

    assert terceiro.status_code == 200
    tokens = db_session.scalars(select(RefreshToken)).all()
    assert len(tokens) == 3
    assert len({t.family_id for t in tokens}) == 1
    assert sum(t.used_at is None for t in tokens) == 1  # só o vigente


def test_renovar_nao_pede_access_token(client):
    """Ele já venceu — é por isso que o app está renovando."""
    _, sessao = _entrar(client)
    r = client.post(
        "/auth/refresh",
        json={"refresh_token": sessao["refresh_token"]},
        headers={"Authorization": "Bearer token-vencido-qualquer"},
    )
    assert r.status_code == 200


# --- o que não renova ------------------------------------------------------


def test_token_desconhecido_responde_401_em_portugues(client):
    r = _renovar(client, "x" * 64)
    assert r.status_code == 401
    assert r.json()["detail"] == "Sua sessão expirou. Entre de novo."


def test_token_vencido_nao_renova(client, db_session):
    _, sessao = _entrar(client)
    db_session.execute(
        text("UPDATE refresh_tokens SET expires_at = now() - interval '1 second'")
    )
    db_session.commit()

    assert _renovar(client, sessao["refresh_token"]).status_code == 401


def test_conta_desativada_nao_renova(client, db_session):
    _, sessao = _entrar(client)
    db_session.execute(text("UPDATE users SET is_active = false"))
    db_session.commit()

    assert _renovar(client, sessao["refresh_token"]).status_code == 401


def test_corpo_com_campo_a_mais_e_recusado(client):
    _, sessao = _entrar(client)
    r = client.post(
        "/auth/refresh",
        json={"refresh_token": sessao["refresh_token"], "user_id": str(uuid.uuid4())},
    )
    assert r.status_code == 422


# --- reuso -----------------------------------------------------------------


def test_reuso_imediato_e_a_folga_das_duas_abas(client, db_session):
    """Duas abas com o mesmo token guardado renovam quase juntas: as duas
    recebem um par válido e ninguém cai."""
    _, sessao = _entrar(client)

    aba_a = _renovar(client, sessao["refresh_token"])
    aba_b = _renovar(client, sessao["refresh_token"])

    assert aba_a.status_code == 200 and aba_b.status_code == 200
    assert aba_a.json()["refresh_token"] != aba_b.json()["refresh_token"]
    assert _renovar(client, aba_a.json()["refresh_token"]).status_code == 200
    assert _renovar(client, aba_b.json()["refresh_token"]).status_code == 200
    assert len({t.family_id for t in db_session.scalars(select(RefreshToken))}) == 1


def test_reuso_fora_da_folga_derruba_a_sessao_inteira(client, db_session):
    """Token trocado que reaparece depois é cópia: nem quem copiou nem a dona
    continuam com sessão — e o sucessor legítimo também cai."""
    _, sessao = _entrar(client)
    sucessor = _renovar(client, sessao["refresh_token"]).json()
    _envelhecer_uso(db_session, 21)

    reuso = _renovar(client, sessao["refresh_token"])

    assert reuso.status_code == 401
    assert _renovar(client, sucessor["refresh_token"]).status_code == 401
    tokens = db_session.scalars(select(RefreshToken)).all()
    assert all(t.revoked_at is not None for t in tokens)


def test_reuso_derruba_so_aquela_sessao(client, db_session):
    email, celular = _entrar(client)
    computador = client.post(
        "/auth/login", json={"email": email, "password": PW}
    ).json()
    _renovar(client, celular["refresh_token"])
    _envelhecer_uso(db_session, 60)

    assert _renovar(client, celular["refresh_token"]).status_code == 401
    assert _renovar(client, computador["refresh_token"]).status_code == 200


# --- o que encerra sessões -------------------------------------------------


def test_logout_revoga_a_sessao_e_responde_204(client):
    _, sessao = _entrar(client)

    r = client.post("/auth/logout", json={"refresh_token": sessao["refresh_token"]})

    assert r.status_code == 204
    assert _renovar(client, sessao["refresh_token"]).status_code == 401


def test_logout_derruba_o_sucessor_ja_emitido(client):
    """Sair com um token antigo (outra aba já renovou) encerra a sessão mesmo
    assim: o que se revoga é a família."""
    _, sessao = _entrar(client)
    sucessor = _renovar(client, sessao["refresh_token"]).json()

    client.post("/auth/logout", json={"refresh_token": sessao["refresh_token"]})

    assert _renovar(client, sucessor["refresh_token"]).status_code == 401


def test_logout_de_token_desconhecido_tambem_e_204(client):
    r = client.post("/auth/logout", json={"refresh_token": "y" * 64})
    assert r.status_code == 204


def test_logout_nao_mexe_nas_outras_sessoes(client):
    email, celular = _entrar(client)
    computador = client.post(
        "/auth/login", json={"email": email, "password": PW}
    ).json()

    client.post("/auth/logout", json={"refresh_token": celular["refresh_token"]})

    assert _renovar(client, computador["refresh_token"]).status_code == 200


def test_trocar_a_senha_encerra_todas_as_sessoes(client):
    email, celular = _entrar(client)
    computador = client.post(
        "/auth/login", json={"email": email, "password": PW}
    ).json()

    r = client.post(
        "/auth/change-password",
        json={"current_password": PW, "new_password": NEW_PW},
        headers={"Authorization": f"Bearer {celular['access_token']}"},
    )

    assert r.status_code == 204
    assert _renovar(client, celular["refresh_token"]).status_code == 401
    assert _renovar(client, computador["refresh_token"]).status_code == 401


def test_senha_atual_errada_nao_encerra_sessao_nenhuma(client):
    _, sessao = _entrar(client)

    r = client.post(
        "/auth/change-password",
        json={"current_password": "nao-e-esta", "new_password": NEW_PW},
        headers={"Authorization": f"Bearer {sessao['access_token']}"},
    )

    assert r.status_code == 401
    assert _renovar(client, sessao["refresh_token"]).status_code == 200


def test_redefinir_a_senha_encerra_todas_as_sessoes(client, db_session):
    email, sessao = _entrar(client)
    cru = auth_service.request_password_reset(db_session, email=email)

    r = client.post(
        "/auth/reset-password", json={"token": cru, "new_password": NEW_PW}
    )

    assert r.status_code == 204
    assert _renovar(client, sessao["refresh_token"]).status_code == 401


# --- faxina e limite -------------------------------------------------------


def test_emitir_apaga_os_tokens_mortos_da_pessoa(client, db_session):
    email, sessao = _entrar(client)
    _renovar(client, sessao["refresh_token"])
    _envelhecer_uso(db_session, 2 * 24 * 3600)

    client.post("/auth/login", json={"email": email, "password": PW})

    tokens = db_session.scalars(select(RefreshToken)).all()
    assert all(t.used_at is None for t in tokens)
    assert len(tokens) == 2  # o sucessor da 1ª sessão + o do login novo


def test_renovacao_tem_limite_por_ip(client, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "AUTH_RATE_LIMIT_IP_ATTEMPTS", 2)

    respostas = [_renovar(client, "z" * 64).status_code for _ in range(3)]

    assert respostas == [401, 401, 429]


# --- o sinal que o app usa para saber quando renovar -----------------------


def test_o_401_de_sessao_vem_marcado_e_o_navegador_pode_ler_a_marca(client):
    """O app renova quando o 401 traz WWW-Authenticate. No navegador esse
    header só chega ao código se o CORS o expuser — sem isso o app web cairia
    no palpite pelo caminho, e renovaria onde não deve."""
    origem = "http://localhost:8081"

    r = client.get(
        "/auth/me",
        headers={"Authorization": "Bearer nao-vale", "Origin": origem},
    )

    assert r.status_code == 401
    assert r.headers["WWW-Authenticate"] == "Bearer"
    expostos = r.headers["Access-Control-Expose-Headers"]
    assert "WWW-Authenticate" in expostos
    assert "X-Next-Cursor" in expostos  # o da paginação continua exposto


def test_senha_atual_errada_e_um_401_sem_a_marca_de_sessao(client):
    """É o 401 que NÃO pede renovação: a sessão está boa, a senha é que não."""
    _, sessao = _entrar(client)

    r = client.post(
        "/auth/change-password",
        json={"current_password": "nao-e-esta", "new_password": NEW_PW},
        headers={"Authorization": f"Bearer {sessao['access_token']}"},
    )

    assert r.status_code == 401
    assert "WWW-Authenticate" not in r.headers
