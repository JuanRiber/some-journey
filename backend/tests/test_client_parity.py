"""Paridade cliente/backend: nenhuma rota pode nascer sem quem a chame.

Mora na suíte porque rodar custa zero — não toca o banco, não sobe servidor — e
não rodar já custou três vezes: `POST`/`DELETE` `/journeys/{id}/cover` e
`GET /journeys/{id}/memories` ficaram no ar, testadas e documentadas, até uma
auditoria manual descobrir que ninguém as chamava.

Os testes abaixo do primeiro existem para que o primeiro signifique alguma
coisa: um comparador que colete zero rota, ou que leia caminho errado dos
clientes, passaria verde para sempre.
"""

from pathlib import Path

from scripts import check_client_parity as parity
from scripts.check_client_parity import Endpoint


def test_toda_rota_do_backend_e_chamada_por_algum_cliente():
    relatorio = parity.run()
    assert not relatorio.drift, "\n" + parity.format_report(relatorio)


def test_a_coleta_enxerga_a_api_inteira():
    # Sem este piso, quebrar a leitura da tabela de rotas deixaria o teste de
    # cima verde para sempre — comparar conjunto vazio nunca acusa nada.
    rotas = parity.backend_routes()
    assert len(rotas) > 30
    # Uma rota com prefixo de router e uma com parâmetro: é onde um grep nos
    # decoradores erraria o caminho.
    assert Endpoint("POST", "/journeys/{}/cover") in rotas
    assert Endpoint("GET", "/journeys/{}/memories") in rotas


def test_a_tabela_de_rotas_sozinha_ja_enxerga_tudo():
    # `backend_routes` lê DUAS fontes (tabela de rotas e esquema OpenAPI) para
    # que uma cubra a falha da outra. O efeito colateral é que a tabela pode
    # parar de funcionar sem ninguém notar, carregada pelo OpenAPI — e aí o que
    # está marcado `include_in_schema=False` some da conta em silêncio. Este
    # teste é o lugar onde isso aparece no dia em que acontecer.
    from app.main import app

    pela_tabela = {
        Endpoint(metodo, parity.normalise_route(rota.path))
        for rota in parity._api_routes(app.routes)
        for metodo in (rota.methods or ())
    }
    assert parity.backend_routes() <= pela_tabela


def test_a_coleta_dos_clientes_enxerga_os_dois_arquivos():
    # Idem do outro lado: um cliente lido como vazio faria TODA rota virar
    # deriva, e o relatório ruidoso seria desligado antes de ser lido.
    for nome, caminho in parity.CLIENTS.items():
        chamadas = parity.client_calls(Path(caminho).read_text(encoding="utf-8"))
        assert len(chamadas) > 10, nome


def test_rota_sem_cliente_aparece_como_deriva():
    # O inverso do primeiro teste. Sem ele, "não há deriva" poderia significar
    # "não comparei nada".
    inventada = Endpoint("GET", "/journeys/{}/estatisticas")
    relatorio = parity.compare(
        parity.backend_routes() | {inventada}, parity.client_endpoints(), known_gaps={}
    )
    assert inventada in relatorio.drift
    assert str(inventada) in parity.format_report(relatorio)


def test_lacuna_declarada_nao_vira_deriva():
    # A allowlist é o que faz o check falhar SÓ em deriva nova. Se ela parasse
    # de suprimir, o relatório acusaria as mesmas sondas de saúde todo dia.
    sonda = Endpoint("GET", "/health")
    assert sonda in parity.KNOWN_GAPS
    relatorio = parity.run()
    assert sonda in relatorio.accepted
    assert sonda not in relatorio.drift


def test_lacuna_ja_fechada_e_avisada_sem_reprovar():
    # Quem passou a chamar uma rota que estava na lista fez a coisa certa: o
    # relatório pede a limpeza da entrada, mas não devolve vermelho por isso.
    ja_chamada = Endpoint("GET", "/memories")
    relatorio = parity.compare(
        parity.backend_routes(),
        parity.client_endpoints(),
        known_gaps={**parity.KNOWN_GAPS, ja_chamada: "motivo que deixou de valer"},
    )
    assert ja_chamada in relatorio.settled
    assert ja_chamada not in relatorio.drift


def test_interpolacao_do_cliente_casa_com_o_parametro_da_rota():
    # `$memoryId` do Dart e `${id}` do TypeScript têm de chegar à mesma forma
    # que `{memory_id}` da tabela de rotas; é esse encontro que o check depende.
    dart = r"""_request('DELETE', '/memories/$memoryId/images/$imageId', authed: true);"""
    assert ("DELETE", "/memories/{}/images/{}") in parity.client_calls(dart)

    ts = """request("GET", `/journeys/${id}/memories`, undefined, true);"""
    assert ("GET", "/journeys/{}/memories") in parity.client_calls(ts)


def test_a_base_da_url_sai_do_caminho():
    # O cliente Expo monta a URL com a base DENTRO do literal; ela não faz parte
    # da rota e, deixada ali, nenhum caminho casaria com a tabela.
    fonte = """fetch(`${API_URL}/memories/${id}/images`, { method: "POST" });"""
    assert ("POST", "/memories/{}/images") in parity.client_calls(fonte)


def test_querystring_sai_do_caminho():
    # `?limit=30` não é parte da rota: a tabela registra `/memories` e mais nada.
    fonte = """request("GET", "/memories?limit=30", undefined, true);"""
    assert ("GET", "/memories") in parity.client_calls(fonte)

    # A mesma coisa quando a querystring é montada em tempo de execução.
    montada = """request("GET", `/map${qs ? `?${qs}` : ""}`, undefined, true);"""
    assert ("GET", "/map") in parity.client_calls(montada)


def test_barra_dentro_de_interpolacao_nao_vira_caminho():
    # `type.split("/")[1]` tem uma barra entre aspas que NÃO é rota. Lida como
    # literal solto, ela entraria na lista de caminhos chamados — e um caminho
    # inventado do lado do cliente é exatamente o que encobre deriva.
    fonte = """const name = `photo.${type.split("/")[1] || "jpg"}`;"""
    assert parity.client_calls(fonte) == set()


def test_chave_dentro_de_string_nao_encerra_a_interpolacao():
    # `"}"` é uma chave que NÃO fecha a expressão. Contando chaves sem olhar as
    # aspas, a interpolação terminaria cedo, o resto do literal entraria no
    # caminho e `/memories/{}/images` viraria outra coisa — uma rota real
    # passaria a parecer sem cliente.
    fonte = """fetch(`${API_URL}/memories/${id ?? "}"}/images`, { method: "POST" });"""
    assert parity.client_calls(fonte) == {("POST", "/memories/{}/images")}


def test_comentario_nao_e_lido_como_chamada():
    # Os comentários deste projeto são em português e cheios de aspas e crases.
    # Lidos como código, desalinhariam a varredura do arquivo inteiro.
    fonte = """
// Hoje ninguem chama '/journeys/{id}/cover' — e a aspa solta d'aqui nao pode
// engolir o resto do arquivo.
request("GET", "/memories", undefined, true);
"""
    assert parity.client_calls(fonte) == {("GET", "/memories")}


# ---------------------------------------------------------------------------
# ASSEMBLED não pode apodrecer
# ---------------------------------------------------------------------------
#
# Declarar à mão que `/journeys/{}/{}` vira quatro rotas é o preço de não
# ensinar o parser a adivinhar. O risco de toda lista escrita à mão é envelhecer
# calada — e aí ela passa a AFIRMAR cobertura que não existe, que é pior que não
# ter check nenhum. Estes dois testes cobram a declaração nas duas pontas.


def test_assembled_ainda_descreve_o_cliente():
    """Se o ajudante sumir do cliente, a entrada tem de gritar.

    Sem isto, apagar `_lifecycle` deixaria as quatro rotas do ciclo de vida
    marcadas como alcançadas para sempre, por uma declaração que não descreve
    mais nada.
    """
    from scripts.check_client_parity import ASSEMBLED, CLIENTS, client_calls

    chamadas = set()
    for caminho in CLIENTS.values():
        chamadas |= {p for _m, p in client_calls(caminho.read_text(encoding="utf-8"))}

    for dinamico in ASSEMBLED:
        assert dinamico in chamadas, (
            f"ASSEMBLED declara '{dinamico}', que nenhum cliente monta mais. "
            "A entrada ficou órfã: ou o ajudante mudou de forma, ou sumiu."
        )


def test_assembled_aponta_para_rotas_que_existem():
    """E se a rota sumir do backend, a entrada também tem de gritar."""
    from scripts.check_client_parity import ASSEMBLED, backend_routes

    caminhos = {r.path for r in backend_routes()}

    for dinamico, concretos in ASSEMBLED.items():
        for concreto in concretos:
            assert concreto in caminhos, (
                f"ASSEMBLED resolve '{dinamico}' em '{concreto}', que não é mais "
                "uma rota do backend."
            )
