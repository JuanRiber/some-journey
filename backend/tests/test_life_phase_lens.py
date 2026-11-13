"""Fases da vida, a segunda metade: o vínculo e a lente.

O vínculo é por onde uma memória ou jornada ganha fase — e a única porta
precisa barrar a fase de outra pessoa, porque a FK aceitaria: a fase existe.

A lente é o filtro. A regra que estes testes guardam é a que um teste de CRUD
não pegaria: a memória está na fase quando foi marcada nela OU quando está
numa jornada marcada nela. Sem a herança, quem marca "Intercâmbio" numa
jornada e filtra por "Intercâmbio" não encontra as lembranças dela — e a fase
viraria uma etiqueta que a pessoa precisa colar à mão em cada foto.
"""

import pytest


def _fase(client, h, nome="Intercâmbio"):
    r = client.post("/life-phases", json={"name": nome}, headers=h)
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _memoria(client, h, titulo="Praia", dia="2024-03-10", **campos):
    corpo = {
        "title": titulo,
        "latitude": -3.73,
        "longitude": -38.52,
        "occurred_at": f"{dia}T12:00:00Z",
    } | campos
    r = client.post("/memories", json=corpo, headers=h)
    assert r.status_code == 201, r.text
    return r.json()


def _jornada(client, h, titulo="Mochilão", **campos):
    r = client.post("/journeys", json={"title": titulo} | campos, headers=h)
    assert r.status_code == 201, r.text
    return r.json()


def _ligar(client, h, jornada_id, memoria_id):
    r = client.post(
        f"/journeys/{jornada_id}/points", json={"memory_id": memoria_id}, headers=h
    )
    assert r.status_code in (200, 201), r.text


def _ids(lista):
    return {item["id"] for item in lista}


# ── O vínculo ───────────────────────────────────────────────────────────────


class TestVinculoDaMemoria:
    def test_nasce_na_fase_e_le_de_volta(self, client, auth_headers):
        h = auth_headers()
        fase = _fase(client, h)
        criada = _memoria(client, h, life_phase_id=fase)

        assert criada["life_phase_id"] == fase
        lida = client.get(f"/memories/{criada['id']}", headers=h).json()
        assert lida["life_phase_id"] == fase

    def test_sem_fase_e_o_normal(self, client, auth_headers):
        # Quem nunca criou fase nenhuma usa o produto inteiro sem perceber que
        # isto existe: o campo vem nulo e nada mais muda.
        assert _memoria(client, auth_headers())["life_phase_id"] is None

    def test_patch_sem_o_campo_nao_mexe_na_fase(self, client, auth_headers):
        h = auth_headers()
        fase = _fase(client, h)
        m = _memoria(client, h, life_phase_id=fase)

        r = client.patch(f"/memories/{m['id']}", json={"title": "Outra"}, headers=h)
        assert r.status_code == 200, r.text
        assert r.json()["life_phase_id"] == fase

    def test_patch_com_null_SOLTA_a_memoria_da_fase(self, client, auth_headers):
        # A exceção deliberada ao "null não mexe" do PATCH de memória: um id
        # não tem string vazia que o substitua. Sem isso, a memória marcada por
        # engano nunca mais voltaria a não ter fase.
        h = auth_headers()
        m = _memoria(client, h, life_phase_id=_fase(client, h))

        r = client.patch(f"/memories/{m['id']}", json={"life_phase_id": None}, headers=h)
        assert r.status_code == 200, r.text
        assert r.json()["life_phase_id"] is None
        # E o resto continua com a convenção de sempre.
        assert r.json()["title"] == "Praia"

    def test_patch_troca_de_fase(self, client, auth_headers):
        h = auth_headers()
        m = _memoria(client, h, life_phase_id=_fase(client, h, "Infância"))
        outra = _fase(client, h, "Recomeços")

        r = client.patch(f"/memories/{m['id']}", json={"life_phase_id": outra}, headers=h)
        assert r.json()["life_phase_id"] == outra

    def test_fase_de_outra_pessoa_e_recusada_sem_gravar_nada(self, client, auth_headers):
        dona, intrusa = auth_headers(), auth_headers()
        alheia = _fase(client, dona)

        r = client.post(
            "/memories",
            json={
                "title": "X",
                "latitude": 0,
                "longitude": 0,
                "occurred_at": "2024-01-01T12:00:00Z",
                "life_phase_id": alheia,
            },
            headers=intrusa,
        )
        # 422, não 404: o que não serve é um valor do corpo.
        assert r.status_code == 422
        assert "fase" in r.json()["detail"].lower()
        assert client.get("/memories", headers=intrusa).json() == []

    def test_fase_apagada_e_recusada_e_a_antiga_fica(self, client, auth_headers):
        h = auth_headers()
        atual = _fase(client, h, "Atual")
        apagada = _fase(client, h, "Apagada")
        client.delete(f"/life-phases/{apagada}", headers=h)
        m = _memoria(client, h, life_phase_id=atual)

        r = client.patch(
            f"/memories/{m['id']}",
            json={"life_phase_id": apagada, "title": "Não deve gravar"},
            headers=h,
        )
        assert r.status_code == 422
        lida = client.get(f"/memories/{m['id']}", headers=h).json()
        assert lida["life_phase_id"] == atual
        assert lida["title"] == "Praia", "o PATCH recusado não grava pela metade"


class TestVinculoDaJornada:
    def test_nasce_na_fase_e_le_de_volta(self, client, auth_headers):
        h = auth_headers()
        fase = _fase(client, h)
        j = _jornada(client, h, life_phase_id=fase)

        assert j["life_phase_id"] == fase
        detalhe = client.get(f"/journeys/{j['id']}", headers=h).json()
        assert detalhe["life_phase_id"] == fase

    def test_patch_com_null_solta_e_sem_o_campo_nao_mexe(self, client, auth_headers):
        h = auth_headers()
        fase = _fase(client, h)
        j = _jornada(client, h, life_phase_id=fase)

        r = client.patch(f"/journeys/{j['id']}", json={"mood": "leve"}, headers=h)
        assert r.json()["life_phase_id"] == fase

        r = client.patch(f"/journeys/{j['id']}", json={"life_phase_id": None}, headers=h)
        assert r.status_code == 200, r.text
        assert r.json()["life_phase_id"] is None

    def test_fase_de_outra_pessoa_e_recusada(self, client, auth_headers):
        dona, intrusa = auth_headers(), auth_headers()
        alheia = _fase(client, dona)

        r = client.post(
            "/journeys", json={"title": "X", "life_phase_id": alheia}, headers=intrusa
        )
        assert r.status_code == 422

        j = _jornada(client, intrusa)
        r = client.patch(
            f"/journeys/{j['id']}", json={"life_phase_id": alheia}, headers=intrusa
        )
        assert r.status_code == 422


# ── A lente ─────────────────────────────────────────────────────────────────


@pytest.fixture()
def atlas(client, auth_headers):
    """Um atlas pequeno com cada caso da regra:

    - `marcada`: solta, marcada na fase;
    - `herdada`: sem marca própria, dentro da jornada marcada na fase;
    - `vizinha`: sem marca, dentro de uma jornada SEM fase — mas que tem
      `semente`, marcada na fase;
    - `fora`: solta e sem fase;
    - `outra_fase`: solta, marcada noutra fase.
    """
    h = auth_headers()
    fase = _fase(client, h, "Intercâmbio")
    outra = _fase(client, h, "Infância")

    marcada = _memoria(client, h, "Marcada", "2024-01-01", life_phase_id=fase)
    herdada = _memoria(client, h, "Herdada", "2024-02-01")
    vizinha = _memoria(client, h, "Vizinha", "2024-03-01")
    semente = _memoria(client, h, "Semente", "2024-04-01", life_phase_id=fase)
    fora = _memoria(client, h, "Fora", "2024-05-01")
    outra_fase = _memoria(client, h, "Outra fase", "2024-06-01", life_phase_id=outra)

    da_fase = _jornada(client, h, "Jornada da fase", life_phase_id=fase)
    _ligar(client, h, da_fase["id"], herdada["id"])
    sem_fase = _jornada(client, h, "Jornada sem fase")
    _ligar(client, h, sem_fase["id"], vizinha["id"])
    _ligar(client, h, sem_fase["id"], semente["id"])
    alheia_a_fase = _jornada(client, h, "Jornada de fora")
    _ligar(client, h, alheia_a_fase["id"], fora["id"])

    return {
        "h": h,
        "fase": fase,
        "outra": outra,
        "m": {
            "marcada": marcada["id"],
            "herdada": herdada["id"],
            "vizinha": vizinha["id"],
            "semente": semente["id"],
            "fora": fora["id"],
            "outra_fase": outra_fase["id"],
        },
        "j": {
            "da_fase": da_fase["id"],
            "sem_fase": sem_fase["id"],
            "de_fora": alheia_a_fase["id"],
        },
    }


class TestLenteNaTimeline:
    def test_marcada_e_herdada_da_jornada_entram(self, client, atlas):
        r = client.get(f"/memories?life_phase_id={atlas['fase']}", headers=atlas["h"])
        assert r.status_code == 200, r.text
        m = atlas["m"]
        # `vizinha` NÃO entra: a herança desce da jornada para a memória, não
        # sobe de uma memória para as irmãs dela.
        assert _ids(r.json()) == {m["marcada"], m["herdada"], m["semente"]}

    def test_a_marca_propria_nao_e_confundida_com_a_herdada(self, client, atlas):
        # A memória herdada aparece no filtro, mas continua dizendo que NÃO foi
        # marcada — senão o seletor da edição mentiria sobre o que está gravado.
        r = client.get(f"/memories/{atlas['m']['herdada']}", headers=atlas["h"])
        assert r.json()["life_phase_id"] is None

    def test_quem_sai_da_jornada_deixa_de_herdar(self, client, atlas):
        h, m = atlas["h"], atlas["m"]
        r = client.delete(
            f"/journeys/{atlas['j']['da_fase']}/points/{m['herdada']}", headers=h
        )
        assert r.status_code == 204, r.text

        r = client.get(f"/memories?life_phase_id={atlas['fase']}", headers=h)
        assert m["herdada"] not in _ids(r.json())

    def test_sem_filtro_nada_muda(self, client, atlas):
        r = client.get("/memories", headers=atlas["h"])
        assert len(r.json()) == 6

    def test_pagina_com_o_filtro_aplicado(self, client, atlas):
        h, fase = atlas["h"], atlas["fase"]
        p1 = client.get(f"/memories?life_phase_id={fase}&limit=2", headers=h)
        cursor = p1.headers.get("x-next-cursor")
        assert len(p1.json()) == 2 and cursor

        p2 = client.get(
            "/memories", params={"life_phase_id": fase, "limit": 2, "cursor": cursor},
            headers=h,
        )
        assert len(p2.json()) == 1
        assert p2.headers.get("x-next-cursor") is None
        # As duas páginas juntas são exatamente a fase, sem repetir ninguém.
        assert len(_ids(p1.json()) | _ids(p2.json())) == 3


class TestLenteNasJornadas:
    def test_marcada_ou_com_memoria_da_fase(self, client, atlas):
        r = client.get(f"/journeys?life_phase_id={atlas['fase']}", headers=atlas["h"])
        assert r.status_code == 200, r.text
        j = atlas["j"]
        assert _ids(r.json()) == {j["da_fase"], j["sem_fase"]}


class TestLenteNoMapa:
    def test_soltos_so_os_marcados(self, client, atlas):
        r = client.get(f"/map?life_phase_id={atlas['fase']}", headers=atlas["h"])
        assert r.status_code == 200, r.text
        soltos = {p["memory_id"] for p in r.json()["loose_points"]}
        assert soltos == {atlas["m"]["marcada"]}

    def test_a_jornada_vem_inteira_com_o_rastro(self, client, atlas):
        # A jornada sem fase entra por causa de UMA memória marcada — e vem com
        # as duas, e com o rastro. Cortar o caminho no meio contaria uma viagem
        # que não aconteceu.
        r = client.get(f"/map?life_phase_id={atlas['fase']}", headers=atlas["h"])
        jornadas = {j["id"]: j for j in r.json()["journeys"]}
        assert set(jornadas) == {atlas["j"]["da_fase"], atlas["j"]["sem_fase"]}

        sem_fase = jornadas[atlas["j"]["sem_fase"]]
        assert {p["memory_id"] for p in sem_fase["points"]} == {
            atlas["m"]["vizinha"],
            atlas["m"]["semente"],
        }
        assert sem_fase["route"] is not None

    def test_a_outra_fase_tem_o_proprio_recorte(self, client, atlas):
        r = client.get(f"/map?life_phase_id={atlas['outra']}", headers=atlas["h"])
        corpo = r.json()
        assert {p["memory_id"] for p in corpo["loose_points"]} == {
            atlas["m"]["outra_fase"]
        }
        assert corpo["journeys"] == []


class TestFaseQueNaoExisteNoFiltro:
    @pytest.mark.parametrize("rota", ["/memories", "/journeys", "/map"])
    def test_fase_alheia_responde_404(self, client, auth_headers, rota):
        # 404 e não lista vazia: "nada nesta fase" é uma resposta plausível, e
        # esconderia que a fase pedida não existe para esta pessoa.
        dona, intrusa = auth_headers(), auth_headers()
        alheia = _fase(client, dona)
        r = client.get(f"{rota}?life_phase_id={alheia}", headers=intrusa)
        assert r.status_code == 404

    @pytest.mark.parametrize("rota", ["/memories", "/journeys", "/map"])
    def test_fase_apagada_responde_404(self, client, auth_headers, rota):
        h = auth_headers()
        fase = _fase(client, h)
        client.delete(f"/life-phases/{fase}", headers=h)
        assert client.get(f"{rota}?life_phase_id={fase}", headers=h).status_code == 404

    def test_id_malformado_e_422(self, client, auth_headers):
        r = client.get("/memories?life_phase_id=nao-e-uuid", headers=auth_headers())
        assert r.status_code == 422
