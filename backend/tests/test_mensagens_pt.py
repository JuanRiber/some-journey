"""As mensagens de erro chegam em português.

O app mostra o `detail` da API como está (e, no 422, o `detail[0].msg`): uma
mensagem em inglês ali é o que o tester lê. Estes testes seguram as duas
pontas — as nossas frases fixas e as do Pydantic, traduzidas no 422 — sem
mexer no formato que os clientes leem (`loc`, `type` continuam iguais).
"""

import uuid

import pytest


def _msg(r) -> str:
    assert r.status_code == 422, r.text
    return r.json()["detail"][0]["msg"]


def test_login_errado_responde_em_portugues(client):
    r = client.post(
        "/auth/login",
        json={"email": f"ninguem_{uuid.uuid4().hex}@t.com", "password": "errada-123"},
    )
    assert r.status_code == 401
    assert r.json()["detail"] == "E-mail ou senha incorretos."


def test_campo_obrigatorio_diz_qual_campo(client):
    r = client.post("/auth/login", json={"email": "a@t.com"})
    assert _msg(r) == "Senha é obrigatório."
    assert r.json()["detail"][0]["type"] == "missing"  # o tipo não muda


def test_texto_curto_demais_diz_o_minimo(client):
    r = client.post(
        "/auth/register",
        json={"name": "x", "email": f"c_{uuid.uuid4().hex}@t.com", "password": "123"},
    )
    assert _msg(r).startswith("Senha precisa ter pelo menos ")


def test_email_invalido(client):
    r = client.post("/auth/login", json={"email": "sem-arroba", "password": "x" * 10})
    assert _msg(r) == "E-mail não é um e-mail válido."


def test_mensagem_dos_nossos_validadores_perde_o_prefixo_em_ingles(client, auth_headers):
    r = client.post(
        "/journeys",
        json={
            "title": "j",
            "started_at": "2025-01-02T00:00:00Z",
            "ended_at": "2025-01-01T00:00:00Z",
        },
        headers=auth_headers(),
    )
    msg = _msg(r)
    assert not msg.startswith("Value error")
    assert msg == "O fim da jornada não pode ser antes do começo"


def test_limite_numerico_escrito_como_se_le(client, auth_headers):
    r = client.post(
        "/memories",
        json={"title": "t", "occurred_at": "2025-01-01T00:00:00Z", "latitude": 91, "longitude": 0},
        headers=auth_headers(),
    )
    assert _msg(r) == "Latitude precisa ser no máximo 90."


@pytest.mark.parametrize("campo", ["foo", "is_admin"])
def test_campo_a_mais(client, campo):
    r = client.post("/auth/login", json={"email": "a@t.com", "password": "x" * 10, campo: 1})
    assert _msg(r) == "O pedido traz um campo que não é aceito aqui."
