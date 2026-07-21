"""Paginação por keyset de GET /memories.

Cobre: o teto/normalização de `?limit`, a continuação por `?cursor`, o header
X-Next-Cursor (presente só quando há próxima página), a ordenação
(occurred_at DESC) com desempate estável por id, e o cursor malformado -> 400.

O corpo continua sendo um ARRAY puro (retrocompatível) — o cursor vive só no
header. As memórias nascem sem fotos, então o Storage nem é tocado aqui.
"""

from app.core.pagination import NEXT_CURSOR_HEADER


def _create(client, headers, occurred_at, title="M"):
    r = client.post(
        "/memories",
        json={
            "title": title,
            "latitude": 1.0,
            "longitude": 2.0,
            "occurred_at": occurred_at,
        },
        headers=headers,
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def test_limit_caps_page_and_sets_next_cursor(client, auth_headers):
    h = auth_headers()
    _create(client, h, "2020-01-01T00:00:00Z")
    _create(client, h, "2021-01-01T00:00:00Z")
    _create(client, h, "2022-01-01T00:00:00Z")

    r = client.get("/memories?limit=2", headers=h)
    assert r.status_code == 200, r.text
    assert len(r.json()) == 2
    assert NEXT_CURSOR_HEADER in r.headers  # há mais uma página


def test_no_next_cursor_header_on_last_page(client, auth_headers):
    h = auth_headers()
    _create(client, h, "2020-01-01T00:00:00Z")
    _create(client, h, "2021-01-01T00:00:00Z")

    # exatamente 2 itens, limit 2: não sobra próxima página -> sem header.
    r = client.get("/memories?limit=2", headers=h)
    assert r.status_code == 200
    assert len(r.json()) == 2
    assert NEXT_CURSOR_HEADER not in r.headers


def test_cursor_continues_without_gaps_or_dups(client, auth_headers):
    h = auth_headers()
    for year in (2020, 2021, 2022):
        _create(client, h, f"{year}-01-01T00:00:00Z")

    r1 = client.get("/memories?limit=2", headers=h)
    page1 = [m["id"] for m in r1.json()]
    cursor = r1.headers[NEXT_CURSOR_HEADER]

    r2 = client.get(f"/memories?limit=2&cursor={cursor}", headers=h)
    page2 = [m["id"] for m in r2.json()]

    assert len(page1) == 2
    assert len(page2) == 1
    assert NEXT_CURSOR_HEADER not in r2.headers
    combined = page1 + page2
    assert len(set(combined)) == 3  # todos, sem duplicatas


def test_order_is_occurred_at_desc(client, auth_headers):
    h = auth_headers()
    _create(client, h, "2020-06-15T00:00:00Z", title="old")
    _create(client, h, "2022-06-15T00:00:00Z", title="new")
    _create(client, h, "2021-06-15T00:00:00Z", title="mid")

    titles = [m["title"] for m in client.get("/memories", headers=h).json()]
    assert titles == ["new", "mid", "old"]


def test_tiebreaker_is_stable_and_paginates_cleanly(client, auth_headers):
    """Mesmo occurred_at em todas: sem desempate a ordem seria não-determinística
    e o cursor pularia/duplicaria linhas. Com id DESC a ordem é total e estável:
    a paginação 1-a-1 reproduz EXATAMENTE a ordem da listagem cheia."""
    h = auth_headers()
    same = "2021-01-01T00:00:00Z"
    for i in range(5):
        _create(client, h, same, title=f"m{i}")

    full = [m["id"] for m in client.get("/memories", headers=h).json()]
    assert len(full) == 5

    # duas leituras cheias -> mesma ordem (determinístico).
    again = [m["id"] for m in client.get("/memories", headers=h).json()]
    assert again == full

    # paginando de 1 em 1, seguindo o cursor, obtém a MESMA sequência.
    collected: list[str] = []
    cursor = None
    for _ in range(10):  # teto de segurança contra loop
        url = "/memories?limit=1" + (f"&cursor={cursor}" if cursor else "")
        r = client.get(url, headers=h)
        assert r.status_code == 200
        collected.extend(m["id"] for m in r.json())
        cursor = r.headers.get(NEXT_CURSOR_HEADER)
        if cursor is None:
            break
    assert collected == full


def test_malformed_cursor_returns_400(client, auth_headers):
    h = auth_headers()
    _create(client, h, "2021-01-01T00:00:00Z")
    r = client.get("/memories?cursor=!!!not-a-valid-cursor!!!", headers=h)
    assert r.status_code == 400


def test_limit_is_clamped_to_max(client, auth_headers):
    """limit acima do teto não estoura: é normalizado (clamp) e a rota responde
    200 com os itens existentes."""
    h = auth_headers()
    _create(client, h, "2021-01-01T00:00:00Z")
    r = client.get("/memories?limit=9999", headers=h)
    assert r.status_code == 200
    assert len(r.json()) == 1
