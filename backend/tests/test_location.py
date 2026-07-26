"""Location (Value Object) + derivação de continente. Domínio puro, sem banco."""

from datetime import UTC, datetime

import pytest

from app.domain.continents import CONTINENTS_IN_ORDER, continent_for
from app.domain.location import Location

FORTALEZA = dict(latitude=-3.7319, longitude=-38.5267)


def test_so_coordenadas_ja_e_um_lugar_valido():
    loc = Location(**FORTALEZA)
    assert loc.is_geocoded is False
    assert loc.geohash  # derivado sempre
    assert loc.continent is None


def test_geohash_e_derivado_e_estavel():
    a = Location(**FORTALEZA)
    b = Location(**FORTALEZA)
    assert a.geohash == b.geohash
    assert len(a.geohash) == 12


def test_continente_derivado_do_country_code():
    loc = Location(**FORTALEZA, country_code="BR")
    assert loc.continent == "América do Sul"


def test_country_code_e_normalizado_para_iso2_maiusculo():
    """O Passaporte conta DISTINCT country_code: 'br' e 'BR' não podem virar dois."""
    assert Location(**FORTALEZA, country_code=" br ").country_code == "BR"


def test_pais_desconhecido_nao_quebra():
    loc = Location(**FORTALEZA, country_code="ZZ")
    assert loc.continent is None


def test_igualdade_por_valor():
    a = Location(**FORTALEZA, city="Fortaleza", country_code="BR")
    b = Location(**FORTALEZA, city="Fortaleza", country_code="BR")
    assert a == b
    assert len({a, b}) == 1, "dois lugares iguais são o mesmo lugar (dedupe)"


def test_e_imutavel():
    loc = Location(**FORTALEZA)
    with pytest.raises(Exception):
        loc.city = "outra"  # type: ignore[misc]


@pytest.mark.parametrize("lat,lng", [(91, 0), (0, 181)])
def test_coordenada_impossivel_falha(lat, lng):
    with pytest.raises(ValueError):
        Location(latitude=lat, longitude=lng)


class TestDisplayLabel:
    def test_prefere_o_rotulo_do_usuario(self):
        loc = Location(**FORTALEZA, place_label="Praia de Iracema", city="Fortaleza")
        assert loc.display_label == "Praia de Iracema"

    def test_cai_para_cidade_e_pais(self):
        loc = Location(**FORTALEZA, city="Fortaleza", country="Brasil")
        assert loc.display_label == "Fortaleza, Brasil"

    def test_sem_geocode_mostra_coordenadas_em_vez_de_vazio(self):
        assert "-3.7319" in Location(**FORTALEZA).display_label


def test_with_geocoding_gera_novo_objeto_e_recalcula_continente():
    original = Location(**FORTALEZA)
    now = datetime.now(UTC)
    geocoded = original.with_geocoding(
        place_name="Praia de Iracema",
        place_label="Praia de Iracema, Fortaleza",
        city="Fortaleza",
        state_province="Ceará",
        country="Brasil",
        country_code="br",
        formatted_address="Praia de Iracema, Fortaleza, CE, Brasil",
        timezone="America/Fortaleza",
        geocoded_at=now,
    )
    assert original.is_geocoded is False, "o original não é mutado"
    assert geocoded.is_geocoded is True
    assert geocoded.country_code == "BR"
    assert geocoded.continent == "América do Sul"
    assert geocoded.geohash == original.geohash, "mesmo ponto, mesmo geohash"


def test_roundtrip_colunas():
    """to_columns/from_row são o contrato exclusivo do repository."""
    loc = Location(**FORTALEZA, city="Fortaleza", country_code="BR",
                   geocoded_at=datetime.now(UTC))
    cols = loc.to_columns()
    assert "latitude" not in cols, "a posição vive na coluna GEOGRAPHY"

    class Row:
        pass
    row = Row()
    for k, v in cols.items():
        setattr(row, k, v)
    back = Location.from_row(latitude=loc.latitude, longitude=loc.longitude, row=row)
    assert back == loc


def test_passaporte_cobre_todos_os_continentes_da_tabela():
    for code in ("BR", "US", "PT", "NG", "JP", "AU", "AQ"):
        assert continent_for(code) in CONTINENTS_IN_ORDER
    assert continent_for(None) is None
