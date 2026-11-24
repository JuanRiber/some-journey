"""Conferir a senha contra um hash que não dá para conferir.

O hash de uma conta pode estar corrompido — uma linha legada, uma restauração
mal feita, uma edição à mão. Para quem está entrando isso tem de ser o mesmo
"e-mail ou senha incorretos" de sempre: nunca um erro 500, que além de não
ajudar ninguém diz a quem sonda que aquela conta existe e tem algo de errado.

Estes testes existem por causa de uma atualização de dependência: até a pwdlib
0.3 um hash argon2 truncado devolvia False; a partir da 0.4.1 ele levanta uma
exceção nova (`HashVerificationError`). O código pegava só a antiga. Os casos
abaixo passam nas duas versões, e é isso que eles prendem.
"""

import pytest
from sqlalchemy import text

from app.core.security import hash_password, verify_password

_BOM = hash_password("senha-de-teste-123")

_CORROMPIDOS = {
    "formato-desconhecido": "isto-nao-e-hash",
    "argon2-truncado": _BOM[:40],
    "argon2-sem-o-fim": _BOM[:-10],
    "argon2-parametros-quebrados": "$argon2id$v=19$m=abc,t=3,p=4$c2FsdA$aGFzaA",
    "vazio": "",
}


def test_hash_bom_confere_e_senha_errada_nao():
    assert verify_password("senha-de-teste-123", _BOM) is True
    assert verify_password("outra-senha-456", _BOM) is False


@pytest.mark.parametrize("corrompido", _CORROMPIDOS.values(), ids=_CORROMPIDOS.keys())
def test_hash_que_nao_da_para_conferir_e_falso_e_nunca_excecao(corrompido):
    assert verify_password("senha-de-teste-123", corrompido) is False


@pytest.mark.parametrize("corrompido", _CORROMPIDOS.values(), ids=_CORROMPIDOS.keys())
def test_login_com_hash_corrompido_e_401_generico_nunca_500(
    client, db_session, corrompido
):
    email = "corrompido@test.com"
    client.post(
        "/auth/register",
        json={"name": "T", "email": email, "password": "Sup3rSecret!pw"},
    )
    db_session.execute(
        text("UPDATE users SET password_hash = :h WHERE email = :e"),
        {"h": corrompido, "e": email},
    )
    db_session.commit()

    r = client.post("/auth/login", json={"email": email, "password": "Sup3rSecret!pw"})

    assert r.status_code == 401
    assert r.json()["detail"] == "E-mail ou senha incorretos."


def test_trocar_senha_com_hash_corrompido_tambem_nao_quebra(client, db_session):
    email = "corrompido2@test.com"
    client.post(
        "/auth/register",
        json={"name": "T", "email": email, "password": "Sup3rSecret!pw"},
    )
    token = client.post(
        "/auth/login", json={"email": email, "password": "Sup3rSecret!pw"}
    ).json()["access_token"]
    db_session.execute(
        text("UPDATE users SET password_hash = :h WHERE email = :e"),
        {"h": _BOM[:40], "e": email},
    )
    db_session.commit()

    r = client.post(
        "/auth/change-password",
        headers={"Authorization": f"Bearer {token}"},
        json={"current_password": "Sup3rSecret!pw", "new_password": "OutraSenha123"},
    )

    assert r.status_code == 401
