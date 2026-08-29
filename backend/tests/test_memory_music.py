"""Música da memória (POST /memories/{id}/music e DELETE .../music/{music_id}).

A canção que estava tocando é parte da lembrança. O app já sabia buscar faixas
desde julho — o `MusicProvider` e o adapter do iTunes existem — e não tinha onde
guardá-las: dava para achar a música e não para salvá-la.

O que estes testes travam:

- **O snapshot.** A API não consulta catálogo nenhum; ela recebe e guarda o que
  o app obteve. Título e artista ficam gravados, para a lembrança sobreviver ao
  dia em que a faixa sair do ar.
- **Uma faixa não entra duas vezes** na mesma memória — a regra que o
  `MusicTrack` do app expressa no `operator ==` e que agora o banco garante.
- **Ownership**, com o mesmo 404 do resto da API para inexistente e de terceiro.
"""

import uuid


def _memory(client, headers, title="Praia de Iracema"):
    r = client.post(
        "/memories",
        json={
            "title": title,
            "text": "O fim de tarde daqui.",
            "latitude": -3.72,
            "longitude": -38.51,
            "occurred_at": "2026-08-28T21:30:00Z",
        },
        headers=headers,
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _faixa(**over):
    base = {
        "provider": "itunes",
        "external_id": "1440857781",
        "title": "Sozinho",
        "artist": "Caetano Veloso",
        "album": "Prenda Minha",
        "artwork_url": "https://example.com/capa.jpg",
        "preview_url": "https://example.com/preview.m4a",
        "external_url": "https://music.apple.com/br/album/1440857781",
        "duration_ms": 222_000,
    }
    base.update(over)
    return base


class TestAnexar:
    def test_a_faixa_fica_gravada_na_memoria(self, client, auth_headers):
        h = auth_headers()
        mid = _memory(client, h)

        r = client.post(f"/memories/{mid}/music", json=_faixa(), headers=h)

        assert r.status_code == 201, r.text
        music = r.json()["music"]
        assert len(music) == 1
        assert music[0]["title"] == "Sozinho"
        assert music[0]["artist"] == "Caetano Veloso"
        assert music[0]["album"] == "Prenda Minha"
        assert music[0]["duration_ms"] == 222_000

    def test_guarda_a_origem_para_reabrir_depois(self, client, auth_headers):
        h = auth_headers()
        mid = _memory(client, h)
        r = client.post(f"/memories/{mid}/music", json=_faixa(), headers=h)

        faixa = r.json()["music"][0]
        assert faixa["provider"] == "itunes"
        assert faixa["external_id"] == "1440857781"
        assert faixa["external_url"].startswith("https://music.apple.com/")

    def test_a_faixa_viaja_junto_da_memoria(self, client, auth_headers):
        h = auth_headers()
        """Quem abre a lembrança vê a música com ela, sem segunda requisição."""
        mid = _memory(client, h)
        client.post(f"/memories/{mid}/music", json=_faixa(), headers=h)

        detalhe = client.get(f"/memories/{mid}", headers=h).json()
        assert [f["title"] for f in detalhe["music"]] == ["Sozinho"]

        listagem = client.get("/memories", headers=h).json()
        assert [f["title"] for f in listagem[0]["music"]] == ["Sozinho"]

    def test_so_titulo_e_artista_bastam(self, client, auth_headers):
        h = auth_headers()
        """O resto é enfeite do provedor: um catálogo pobre não impede guardar."""
        mid = _memory(client, h)
        r = client.post(
            f"/memories/{mid}/music",
            json={"external_id": "1", "title": "Asa Branca", "artist": "Luiz Gonzaga"},
            headers=h,
        )
        assert r.status_code == 201, r.text
        faixa = r.json()["music"][0]
        assert faixa["album"] is None
        assert faixa["provider"] == "itunes", "o provedor padrão é o implementado"

    def test_varias_faixas_convivem_na_ordem_em_que_entraram(self, client, auth_headers):
        h = auth_headers()
        mid = _memory(client, h)
        for i, titulo in enumerate(["Primeira", "Segunda", "Terceira"]):
            client.post(
                f"/memories/{mid}/music",
                json=_faixa(external_id=str(i), title=titulo),
                headers=h,
            )

        detalhe = client.get(f"/memories/{mid}", headers=h).json()
        assert [f["title"] for f in detalhe["music"]] == ["Primeira", "Segunda", "Terceira"]


class TestAMesmaFaixaNaoEntraDuasVezes:
    def test_repetir_a_mesma_faixa_e_409(self, client, auth_headers):
        h = auth_headers()
        mid = _memory(client, h)
        client.post(f"/memories/{mid}/music", json=_faixa(), headers=h)

        r = client.post(f"/memories/{mid}/music", json=_faixa(), headers=h)

        assert r.status_code == 409
        detalhe = client.get(f"/memories/{mid}", headers=h).json()
        assert len(detalhe["music"]) == 1, "a segunda tentativa não pode duplicar"

    def test_o_mesmo_id_em_provedor_diferente_e_outra_faixa(self, client, auth_headers):
        h = auth_headers()
        mid = _memory(client, h)
        client.post(f"/memories/{mid}/music", json=_faixa(), headers=h)

        r = client.post(
            f"/memories/{mid}/music",
            json=_faixa(provider="spotify"),
            headers=h,
        )

        assert r.status_code == 201, "ids são do provedor; um não colide com o outro"

    def test_a_mesma_faixa_em_outra_memoria_e_permitida(self, client, auth_headers):
        h = auth_headers()
        """A mesma canção pode marcar dois momentos diferentes."""
        a = _memory(client, h, "Iracema")
        b = _memory(client, h, "Mucuripe")
        client.post(f"/memories/{a}/music", json=_faixa(), headers=h)

        r = client.post(f"/memories/{b}/music", json=_faixa(), headers=h)
        assert r.status_code == 201

    def test_remover_e_reanexar_a_mesma_faixa_funciona(self, client, auth_headers):
        h = auth_headers()
        """O índice é parcial: uma faixa removida não bloqueia a volta dela."""
        mid = _memory(client, h)
        r = client.post(f"/memories/{mid}/music", json=_faixa(), headers=h)
        fid = r.json()["music"][0]["id"]
        client.delete(f"/memories/{mid}/music/{fid}", headers=h)

        r = client.post(f"/memories/{mid}/music", json=_faixa(), headers=h)
        assert r.status_code == 201


class TestTeto:
    def test_acima_do_teto_responde_409(self, client, auth_headers):
        h = auth_headers()
        """Uma lembrança tem trilha, não playlist."""
        mid = _memory(client, h)
        for i in range(5):
            r = client.post(
                f"/memories/{mid}/music",
                json=_faixa(external_id=f"faixa-{i}"),
                headers=h,
            )
            assert r.status_code == 201, r.text

        r = client.post(
            f"/memories/{mid}/music",
            json=_faixa(external_id="a-sexta"),
            headers=h,
        )
        assert r.status_code == 409


class TestRemover:
    def test_remove_a_faixa_e_mantem_a_memoria(self, client, auth_headers):
        h = auth_headers()
        mid = _memory(client, h)
        r = client.post(f"/memories/{mid}/music", json=_faixa(), headers=h)
        fid = r.json()["music"][0]["id"]

        r = client.delete(f"/memories/{mid}/music/{fid}", headers=h)

        assert r.status_code == 200
        assert r.json()["music"] == []
        assert r.json()["title"] == "Praia de Iracema", "a memória continua inteira"

    def test_faixa_inexistente_e_404(self, client, auth_headers):
        h = auth_headers()
        mid = _memory(client, h)
        r = client.delete(
            f"/memories/{mid}/music/{uuid.uuid4()}", headers=h
        )
        assert r.status_code == 404


class TestOwnership:
    def test_memoria_de_outro_usuario_e_404_ao_anexar(self, client, auth_headers):
        h = auth_headers()
        dono = auth_headers()
        intruso = auth_headers()
        alheia = _memory(client, dono)
        r = client.post(
            f"/memories/{alheia}/music", json=_faixa(), headers=intruso
        )
        assert r.status_code == 404, "mesmo 404 de inexistente — anti-enumeração"

    def test_memoria_inexistente_e_404(self, client, auth_headers):
        h = auth_headers()
        r = client.post(
            f"/memories/{uuid.uuid4()}/music", json=_faixa(), headers=h
        )
        assert r.status_code == 404

    def test_sem_token_e_401(self, client, auth_headers):
        h = auth_headers()
        mid = _memory(client, h)
        r = client.post(f"/memories/{mid}/music", json=_faixa())
        assert r.status_code in (401, 403)


class TestPerfil:
    def test_o_cartao_do_viajante_conta_as_faixas(self, client, auth_headers):
        h = auth_headers()
        mid = _memory(client, h)
        for i in range(3):
            client.post(
                f"/memories/{mid}/music",
                json=_faixa(external_id=f"t{i}"),
                headers=h,
            )

        stats = client.get("/me/profile", headers=h).json()["stats"]
        assert stats["tracks"] == 3

    def test_faixa_removida_sai_da_contagem(self, client, auth_headers):
        h = auth_headers()
        mid = _memory(client, h)
        r = client.post(f"/memories/{mid}/music", json=_faixa(), headers=h)
        fid = r.json()["music"][0]["id"]
        client.delete(f"/memories/{mid}/music/{fid}", headers=h)

        stats = client.get("/me/profile", headers=h).json()["stats"]
        assert stats["tracks"] == 0
