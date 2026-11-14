"""Fases da vida: os capítulos que a pessoa reconhece na própria história.

O que estes testes guardam, antes de qualquer CRUD: que o produto NÃO impõe
estrutura. Não há fase predefinida, nada é obrigatório além do nome, o período
pode ficar em aberto dos dois lados, e fases podem se sobrepor — "vida adulta"
e "recomeços" convivem. Um teste que exigisse o contrário congelaria no código
uma taxonomia que o produto decidiu não ter.

E o que importa mais que tudo: apagar uma fase não pode levar memória junto.
A etiqueta é descartável; a lembrança não.
"""

import uuid
from datetime import UTC, datetime

from app.models.journey import Journey
from app.models.memory import Memory


def _criar(client, h, **campos):
    corpo = {"name": "Recomeços"} | campos
    return client.post("/life-phases", json=corpo, headers=h)


class TestCriar:
    def test_so_o_nome_basta(self, client, auth_headers):
        h = auth_headers()
        r = _criar(client, h)

        assert r.status_code == 201, r.text
        corpo = r.json()
        assert corpo["name"] == "Recomeços"
        # Sem período e sem descrição: a pessoa que não sabe quando a fase
        # começou ainda assim consegue nomeá-la.
        assert corpo["started_at"] is None and corpo["ended_at"] is None
        assert corpo["description"] is None
        assert corpo["color"] == "accent"

    def test_a_cor_vem_da_paleta_e_nao_de_um_hexadecimal(self, client, auth_headers):
        # Cor livre quebraria o contraste em um dos dois modos: o que é
        # legível no papel quente some no atlas noturno.
        h = auth_headers()
        assert _criar(client, h, color="moss").status_code == 201
        r = _criar(client, h, color="#FF00AA")
        assert r.status_code == 422
        assert "moss" in r.json()["detail"], "a mensagem diz quais valem"

    def test_terminar_antes_de_comecar_e_recusado(self, client, auth_headers):
        r = _criar(
            client,
            auth_headers(),
            started_at="2020-01-01T00:00:00Z",
            ended_at="2019-01-01T00:00:00Z",
        )
        assert r.status_code == 422

    def test_fase_em_curso_nao_precisa_de_fim(self, client, auth_headers):
        # Pedir data de fim para salvar seria pedir que a pessoa decretasse o
        # próprio presente no passado.
        r = _criar(client, auth_headers(), started_at="2024-03-01T00:00:00Z")
        assert r.status_code == 201
        assert r.json()["ended_at"] is None

    def test_fases_podem_se_sobrepor(self, client, auth_headers):
        # "Vida adulta" e "recomeços" convivem. Exigir períodos disjuntos
        # transformaria memória em planilha.
        h = auth_headers()
        janela = {"started_at": "2020-01-01T00:00:00Z", "ended_at": "2025-01-01T00:00:00Z"}
        assert _criar(client, h, name="Vida adulta", **janela).status_code == 201
        assert _criar(client, h, name="Recomeços", **janela).status_code == 201

    def test_campo_desconhecido_e_recusado(self, client, auth_headers):
        r = client.post(
            "/life-phases",
            json={"name": "X", "cor_favorita": "azul"},
            headers=auth_headers(),
        )
        assert r.status_code == 422


class TestListar:
    def test_sai_na_ordem_em_que_a_vida_aconteceu(self, client, auth_headers):
        h = auth_headers()
        _criar(client, h, name="Depois", started_at="2020-01-01T00:00:00Z")
        _criar(client, h, name="Antes", started_at="2010-01-01T00:00:00Z")
        _criar(client, h, name="Sem data")

        nomes = [f["name"] for f in client.get("/life-phases", headers=h).json()]

        # Quem não tem início declarado vai para o FIM: um NULL não deve
        # encabeçar a história de ninguém.
        assert nomes == ["Antes", "Depois", "Sem data"]

    def test_quem_nunca_criou_nenhuma_ve_lista_vazia(self, client, auth_headers):
        assert client.get("/life-phases", headers=auth_headers()).json() == []


class TestIsolamento:
    def test_a_fase_de_outra_pessoa_nao_existe(self, client, auth_headers):
        alheia = _criar(client, auth_headers(), name="Alheia").json()["id"]
        outro = auth_headers()

        assert client.get(f"/life-phases/{alheia}", headers=outro).status_code == 404
        assert client.get("/life-phases", headers=outro).json() == []

    def test_id_inexistente_responde_igual_a_id_de_outro(self, client, auth_headers):
        # Mesma resposta nos dois casos: quem sonda ids não descobre quais
        # existem.
        h = auth_headers()
        assert client.get(f"/life-phases/{uuid.uuid4()}", headers=h).status_code == 404

    def test_sem_token_nao_passa(self, client):
        assert client.get("/life-phases").status_code == 401


class TestEditar:
    def test_edita_so_o_que_veio(self, client, auth_headers):
        h = auth_headers()
        fase = _criar(client, h, description="um texto", color="moss").json()

        r = client.patch(
            f"/life-phases/{fase['id']}", json={"name": "Outro nome"}, headers=h
        )

        assert r.status_code == 200
        assert r.json()["name"] == "Outro nome"
        assert r.json()["description"] == "um texto", "o que não veio não muda"
        assert r.json()["color"] == "moss"

    def test_null_LIMPA_a_data_de_fim(self, client, auth_headers):
        # Ao contrário do PATCH de jornada, onde null é no-op. Aqui a
        # diferença importa: uma fase que ganhou fim por engano precisa poder
        # voltar a ser a fase em curso, e para data não existe o truque da
        # string vazia.
        h = auth_headers()
        fase = _criar(client, h, ended_at="2024-01-01T00:00:00Z").json()
        assert fase["ended_at"] is not None

        r = client.patch(f"/life-phases/{fase['id']}", json={"ended_at": None}, headers=h)

        assert r.status_code == 200
        assert r.json()["ended_at"] is None

    def test_edicao_incoerente_e_recusada(self, client, auth_headers):
        h = auth_headers()
        fase = _criar(client, h, started_at="2020-01-01T00:00:00Z").json()
        r = client.patch(
            f"/life-phases/{fase['id']}",
            json={"ended_at": "2019-01-01T00:00:00Z"},
            headers=h,
        )
        assert r.status_code == 422

    def test_nao_edita_fase_alheia(self, client, auth_headers):
        alheia = _criar(client, auth_headers()).json()["id"]
        r = client.patch(
            f"/life-phases/{alheia}", json={"name": "invadida"}, headers=auth_headers()
        )
        assert r.status_code == 404


class TestApagar:
    def test_apaga_e_some_da_lista(self, client, auth_headers):
        h = auth_headers()
        fase = _criar(client, h).json()

        assert client.delete(f"/life-phases/{fase['id']}", headers=h).status_code == 204
        assert client.get("/life-phases", headers=h).json() == []
        assert client.get(f"/life-phases/{fase['id']}", headers=h).status_code == 404

    def test_a_etiqueta_nao_leva_a_lembranca_junto(self, client, auth_headers, db_session):
        # O teste que vale o arquivo. Apagar uma fase solta o que apontava
        # para ela; perder a memória por causa da etiqueta seria a ordem
        # errada de importância.
        h = auth_headers()
        fase = _criar(client, h).json()
        memoria = client.post(
            "/memories",
            json={
                "text": "o mar estava frio",
                "latitude": -3.7,
                "longitude": -38.5,
                "occurred_at": "2024-08-14T00:00:00Z",
            },
            headers=h,
        ).json()
        jornada = client.post("/journeys", json={"title": "Litoral"}, headers=h).json()

        linha_m = db_session.get(Memory, uuid.UUID(memoria["id"]))
        linha_j = db_session.get(Journey, uuid.UUID(jornada["id"]))
        linha_m.life_phase_id = uuid.UUID(fase["id"])
        linha_j.life_phase_id = uuid.UUID(fase["id"])
        db_session.commit()

        assert client.delete(f"/life-phases/{fase['id']}", headers=h).status_code == 204

        db_session.expire_all()
        assert db_session.get(Memory, uuid.UUID(memoria["id"])) is not None
        assert db_session.get(Memory, uuid.UUID(memoria["id"])).life_phase_id is None
        assert db_session.get(Journey, uuid.UUID(jornada["id"])).life_phase_id is None

    def test_nao_apaga_fase_alheia(self, client, auth_headers):
        alheia = _criar(client, auth_headers()).json()["id"]
        assert client.delete(f"/life-phases/{alheia}", headers=auth_headers()).status_code == 404


class TestDatasSemFuso:
    """Regressão: as datas da fase não eram normalizadas para UTC. Uma data sem
    fuso ao lado de uma com fuso quebrava a comparação do período com
    TypeError, e a resposta era 500."""

    def test_patch_com_data_sem_fuso_numa_fase_com_fuso(self, client, auth_headers):
        h = auth_headers()
        fase = _criar(client, h, started_at="2020-01-01T00:00:00Z").json()

        r = client.patch(
            f"/life-phases/{fase['id']}", json={"ended_at": "2021-01-01T00:00:00"}, headers=h
        )
        assert r.status_code == 200, r.text
        # Sem fuso vira UTC — não o fuso da sessão do banco.
        fim = datetime.fromisoformat(r.json()["ended_at"])
        assert fim == datetime(2021, 1, 1, tzinfo=UTC)

    def test_post_misturando_os_dois_formatos(self, client, auth_headers):
        h = auth_headers()
        ok = _criar(
            client, h, started_at="2020-01-01T00:00:00Z", ended_at="2021-01-01T00:00:00"
        )
        assert ok.status_code == 201, ok.text
        incoerente = _criar(
            client, h, started_at="2021-01-01T00:00:00Z", ended_at="2020-01-01T00:00:00"
        )
        assert incoerente.status_code == 422, "incoerente é 422, não 500"


class TestNomeUnico:
    """Duas "Faculdade" viram duas etiquetas iguais na lente, e a pessoa não
    tem como saber qual filtra o quê."""

    def test_mesmo_nome_sem_diferenciar_caixa_e_recusado(self, client, auth_headers):
        h = auth_headers()
        assert _criar(client, h, name="Faculdade").status_code == 201
        r = _criar(client, h, name="  faculdade ")
        assert r.status_code == 409
        assert "Faculdade" in r.json()["detail"] or "faculdade" in r.json()["detail"]
        assert len(client.get("/life-phases", headers=h).json()) == 1

    def test_renomear_para_o_nome_de_outra_e_recusado(self, client, auth_headers):
        h = auth_headers()
        _criar(client, h, name="Infância")
        outra = _criar(client, h, name="Recomeços").json()
        r = client.patch(f"/life-phases/{outra['id']}", json={"name": "INFÂNCIA"}, headers=h)
        assert r.status_code == 409
        assert client.get(f"/life-phases/{outra['id']}", headers=h).json()["name"] == "Recomeços"

    def test_mudar_so_a_caixa_do_proprio_nome_pode(self, client, auth_headers):
        h = auth_headers()
        fase = _criar(client, h, name="faculdade").json()
        r = client.patch(f"/life-phases/{fase['id']}", json={"name": "Faculdade"}, headers=h)
        assert r.status_code == 200, r.text

    def test_o_nome_de_uma_fase_apagada_fica_livre(self, client, auth_headers):
        h = auth_headers()
        fase = _criar(client, h, name="Mudança").json()
        client.delete(f"/life-phases/{fase['id']}", headers=h)
        assert _criar(client, h, name="Mudança").status_code == 201

    def test_cada_pessoa_tem_os_proprios_nomes(self, client, auth_headers):
        assert _criar(client, auth_headers(), name="Infância").status_code == 201
        assert _criar(client, auth_headers(), name="Infância").status_code == 201

    def test_dois_posts_juntos_com_o_mesmo_nome(self, client, auth_headers, monkeypatch):
        # A conferência e o INSERT não são atômicos; o índice barra o segundo.
        from app.repositories import life_phase_repository

        h = auth_headers()
        assert _criar(client, h, name="Corrida").status_code == 201
        monkeypatch.setattr(life_phase_repository, "name_taken", lambda *a, **k: False)
        assert _criar(client, h, name="corrida").status_code == 409
