"""@username e avatar: regras de domínio, unicidade sem caixa e a escrita."""

import pytest

from app.core import storage
from app.domain.username import InvalidUsernameError, normalize, validate
from app.services import profile_service

# JPEG real (magic bytes FF D8 FF) — o tipo vem dos BYTES, não do cabeçalho.
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 20


class TestRegrasDoUsername:
    def test_normaliza_caixa_e_espacos(self):
        assert normalize("  Juan  ") == "juan"

    @pytest.mark.parametrize("value", ["juan", "juan_pedro", "j1234", "a" * 30])
    def test_aceita_validos(self, value):
        assert validate(value) == value.lower()

    @pytest.mark.parametrize(
        "value",
        ["ab", "a" * 31, "1juan", "_juan", "juan.pedro", "juan-pedro", "juan pedro",
         "juão", "", "   "],
    )
    def test_recusa_invalidos(self, value):
        with pytest.raises(InvalidUsernameError):
            validate(value)

    @pytest.mark.parametrize("value", ["admin", "API", "me", "settings", "SomeJourney"])
    def test_recusa_reservados(self, value):
        """Colisão de rota e falsa identidade: bloquear agora custa nada."""
        with pytest.raises(InvalidUsernameError):
            validate(value)


class TestEdicaoDoPerfil:
    def test_define_username_e_bio(self, client, auth_headers):
        h = auth_headers()
        r = client.patch(
            "/me/profile", json={"username": "Juan_Pedro", "bio": "Cada lugar guarda uma história."},
            headers=h,
        )
        assert r.status_code == 200, r.text
        identity = r.json()["identity"]
        assert identity["username"] == "juan_pedro", "guardado na forma canônica"
        assert identity["bio"] == "Cada lugar guarda uma história."

    def test_edicao_e_parcial(self, client, auth_headers):
        h = auth_headers()
        client.patch("/me/profile", json={"username": "viajante1", "bio": "oi"}, headers=h)
        client.patch("/me/profile", json={"name": "Novo Nome"}, headers=h)
        identity = client.get("/me/profile", headers=h).json()["identity"]
        assert identity["name"] == "Novo Nome"
        assert identity["bio"] == "oi", "não enviar bio não a apaga"

    def test_username_invalido_vira_422_com_mensagem_util(self, client, auth_headers):
        r = client.patch("/me/profile", json={"username": "1abc"}, headers=auth_headers())
        assert r.status_code == 422
        assert "letra" in r.json()["detail"].lower()

    def test_username_reservado_e_recusado(self, client, auth_headers):
        r = client.patch("/me/profile", json={"username": "admin"}, headers=auth_headers())
        assert r.status_code == 422

    def test_username_duplicado_vira_409_ignorando_caixa(self, client, auth_headers):
        first = auth_headers()
        second = auth_headers()
        assert client.patch("/me/profile", json={"username": "explorador"},
                            headers=first).status_code == 200
        r = client.patch("/me/profile", json={"username": "EXPLORADOR"}, headers=second)
        assert r.status_code == 409

    def test_manter_o_proprio_username_nao_conflita(self, client, auth_headers):
        h = auth_headers()
        client.patch("/me/profile", json={"username": "mesmo"}, headers=h)
        assert client.patch("/me/profile", json={"username": "Mesmo"},
                            headers=h).status_code == 200

    def test_campo_desconhecido_falha_alto(self, client, auth_headers):
        """Fronteira de escrita de conta: extra=forbid (sondagem não passa)."""
        r = client.patch("/me/profile", json={"is_active": False}, headers=auth_headers())
        assert r.status_code == 422

    def test_exige_autenticacao(self, client):
        assert client.patch("/me/profile", json={"username": "x1234"}).status_code == 401


class TestAvatar:
    def test_sem_storage_configurado_responde_503(self, client, auth_headers):
        """Em teste o Supabase não está configurado — a rota é honesta sobre isso."""
        r = client.post("/me/avatar", files={"file": ("a.jpg", JPEG, "image/jpeg")},
                        headers=auth_headers())
        assert r.status_code == 503

    def test_arquivo_que_nao_e_imagem_e_recusado(self, client, auth_headers):
        r = client.post("/me/avatar", files={"file": ("a.jpg", b"nao-sou-imagem", "image/jpeg")},
                        headers=auth_headers())
        assert r.status_code == 400, "o tipo vem dos bytes, não do content-type"

    def test_arquivo_vazio_e_recusado(self, client, auth_headers):
        r = client.post("/me/avatar", files={"file": ("a.jpg", b"", "image/jpeg")},
                        headers=auth_headers())
        assert r.status_code == 400

    def test_upload_grava_o_caminho_e_devolve_o_perfil(self, client, auth_headers, monkeypatch):
        monkeypatch.setattr(storage, "enabled", lambda: True)
        monkeypatch.setattr(storage, "upload", lambda path, data, ct: None)
        monkeypatch.setattr(storage, "sign_urls", lambda paths, ttl=None: {
            p: f"https://signed/{p}" for p in paths
        })
        monkeypatch.setattr(storage, "sign_url", lambda path, ttl=None: f"https://signed/{path}")

        r = client.post("/me/avatar", files={"file": ("a.jpg", JPEG, "image/jpeg")},
                        headers=auth_headers())
        assert r.status_code == 200, r.text
        assert r.json()["identity"]["avatar_url"].startswith("https://signed/")

    def test_falha_no_banco_apaga_o_arquivo_recem_enviado(self, client, auth_headers, monkeypatch):
        """Compensação: nada de objeto órfão no bucket."""
        removed: list[str] = []
        monkeypatch.setattr(storage, "enabled", lambda: True)
        monkeypatch.setattr(storage, "upload", lambda path, data, ct: None)
        monkeypatch.setattr(storage, "delete", lambda path: removed.append(path))

        from app.repositories import user_repository

        def boom(*args, **kwargs):
            raise RuntimeError("banco fora")

        monkeypatch.setattr(user_repository, "set_avatar_path", boom)
        with pytest.raises(RuntimeError):
            client.post("/me/avatar", files={"file": ("a.jpg", JPEG, "image/jpeg")},
                        headers=auth_headers())
        assert removed, "o objeto enviado foi apagado"

    def test_remover_avatar_e_idempotente(self, client, auth_headers):
        h = auth_headers()
        assert client.delete("/me/avatar", headers=h).status_code == 200
        assert client.delete("/me/avatar", headers=h).status_code == 200
