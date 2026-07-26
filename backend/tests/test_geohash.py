"""Geohash: valores conhecidos + invariantes. Não toca no banco."""

import pytest

from app.core.geohash import DEFAULT_PRECISION, encode, neighbours_prefix


def test_valores_conhecidos_de_referencia():
    # Casos canônicos da literatura do geohash.
    assert encode(57.64911, 10.40744, 11) == "u4pruydqqvj"
    assert encode(-25.382708, -49.265506, 9) == "6gkzwgjzn"
    # Origem (0,0) fica na fronteira das quatro células centrais.
    assert encode(0, 0, 1) == "s"


def test_precisao_controla_o_tamanho():
    assert len(encode(-3.72, -38.53)) == DEFAULT_PRECISION
    for p in range(1, 13):
        assert len(encode(-3.72, -38.53, p)) == p


def test_prefixo_e_estavel_ao_aumentar_a_precisao():
    """Um geohash mais preciso ESTENDE o menos preciso — é o que faz o prefixo
    funcionar como vizinhança."""
    curto = encode(-3.7319, -38.5267, 5)
    longo = encode(-3.7319, -38.5267, 10)
    assert longo.startswith(curto)


def test_pontos_vizinhos_compartilham_prefixo():
    # Duas esquinas da mesma praia caem no mesmo prefixo de ~5 km.
    a = encode(-3.7200, -38.5200, 5)
    b = encode(-3.7250, -38.5250, 5)
    assert a == b


def test_pontos_distantes_nao_compartilham_prefixo():
    fortaleza = encode(-3.7319, -38.5267, 5)
    lisboa = encode(38.7223, -9.1393, 5)
    assert fortaleza != lisboa


def test_neighbours_prefix_corta():
    full = encode(-3.7319, -38.5267, 12)
    assert neighbours_prefix(full, 5) == full[:5]
    with pytest.raises(ValueError):
        neighbours_prefix(full, 0)


@pytest.mark.parametrize(
    "lat,lng",
    [(91, 0), (-91, 0), (0, 181), (0, -181)],
)
def test_coordenada_fora_do_mundo_falha(lat, lng):
    """Melhor estourar na escrita que gravar um geohash errado em silêncio."""
    with pytest.raises(ValueError):
        encode(lat, lng)


@pytest.mark.parametrize("precision", [0, 13, -1])
def test_precisao_invalida_falha(precision):
    with pytest.raises(ValueError):
        encode(0, 0, precision)


def test_extremos_do_mundo_sao_validos():
    for lat, lng in [(90, 180), (-90, -180), (90, -180), (-90, 180)]:
        assert len(encode(lat, lng)) == DEFAULT_PRECISION
