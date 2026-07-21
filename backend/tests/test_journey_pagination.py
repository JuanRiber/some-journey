"""Paginação por keyset da listagem de jornadas (GET /journeys).

Cobre o contrato compartilhado: corpo é ARRAY JSON puro (retrocompatível), a
próxima página vem no header X-Next-Cursor, a caminhada por páginas não gera
lacunas nem duplicatas, cursor inválido vira 400 e o limite é normalizado
(clamp) em vez de rejeitado.
"""

from app.core.pagination import NEXT_CURSOR_HEADER


def _journey(client, h, title):
    r = client.post("/journeys", json={"title": title}, headers=h)
    assert r.status_code == 201, r.text
    return r.json()["id"]


def test_list_is_bare_array_and_backward_compatible(client, auth_headers):
    h = auth_headers()
    for i in range(3):
        _journey(client, h, f"J{i}")
    r = client.get("/journeys", headers=h)
    assert r.status_code == 200
    body = r.json()
    assert isinstance(body, list)  # array puro, sem envelope
    assert len(body) == 3
    # cabe tudo na página default -> sem próxima página -> sem header
    assert NEXT_CURSOR_HEADER not in r.headers


def test_default_order_is_most_recent_first(client, auth_headers):
    h = auth_headers()
    ids = [_journey(client, h, f"J{i}") for i in range(3)]
    body = client.get("/journeys", headers=h).json()
    # created_at DESC, id DESC -> a última criada aparece primeiro
    assert [j["id"] for j in body] == list(reversed(ids))


def test_keyset_walks_all_pages_without_gaps_or_dups(client, auth_headers):
    h = auth_headers()
    created = [_journey(client, h, f"J{i}") for i in range(5)]
    seen: list[str] = []
    cursor = None
    pages = 0
    while True:
        params = {"limit": 2}
        if cursor:
            params["cursor"] = cursor
        r = client.get("/journeys", params=params, headers=h)
        assert r.status_code == 200, r.text
        page = r.json()
        seen.extend(p["id"] for p in page)
        cursor = r.headers.get(NEXT_CURSOR_HEADER)
        pages += 1
        assert pages < 10  # trava anti-loop
        if cursor is None:
            break
        # enquanto houver próxima página, a atual veio cheia (limit=2)
        assert len(page) == 2
    # 5 itens em páginas de 2 -> 3 páginas (2 + 2 + 1)
    assert pages == 3
    assert len(seen) == 5
    assert set(seen) == set(created)  # sem lacunas
    assert len(set(seen)) == 5  # sem duplicatas


def test_next_cursor_absent_on_exact_last_page(client, auth_headers):
    h = auth_headers()
    for i in range(4):
        _journey(client, h, f"J{i}")
    # Página 1 (limit=2): há próxima -> header presente.
    r1 = client.get("/journeys", params={"limit": 2}, headers=h)
    c1 = r1.headers.get(NEXT_CURSOR_HEADER)
    assert c1 is not None
    # Página 2: consome os 2 restantes; não há próxima -> sem header.
    r2 = client.get("/journeys", params={"limit": 2, "cursor": c1}, headers=h)
    assert len(r2.json()) == 2
    assert NEXT_CURSOR_HEADER not in r2.headers


def test_limit_is_clamped_below_one(client, auth_headers):
    h = auth_headers()
    for i in range(3):
        _journey(client, h, f"J{i}")
    # limit=0 é normalizado para 1 (clamp), não rejeitado.
    r = client.get("/journeys", params={"limit": 0}, headers=h)
    assert r.status_code == 200
    assert len(r.json()) == 1
    assert r.headers.get(NEXT_CURSOR_HEADER) is not None


def test_invalid_cursor_returns_400(client, auth_headers):
    h = auth_headers()
    _journey(client, h, "J")
    r = client.get("/journeys", params={"cursor": "not-a-valid-cursor"}, headers=h)
    assert r.status_code == 400


def test_pagination_is_scoped_to_owner(client, auth_headers):
    h1 = auth_headers()
    h2 = auth_headers()
    for i in range(3):
        _journey(client, h1, f"A{i}")
    # u2 não tem jornadas: lista vazia, sem cursor.
    r = client.get("/journeys", params={"limit": 2}, headers=h2)
    assert r.status_code == 200
    assert r.json() == []
    assert NEXT_CURSOR_HEADER not in r.headers
