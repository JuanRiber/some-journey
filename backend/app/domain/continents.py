"""Continente a partir do country_code (ISO-3166-1 alpha-2) — TABELA ESTÁTICA.

O Nominatim não devolve continente, e não vale uma chamada de rede a mais por
memória para descobrir algo que nunca muda. Mapa fixo, custo zero, offline.

Os nomes estão em português porque são exibidos direto no Passaporte do Perfil
("✓ América do Sul"). Se um dia houver i18n, a chave de tradução nasce daqui.
"""

# Agrupado por continente (compacto e fácil de auditar); o índice inverso é
# construído uma vez no import.
_CODES_BY_CONTINENT: dict[str, str] = {
    "África": (
        "DZ AO BJ BW BF BI CV CM CF TD KM CD CG CI DJ EG GQ ER SZ ET GA GM GH "
        "GN GW KE LS LR LY MG MW ML MR MU YT MA MZ NA NE NG RE RW SH ST SN SC "
        "SL SO ZA SS SD TZ TG TN UG EH ZM ZW"
    ),
    "América do Norte": (
        "AI AG AW BS BB BZ BM BQ VG CA KY CR CU CW DM DO SV GL GD GP GT HT HN "
        "JM MQ MX MS NI PA PR BL KN LC MF PM VC SX TT TC US VI"
    ),
    "América do Sul": "AR BO BR CL CO EC FK GF GY PE PY SR UY VE",
    "Antártida": "AQ BV GS HM TF",
    "Ásia": (
        "AF AM AZ BH BD BT BN KH CN CY GE HK IN ID IR IQ IL JP JO KZ KP KR KW "
        "KG LA LB MO MY MV MN MM NP OM PK PS PH QA SA SG LK SY TW TJ TH TL TR "
        "TM AE UZ VN YE"
    ),
    "Europa": (
        "AL AD AT BY BE BA BG HR CZ DK EE FO FI FR DE GI GR GG HU IS IE IM IT "
        "JE LV LI LT LU MT MD MC ME NL MK NO PL PT RO RU SM RS SK SI ES SJ SE "
        "CH UA GB VA AX"
    ),
    "Oceania": (
        "AS AU CK FJ PF GU KI MH FM NR NC NZ NU NF MP PW PG PN WS SB TK TO TV "
        "VU WF"
    ),
}

CONTINENT_BY_COUNTRY_CODE: dict[str, str] = {
    code: continent
    for continent, codes in _CODES_BY_CONTINENT.items()
    for code in codes.split()
}

# Ordem de exibição do Passaporte (do mais provável ao menos, para o usuário
# brasileiro ver primeiro o que já carimbou).
CONTINENTS_IN_ORDER: tuple[str, ...] = (
    "América do Sul",
    "América do Norte",
    "Europa",
    "África",
    "Ásia",
    "Oceania",
    "Antártida",
)


def continent_for(country_code: str | None) -> str | None:
    """Continente do país, ou None quando o código é desconhecido/ausente.

    Aceita o código em qualquer caixa e com espaços; normaliza para ISO-2
    maiúsculo. Código inválido devolve None em vez de levantar: um país
    desconhecido não pode impedir que a memória seja salva.
    """
    if not country_code:
        return None
    return CONTINENT_BY_COUNTRY_CODE.get(country_code.strip().upper())
