"""Geohash — codifica (lat, long) numa string curta de base32.

Por que existe: o objeto de localização da memória guarda um `geohash` para
otimizações FUTURAS de busca — prefixos de geohash são vizinhança geográfica, então
"memórias por perto" e agrupamentos viram comparação de PREFIXO (indexável com um
btree comum), sem precisar de consulta espacial. Não substitui o PostGIS que já
usamos para bbox/distância; é um atalho barato e portável.

Escolha do tamanho: 12 caracteres (precisão de ~3,7 cm) é o padrão de fato e cabe
em VARCHAR(12). Cortar o prefixo dá precisões maiores: 5 chars ≈ 4,9 km (bairro),
6 ≈ 1,2 km, 7 ≈ 153 m.

Sem dependência externa de propósito: o algoritmo é pequeno, estável desde 2008 e
não vale mais uma biblioteca no requirements.
"""

# Alfabeto base32 do geohash (sem 'a', 'i', 'l', 'o' — evita confusão visual).
_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"

DEFAULT_PRECISION = 12


def encode(latitude: float, longitude: float, precision: int = DEFAULT_PRECISION) -> str:
    """Devolve o geohash de um ponto.

    Bisecção alternada: a cada bit, corta o intervalo de longitude (bits pares) ou
    de latitude (bits ímpares) pela metade e guarda de que lado o ponto caiu. Cinco
    bits formam um caractere de base32.

    Levanta ValueError para coordenadas fora do mundo ou precisão inválida — é
    melhor falhar na escrita do que gravar um geohash silenciosamente errado.
    """
    if not -90 <= latitude <= 90:
        raise ValueError("latitude deve estar entre -90 e 90")
    if not -180 <= longitude <= 180:
        raise ValueError("longitude deve estar entre -180 e 180")
    if precision < 1 or precision > 12:
        raise ValueError("precision deve estar entre 1 e 12")

    lat_range = [-90.0, 90.0]
    lng_range = [-180.0, 180.0]
    geohash: list[str] = []
    bits = 0
    bit_count = 0
    even_bit = True  # começa pela longitude

    while len(geohash) < precision:
        if even_bit:
            mid = (lng_range[0] + lng_range[1]) / 2
            if longitude >= mid:
                bits = (bits << 1) | 1
                lng_range[0] = mid
            else:
                bits <<= 1
                lng_range[1] = mid
        else:
            mid = (lat_range[0] + lat_range[1]) / 2
            if latitude >= mid:
                bits = (bits << 1) | 1
                lat_range[0] = mid
            else:
                bits <<= 1
                lat_range[1] = mid
        even_bit = not even_bit

        bit_count += 1
        if bit_count == 5:
            geohash.append(_BASE32[bits])
            bits = 0
            bit_count = 0

    return "".join(geohash)


def neighbours_prefix(geohash: str, precision: int) -> str:
    """Prefixo de vizinhança: 'quem está por perto' compartilha este prefixo.

    Uso pretendido: `WHERE geohash LIKE :prefix || '%'`. Cuidado conhecido do
    geohash — pontos muito próximos podem cair em prefixos diferentes quando estão
    nas bordas da grade, então isto é um FILTRO GROSSO (barato) que deve ser
    refinado por distância real depois.
    """
    if precision < 1:
        raise ValueError("precision deve ser >= 1")
    return geohash[:precision]
