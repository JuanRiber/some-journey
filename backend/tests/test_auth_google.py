"""Entrar com o Google: vínculo por `sub`, e nunca uma segunda conta.

O risco inteiro deste fluxo cabe numa frase: se o login com Google criar um
cadastro novo para quem já tem conta, a pessoa entra num perfil vazio e acha
que perdeu as memórias. É o teste `vincula_em_vez_de_criar` que guarda isso.

O verificador do token é trocado por um dublê na maior parte dos casos —
assinar um JWT de mentira com a chave do Google não é possível, e o que está
sob teste aqui é a REGRA (quem vira quem), não a criptografia. A verificação
de verdade tem os seus próprios testes no fim do arquivo, nos dois pontos que
dá para exercitar sem o Google: desligado e token lixo.
"""

import uuid

import pytest

from app.core import google_oauth
from app.core.google_oauth import GoogleIdentity, InvalidGoogleToken
from app.models.user import User

PW = "Sup3rSecret!pw"


@pytest.fixture
def google(monkeypatch):
    """Faz o verificador devolver a identidade que o teste quiser."""

    def _configura(sub: str, email: str, name: str | None = "Pessoa"):
        monkeypatch.setattr(google_oauth, "enabled", lambda: True)
        monkeypatch.setattr(
            google_oauth,
            "verify",
            lambda _t: GoogleIdentity(sub=sub, email=email.lower(), name=name),
        )

    return _configura


def _email():
    return f"g_{uuid.uuid4().hex[:10]}@t.com"


def _entrar(client, token="qualquer"):
    return client.post("/auth/google", json={"id_token": token})


def test_primeira_vez_cria_a_conta(client, db_session, google):
    email = _email()
    google(sub="sub-1", email=email)

    r = _entrar(client)

    assert r.status_code == 200, r.text
    assert r.json()["access_token"]
    user = db_session.query(User).filter(User.email == email).one()
    assert user.google_sub == "sub-1"
    # Quem entrou pelo Google nunca definiu senha — e a coluna diz a verdade
    # sobre isso em vez de guardar um hash inventado.
    assert user.password_hash is None


def test_segunda_vez_entra_na_mesma_conta(client, db_session, google):
    email = _email()
    google(sub="sub-2", email=email)

    _entrar(client)
    _entrar(client)

    assert db_session.query(User).filter(User.email == email).count() == 1


def test_vincula_em_vez_de_criar_uma_segunda_conta(client, db_session, google):
    # O caso que estraga a vida de quem já usava o produto: cadastro antigo
    # por e-mail e senha, e um dia a pessoa toca em "entrar com Google".
    email = _email()
    client.post("/auth/register", json={"name": "Antigo", "email": email, "password": PW})
    antigo = db_session.query(User).filter(User.email == email).one()
    assert antigo.google_sub is None

    google(sub="sub-3", email=email)
    r = _entrar(client)

    assert r.status_code == 200, r.text
    assert db_session.query(User).filter(User.email == email).count() == 1
    db_session.refresh(antigo)
    assert antigo.google_sub == "sub-3"
    # A senha continua valendo: vincular não pode derrubar a porta antiga.
    assert client.post("/auth/login", json={"email": email, "password": PW}).status_code == 200


def test_o_vinculo_e_pelo_sub_e_nao_pelo_email(client, db_session, google):
    # O e-mail de uma conta Google pode mudar. Se o vínculo fosse por e-mail,
    # a pessoa voltaria como estranha e perderia o acesso ao que é dela.
    email_antigo, email_novo = _email(), _email()
    google(sub="sub-4", email=email_antigo)
    _entrar(client)

    google(sub="sub-4", email=email_novo)
    r = _entrar(client)

    assert r.status_code == 200, r.text
    user = db_session.query(User).filter(User.google_sub == "sub-4").one()
    assert user.email == email_antigo, "trocar de e-mail no Google não cria outra conta"
    assert db_session.query(User).filter(User.email == email_novo).count() == 0


def test_conta_inativa_nao_entra(client, db_session, google):
    email = _email()
    google(sub="sub-5", email=email)
    _entrar(client)
    user = db_session.query(User).filter(User.email == email).one()
    user.is_active = False
    db_session.commit()

    assert _entrar(client).status_code == 403


def test_senha_nao_abre_conta_que_so_tem_google(client, google):
    # E a recusa é a mensagem GENÉRICA: responder "esta conta usa Google"
    # confirmaria que o e-mail existe, que é o que todo o resto deste fluxo
    # evita.
    email = _email()
    google(sub="sub-6", email=email)
    _entrar(client)

    r = client.post("/auth/login", json={"email": email, "password": PW})

    assert r.status_code == 401
    assert "Google" not in r.json()["detail"]


def test_token_recusado_vira_401(client, monkeypatch):
    monkeypatch.setattr(google_oauth, "enabled", lambda: True)

    def _recusa(_t):
        raise InvalidGoogleToken("unverified email")

    monkeypatch.setattr(google_oauth, "verify", _recusa)
    assert _entrar(client).status_code == 401


def test_sem_configuracao_a_rota_diz_que_nao_esta_ligada(client, monkeypatch):
    # 503, não 401: o recurso não existe neste ambiente. Responder "token
    # inválido" mandaria alguém depurar o Google quando o que falta é uma
    # variável de ambiente.
    monkeypatch.setattr(google_oauth.settings, "GOOGLE_CLIENT_ID", None)
    r = _entrar(client)
    assert r.status_code == 503
    assert "not configured" in r.json()["detail"]


def test_corpo_com_campo_extra_e_recusado(client):
    r = client.post("/auth/google", json={"id_token": "x", "email": "eu@t.com"})
    assert r.status_code == 422, "o cliente não dita quem ele é; só o token vale"


class TestVerificacaoDeVerdade:
    """Os dois pontos do verificador real que dá para exercitar sem o Google."""

    def test_desligado_levanta_em_vez_de_aceitar(self, monkeypatch):
        monkeypatch.setattr(google_oauth.settings, "GOOGLE_CLIENT_ID", None)
        with pytest.raises(google_oauth.GoogleNotConfigured):
            google_oauth.verify("qualquer.coisa.aqui")

    def test_token_lixo_nao_passa(self, monkeypatch):
        monkeypatch.setattr(google_oauth.settings, "GOOGLE_CLIENT_ID", "cliente.apps.googleusercontent.com")
        with pytest.raises(InvalidGoogleToken):
            google_oauth.verify("isto.nao.e.um.jwt")

    def test_token_vazio_nao_chega_a_rede(self, monkeypatch):
        monkeypatch.setattr(google_oauth.settings, "GOOGLE_CLIENT_ID", "cliente.apps.googleusercontent.com")
        with pytest.raises(InvalidGoogleToken):
            google_oauth.verify("")
