"""Serviço de geocoding: tradução do provedor + a regra de nunca bloquear a escrita."""

from datetime import UTC, datetime

import httpx

from app.services.geocoding import (
    NominatimGeocodingProvider,
    NullGeocodingProvider,
    resolve_location,
)

FORTALEZA = (-3.7319, -38.5267)

_PAYLOAD = {
    "name": "Praia de Iracema",
    "display_name": "Praia de Iracema, Fortaleza, Ceará, Brasil",
    "address": {
        "city": "Fortaleza",
        "state": "Ceará",
        "country": "Brasil",
        "country_code": "br",
    },
}


def _provider(handler, **kw):
    return NominatimGeocodingProvider(
        client=httpx.Client(transport=httpx.MockTransport(handler)), **kw
    )


def test_traduz_a_resposta_para_o_value_object():
    p = _provider(lambda r: httpx.Response(200, json=_PAYLOAD))
    loc = p.reverse(*FORTALEZA)

    assert loc is not None
    assert loc.city == "Fortaleza"
    assert loc.state_province == "Ceará"
    assert loc.country_code == "BR"          # normalizado pelo VO
    assert loc.continent == "América do Sul"  # derivado, sem rede
    assert loc.place_label == "Praia de Iracema, Fortaleza"
    assert loc.is_geocoded is True
    assert loc.geohash


def test_envia_user_agent_identificavel_como_o_nominatim_exige():
    seen = {}

    def handler(request):
        seen["ua"] = request.headers.get("user-agent", "")
        return httpx.Response(200, json=_PAYLOAD)

    _provider(handler).reverse(*FORTALEZA)
    assert "SomeJourney" in seen["ua"]


def test_respeita_o_limite_de_uma_chamada_por_segundo():
    calls = {"n": 0}

    def handler(request):
        calls["n"] += 1
        return httpx.Response(200, json=_PAYLOAD)

    fixed = datetime(2026, 7, 26, 12, 0, tzinfo=UTC)
    p = _provider(handler, now=lambda: fixed)  # relógio parado = 2ª chamada é cedo demais
    assert p.reverse(*FORTALEZA) is not None
    assert p.reverse(*FORTALEZA) is None, "a segunda é pulada e vai para o backfill"
    assert calls["n"] == 1


def test_cidade_vem_de_town_village_ou_municipality():
    payload = {"address": {"village": "Guaramiranga", "country_code": "br"}}
    loc = _provider(lambda r: httpx.Response(200, json=payload)).reverse(*FORTALEZA)
    assert loc.city == "Guaramiranga"


def test_resolvedor_de_fuso_e_opcional_e_nao_derruba_nada():
    ok = _provider(
        lambda r: httpx.Response(200, json=_PAYLOAD),
        timezone_resolver=lambda lat, lng: "America/Fortaleza",
    ).reverse(*FORTALEZA)
    assert ok.timezone == "America/Fortaleza"

    def explode(lat, lng):
        raise RuntimeError("sem base de fusos")

    still_ok = _provider(
        lambda r: httpx.Response(200, json=_PAYLOAD), timezone_resolver=explode
    ).reverse(*FORTALEZA)
    assert still_ok is not None and still_ok.timezone is None


class TestNuncaBloquearAEscrita:
    def test_erro_http_nao_levanta(self):
        p = _provider(lambda r: httpx.Response(503, text="down"))
        assert p.reverse(*FORTALEZA) is None

    def test_falha_de_rede_nao_levanta(self):
        def boom(request):
            raise httpx.ConnectError("sem rede")

        assert _provider(boom).reverse(*FORTALEZA) is None

    def test_resposta_inesperada_nao_levanta(self):
        p = _provider(lambda r: httpx.Response(200, json={"erro": "?"}))
        assert p.reverse(*FORTALEZA) is None

    def test_resolve_location_sempre_devolve_um_lugar(self):
        """É o contrato do serviço: quem chama não tem como esquecer da falha."""
        loc = resolve_location(NullGeocodingProvider(), latitude=-3.73, longitude=-38.52)
        assert loc.is_geocoded is False
        assert loc.geohash and loc.display_label

    def test_adapter_mal_comportado_que_levanta_e_contido(self):
        class Broken:
            def reverse(self, latitude, longitude):
                raise RuntimeError("adapter ruim")

        loc = resolve_location(Broken(), latitude=-3.73, longitude=-38.52)
        assert loc.is_geocoded is False
