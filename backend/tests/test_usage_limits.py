"""Teto de uso por pessoa: escritas e uploads de quem já está logado.

O limite de tentativas cobria só o login. Aqui o que se prende é o outro
lado: que um laço de escritas para num teto, que o teto é POR PESSOA (uma não
gasta o da outra), que leitura nunca conta, e que os uploads têm um balde
próprio, mais apertado.
"""

import pytest

from app.core import storage
from app.core.config import settings
from tests._images import JPEG

_MEMORIA = {
    "text": "x",
    "latitude": -3.73,
    "longitude": -38.52,
    "occurred_at": "2026-05-01T12:00:00Z",
}


@pytest.fixture()
def cofre(monkeypatch):
    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "upload", lambda *a, **k: None)
    monkeypatch.setattr(storage, "delete", lambda *a, **k: None)
    monkeypatch.setattr(storage, "sign_url", lambda path, ttl=None: f"https://s/{path}")
    monkeypatch.setattr(
        storage, "sign_urls", lambda paths, ttl=None: {p: f"https://s/{p}" for p in paths}
    )


def test_os_tetos_padrao_ficam_longe_do_uso_normal():
    """Uma gravação de percurso sobe uns 15 lotes em cinco minutos; salvar uma
    memória com cinco fotos são seis pedidos. O teto não pode morar perto."""
    assert settings.WRITE_RATE_LIMIT_ATTEMPTS >= 300
    assert settings.UPLOAD_RATE_LIMIT_ATTEMPTS >= 30
    assert settings.UPLOAD_RATE_LIMIT_ATTEMPTS < settings.WRITE_RATE_LIMIT_ATTEMPTS


def test_um_laco_de_escritas_para_no_teto(client, auth_headers, monkeypatch):
    monkeypatch.setattr(settings, "WRITE_RATE_LIMIT_ATTEMPTS", 3)
    h = auth_headers()

    respostas = [
        client.post("/memories", headers=h, json=_MEMORIA).status_code for _ in range(5)
    ]

    assert respostas == [201, 201, 201, 429, 429]


def test_o_429_diz_quanto_esperar_e_fala_portugues(client, auth_headers, monkeypatch):
    monkeypatch.setattr(settings, "WRITE_RATE_LIMIT_ATTEMPTS", 1)
    h = auth_headers()
    client.post("/memories", headers=h, json=_MEMORIA)

    r = client.post("/memories", headers=h, json=_MEMORIA)

    assert r.status_code == 429
    assert 1 <= int(r.headers["Retry-After"]) <= settings.USAGE_RATE_LIMIT_WINDOW_SECONDS
    assert r.json()["detail"].startswith("Muitas alterações em pouco tempo.")


def test_o_teto_e_por_pessoa(client, auth_headers, monkeypatch):
    monkeypatch.setattr(settings, "WRITE_RATE_LIMIT_ATTEMPTS", 2)
    ana, bia = auth_headers(), auth_headers()
    for _ in range(3):
        client.post("/memories", headers=ana, json=_MEMORIA)

    assert client.post("/memories", headers=ana, json=_MEMORIA).status_code == 429
    assert client.post("/memories", headers=bia, json=_MEMORIA).status_code == 201


def test_leitura_nunca_conta_nem_e_barrada(client, auth_headers, monkeypatch):
    monkeypatch.setattr(settings, "WRITE_RATE_LIMIT_ATTEMPTS", 1)
    h = auth_headers()
    client.post("/memories", headers=h, json=_MEMORIA)
    assert client.post("/memories", headers=h, json=_MEMORIA).status_code == 429

    for rota in ("/memories", "/journeys", "/life-phases", "/me/profile", "/map"):
        for _ in range(3):
            assert client.get(rota, headers=h).status_code == 200, rota


@pytest.mark.parametrize(
    ("metodo", "rota", "corpo"),
    [
        ("post", "/journeys", {"title": "Litoral"}),
        ("post", "/life-phases", {"name": "Faculdade"}),
        ("patch", "/me/profile", {"bio": "oi"}),
        ("delete", "/me/avatar", None),
    ],
)
def test_todo_router_de_conteudo_conta_no_mesmo_balde(
    client, auth_headers, monkeypatch, metodo, rota, corpo
):
    monkeypatch.setattr(settings, "WRITE_RATE_LIMIT_ATTEMPTS", 1)
    h = auth_headers()
    client.post("/memories", headers=h, json=_MEMORIA)  # gasta o teto

    r = getattr(client, metodo)(rota, headers=h, **({"json": corpo} if corpo else {}))

    assert r.status_code == 429, f"{metodo.upper()} {rota} escapou do teto"


def test_envio_de_pontos_de_gps_conta_como_escrita(client, auth_headers, monkeypatch):
    h = auth_headers()
    jid = client.post("/journeys", headers=h, json={"title": "Trilha"}).json()["id"]
    client.post(f"/journeys/{jid}/start", headers=h)
    tid = client.post(
        f"/journeys/{jid}/tracks/start", headers=h, json={"source": "gps_live"}
    ).json()["id"]
    monkeypatch.setattr(settings, "WRITE_RATE_LIMIT_ATTEMPTS", 4)
    lote = {
        "points": [
            {"latitude": -3.7, "longitude": -38.5, "recorded_at": "2026-05-01T12:00:00Z"}
        ]
    }

    respostas = [
        client.post(
            f"/journeys/{jid}/tracks/{tid}/points", headers=h, json=lote
        ).status_code
        for _ in range(3)
    ]

    # Três escritas antes (jornada, start, trecho) + a primeira de pontos = 4.
    assert respostas == [200, 429, 429]


def test_uploads_tem_balde_proprio_mais_apertado(
    client, auth_headers, monkeypatch, cofre
):
    monkeypatch.setattr(settings, "UPLOAD_RATE_LIMIT_ATTEMPTS", 2)
    h = auth_headers()
    mid = client.post("/memories", headers=h, json=_MEMORIA).json()["id"]

    respostas = [
        client.post(
            f"/memories/{mid}/images",
            headers=h,
            files={"file": ("f.jpg", JPEG, "image/jpeg")},
        ).status_code
        for _ in range(3)
    ]

    assert respostas == [200, 200, 429]
    # O teto de upload não trava as outras escritas.
    assert client.post("/memories", headers=h, json=_MEMORIA).status_code == 201


def test_avatar_e_capa_gastam_o_mesmo_balde_de_upload(
    client, auth_headers, monkeypatch, cofre
):
    monkeypatch.setattr(settings, "UPLOAD_RATE_LIMIT_ATTEMPTS", 2)
    h = auth_headers()
    jid = client.post("/journeys", headers=h, json={"title": "Litoral"}).json()["id"]
    arquivo = {"file": ("f.jpg", JPEG, "image/jpeg")}

    assert client.post("/me/avatar", headers=h, files=arquivo).status_code == 200
    assert client.post(f"/journeys/{jid}/cover", headers=h, files=arquivo).status_code == 200
    assert client.post("/me/avatar", headers=h, files=arquivo).status_code == 429


def test_sem_sessao_continua_sendo_401_e_nao_gasta_teto_de_ninguem(client, db_session):
    from sqlalchemy import text

    r = client.post("/memories", json=_MEMORIA)

    assert r.status_code == 401
    assert (
        db_session.execute(text("SELECT count(*) FROM auth_rate_limits")).scalar_one() == 0
    )


def test_as_rotas_de_conta_nao_entram_neste_teto(client, auth_headers, monkeypatch):
    """Login, troca de senha e exclusão têm os limites deles (por conta, IP e
    e-mail); o teto de uso é do conteúdo."""
    monkeypatch.setattr(settings, "WRITE_RATE_LIMIT_ATTEMPTS", 1)
    h = auth_headers()
    client.post("/memories", headers=h, json=_MEMORIA)

    r = client.post(
        "/auth/change-password",
        headers=h,
        json={"current_password": "errada", "new_password": "OutraSenha123"},
    )

    assert r.status_code == 401
