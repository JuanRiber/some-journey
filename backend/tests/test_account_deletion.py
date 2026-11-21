"""Excluir a conta: POST /auth/delete-account.

O que estes testes prendem, na ordem em que importa: que NADA da pessoa fica
(nem linha, nem caminho de arquivo sem registro), que ninguém mais é tocado, e
que só a própria pessoa consegue pedir — um token de sessão sozinho não basta
para uma conta com senha.
"""

import uuid

import pytest
from sqlalchemy import func, select, text

from app.core import storage
from app.models.file_deletion import PendingFileDeletion
from app.models.journey import Journey
from app.models.memory import Memory, MemoryImage
from app.models.user import User

PW = "Sup3rSecret!pw"

# Toda tabela que guarda algo de uma pessoa. Se uma nova nascer sem entrar
# aqui, o teste de "não sobra nada" continua passando sem conferi-la — por isso
# `test_a_lista_de_tabelas_esta_completa` cobra a lista contra o metadata.
_TABELAS_DA_PESSOA = (
    "users",
    "memories",
    "memory_images",
    "memory_music",
    "journeys",
    "journey_memories",
    "journey_tracks",
    "journey_track_points",
    "life_phases",
    "password_reset_tokens",
    "refresh_tokens",
)
_TABELAS_SEM_DONO = ("auth_rate_limits", "pending_file_deletions")


@pytest.fixture()
def cofre(monkeypatch):
    """Um Storage de mentira que registra o que foi mandado apagar."""

    class Cofre:
        removidos: list[str] = []
        responde = True

    c = Cofre()
    c.removidos = []
    monkeypatch.setattr(storage, "enabled", lambda: True)

    def remove(path: str) -> bool:
        if c.responde:
            c.removidos.append(path)
        return c.responde

    monkeypatch.setattr(storage, "remove", remove)
    monkeypatch.setattr(storage, "sign_url", lambda path, ttl=None: f"https://s/{path}")
    monkeypatch.setattr(storage, "sign_urls", lambda paths, ttl=None: {})
    return c


def _conta(client, email: str | None = None) -> tuple[str, dict[str, str], str]:
    """Cadastra e entra. Devolve (email, headers, refresh_token)."""
    email = email or f"d_{uuid.uuid4().hex[:10]}@test.com"
    client.post("/auth/register", json={"name": "T", "email": email, "password": PW})
    sessao = client.post("/auth/login", json={"email": email, "password": PW}).json()
    return email, {"Authorization": f"Bearer {sessao['access_token']}"}, sessao[
        "refresh_token"
    ]


def _encher(client, db_session, headers) -> dict[str, str]:
    """Dá à conta um pouco de tudo, incluindo três arquivos no Storage."""
    memoria = client.post(
        "/memories",
        headers=headers,
        json={
            "title": "Praia",
            "text": "x",
            "latitude": -3.73,
            "longitude": -38.52,
            "occurred_at": "2026-05-01T12:00:00Z",
        },
    ).json()
    apagada = client.post(
        "/memories",
        headers=headers,
        json={
            "text": "y",
            "latitude": -3.7,
            "longitude": -38.5,
            "occurred_at": "2026-05-02T12:00:00Z",
        },
    ).json()
    client.delete(f"/memories/{apagada['id']}", headers=headers)
    jornada = client.post(
        "/journeys", headers=headers, json={"title": "Litoral"}
    ).json()
    client.post(f"/journeys/{jornada['id']}/start", headers=headers)
    client.post(
        f"/journeys/{jornada['id']}/points",
        headers=headers,
        json={"memory_id": memoria["id"]},
    )
    trecho = client.post(
        f"/journeys/{jornada['id']}/tracks/start",
        headers=headers,
        json={"source": "gps_live"},
    ).json()
    client.post(
        f"/journeys/{jornada['id']}/tracks/{trecho['id']}/points",
        headers=headers,
        json={
            "points": [
                {
                    "latitude": -3.73,
                    "longitude": -38.52,
                    "recorded_at": "2026-05-01T12:00:00Z",
                }
            ]
        },
    )
    client.post("/life-phases", headers=headers, json={"name": "Faculdade"})
    client.post(
        f"/memories/{memoria['id']}/music",
        headers=headers,
        json={
            "provider": "itunes",
            "external_id": "1440857781",
            "title": "Sozinho",
            "artist": "Caetano Veloso",
        },
    )
    client.post("/auth/forgot-password", json={"email": _email_de(db_session, headers)})

    caminhos = {
        "foto": f"memories/{memoria['id']}/a.jpg",
        "foto_da_apagada": f"memories/{apagada['id']}/b.jpg",
        "capa": f"journeys/{jornada['id']}/cover.jpg",
        "avatar": f"avatars/{uuid.uuid4().hex}.jpg",
    }
    db_session.add_all(
        [
            MemoryImage(
                memory_id=uuid.UUID(memoria["id"]),
                image_path=caminhos["foto"],
                position=1,
            ),
            MemoryImage(
                memory_id=uuid.UUID(apagada["id"]),
                image_path=caminhos["foto_da_apagada"],
                position=1,
            ),
        ]
    )
    db_session.execute(
        text("UPDATE journeys SET cover_image_path = :p WHERE id = :id"),
        {"p": caminhos["capa"], "id": jornada["id"]},
    )
    db_session.execute(
        text("UPDATE users SET avatar_path = :p WHERE email = :e"),
        {"p": caminhos["avatar"], "e": _email_de(db_session, headers)},
    )
    db_session.commit()
    return caminhos


_EMAILS: dict[str, str] = {}


def _email_de(db_session, headers) -> str:
    return _EMAILS[headers["Authorization"]]


def _excluir(client, headers, email, password=PW):
    corpo = {"email": email}
    if password is not None:
        corpo["password"] = password
    return client.post("/auth/delete-account", headers=headers, json=corpo)


def _contagens(db_session) -> dict[str, int]:
    return {
        t: db_session.execute(text(f"SELECT count(*) FROM {t}")).scalar_one()
        for t in _TABELAS_DA_PESSOA
    }


@pytest.fixture()
def conta_cheia(client, db_session, cofre):
    email, headers, refresh = _conta(client)
    _EMAILS[headers["Authorization"]] = email
    caminhos = _encher(client, db_session, headers)
    return email, headers, refresh, caminhos


# --- o que sai --------------------------------------------------------------


def test_a_lista_de_tabelas_esta_completa():
    from app.db.base import Base

    assert set(Base.metadata.tables) == set(_TABELAS_DA_PESSOA) | set(
        _TABELAS_SEM_DONO
    ), "tabela nova: decida se ela guarda dado de pessoa e acrescente na lista"


def test_excluir_a_conta_nao_deixa_linha_nenhuma(client, db_session, conta_cheia):
    email, headers, _, _ = conta_cheia
    antes = _contagens(db_session)
    assert all(n > 0 for n in antes.values()), f"a conta de teste está rala: {antes}"

    r = _excluir(client, headers, email)

    assert r.status_code == 204, r.text
    assert _contagens(db_session) == dict.fromkeys(_TABELAS_DA_PESSOA, 0)


def test_os_arquivos_saem_do_storage_inclusive_os_da_memoria_ja_apagada(
    client, db_session, cofre, conta_cheia
):
    email, headers, _, caminhos = conta_cheia

    _excluir(client, headers, email)

    assert set(cofre.removidos) == set(caminhos.values())
    assert db_session.scalar(select(func.count()).select_from(PendingFileDeletion)) == 0


def test_storage_fora_do_ar_nao_perde_o_caminho_de_nenhum_arquivo(
    client, db_session, cofre, conta_cheia
):
    """A conta sai do mesmo jeito; os arquivos ficam na fila, com o caminho."""
    email, headers, _, caminhos = conta_cheia
    cofre.responde = False

    r = _excluir(client, headers, email)

    assert r.status_code == 204
    assert db_session.scalar(select(func.count()).select_from(User)) == 0
    na_fila = db_session.scalars(select(PendingFileDeletion)).all()
    assert {f.path for f in na_fila} == set(caminhos.values())
    assert all(f.attempts == 1 for f in na_fila)


def test_as_sessoes_morrem_com_a_conta(client, conta_cheia):
    email, headers, refresh, _ = conta_cheia

    _excluir(client, headers, email)

    assert client.get("/auth/me", headers=headers).status_code == 401
    assert (
        client.post("/auth/refresh", json={"refresh_token": refresh}).status_code == 401
    )
    assert (
        client.post("/auth/login", json={"email": email, "password": PW}).status_code
        == 401
    )


def test_o_email_fica_livre_para_um_cadastro_novo_e_vazio(client, conta_cheia):
    email, headers, _, _ = conta_cheia
    _excluir(client, headers, email)

    _, novos, _ = _conta(client, email)

    assert client.get("/memories", headers=novos).json() == []
    assert client.get("/journeys", headers=novos).json() == []


def test_a_conta_do_vizinho_nao_e_tocada(client, db_session, cofre, conta_cheia):
    email, headers, _, caminhos = conta_cheia
    _, vizinho, refresh_vizinho = _conta(client)
    memoria = client.post(
        "/memories",
        headers=vizinho,
        json={
            "text": "do vizinho",
            "latitude": 1,
            "longitude": 1,
            "occurred_at": "2026-05-01T12:00:00Z",
        },
    ).json()
    db_session.add(
        MemoryImage(
            memory_id=uuid.UUID(memoria["id"]), image_path="vizinho.jpg", position=1
        )
    )
    db_session.commit()

    _excluir(client, headers, email)

    assert "vizinho.jpg" not in cofre.removidos
    assert [m["id"] for m in client.get("/memories", headers=vizinho).json()] == [
        memoria["id"]
    ]
    assert db_session.scalar(select(func.count()).select_from(MemoryImage)) == 1
    assert (
        client.post("/auth/refresh", json={"refresh_token": refresh_vizinho}).status_code
        == 200
    )


# --- quem pode pedir --------------------------------------------------------


def test_sem_sessao_nao_exclui_nada(client, db_session, conta_cheia):
    email, _, _, _ = conta_cheia

    r = client.post("/auth/delete-account", json={"email": email, "password": PW})

    assert r.status_code == 401
    assert db_session.scalar(select(func.count()).select_from(User)) == 1


def test_senha_errada_nao_exclui_e_o_401_nao_e_de_sessao(
    client, db_session, conta_cheia
):
    email, headers, _, _ = conta_cheia

    r = _excluir(client, headers, email, password="nao-e-esta")

    assert r.status_code == 401
    assert r.json()["detail"] == "A senha está incorreta."
    assert "WWW-Authenticate" not in r.headers, "o app renovaria a sessão à toa"
    assert db_session.scalar(select(func.count()).select_from(Memory)) == 2


def test_token_de_sessao_sozinho_nao_apaga_conta_com_senha(
    client, db_session, conta_cheia
):
    """É o caso do token copiado: tem a sessão, não tem a senha."""
    email, headers, _, _ = conta_cheia

    r = _excluir(client, headers, email, password=None)

    assert r.status_code == 401
    assert db_session.scalar(select(func.count()).select_from(User)) == 1


def test_email_que_nao_e_o_da_conta_e_recusado(client, db_session, conta_cheia):
    _, headers, _, _ = conta_cheia

    r = _excluir(client, headers, "outra@test.com")

    assert r.status_code == 400
    assert r.json()["detail"] == "O e-mail digitado não é o desta conta."
    assert db_session.scalar(select(func.count()).select_from(User)) == 1


def test_o_email_digitado_vale_com_maiusculas_e_espacos(client, db_session, conta_cheia):
    email, headers, _, _ = conta_cheia

    r = _excluir(client, headers, f"  {email.upper()} ")

    assert r.status_code == 204


def test_conta_que_so_entra_pelo_google_exclui_sem_senha(client, db_session, cofre):
    email, headers, _ = _conta(client)
    db_session.execute(
        text("UPDATE users SET password_hash = NULL, google_sub = 'g-1' WHERE email = :e"),
        {"e": email},
    )
    db_session.commit()

    r = _excluir(client, headers, email, password=None)

    assert r.status_code == 204
    assert db_session.scalar(select(func.count()).select_from(User)) == 0


def test_o_perfil_diz_se_a_conta_tem_senha(client, db_session, cofre):
    email, headers, _ = _conta(client)
    assert client.get("/me/profile", headers=headers).json()["identity"][
        "has_password"
    ] is True

    db_session.execute(
        text("UPDATE users SET password_hash = NULL, google_sub = 'g-2' WHERE email = :e"),
        {"e": email},
    )
    db_session.commit()

    assert client.get("/me/profile", headers=headers).json()["identity"][
        "has_password"
    ] is False


def test_campo_a_mais_no_corpo_e_recusado(client, conta_cheia):
    email, headers, _, _ = conta_cheia
    r = client.post(
        "/auth/delete-account",
        headers=headers,
        json={"email": email, "password": PW, "user_id": str(uuid.uuid4())},
    )
    assert r.status_code == 422


def test_tentativas_de_senha_tem_limite_proprio(client, monkeypatch, conta_cheia):
    from app.core.config import settings

    monkeypatch.setattr(settings, "AUTH_RATE_LIMIT_ATTEMPTS", 2)
    email, headers, _, _ = conta_cheia

    respostas = [
        _excluir(client, headers, email, password="errada").status_code
        for _ in range(3)
    ]

    assert respostas == [401, 401, 429]
    # O teto da exclusão não gasta o da troca de senha.
    r = client.post(
        "/auth/change-password",
        headers=headers,
        json={"current_password": "errada", "new_password": "OutraSenha123"},
    )
    assert r.status_code == 401


def test_a_jornada_do_teste_tinha_capa(db_session, conta_cheia):
    """Guarda do próprio arranjo: se a capa não foi gravada, o teste dos
    arquivos passaria conferindo um arquivo a menos."""
    assert db_session.scalar(
        select(func.count()).select_from(Journey).where(
            Journey.cover_image_path.is_not(None)
        )
    ) == 1
