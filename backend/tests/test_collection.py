"""Os números do Perfil como portas: cada quadrado abre o que ele conta.

`GET /me/places` e `GET /me/days` listam o que está por trás de "cidades",
"países" e "dias no app"; os recortes de `GET /memories` (`city`,
`country_code`, `has_images`, `created_on`) abrem as memórias de cada item.
O que importa aqui é a coerência: a lista e o filtro têm de contar a mesma
coisa que o número do Perfil.
"""

import uuid
from datetime import UTC, datetime

from sqlalchemy import update

from app.db.session import SessionLocal
from app.domain.location import Location
from app.models.memory import Memory
from app.repositories import memory_repository

# O upload confere os magic bytes do PNG, não o Content-Type.
_PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 64


def _memory(client, headers, *, title="M", when="2026-07-01"):
    r = client.post(
        "/memories",
        json={
            "title": title,
            "text": "",
            "latitude": -3.7319,
            "longitude": -38.5267,
            "occurred_at": f"{when}T12:00:00Z",
        },
        headers=headers,
    )
    assert r.status_code == 201, r.text
    return r.json()


def _user_id(client, headers) -> uuid.UUID:
    return uuid.UUID(client.get("/auth/me", headers=headers).json()["id"])


def _geocode(client, headers, memory_id, *, city, country, code):
    """Preenche o lugar direto pelo repository (o provedor é Null em teste)."""
    with SessionLocal() as db:
        memory = memory_repository.get_by_id(
            db, user_id=_user_id(client, headers), memory_id=uuid.UUID(memory_id)
        )
        loc = Location(
            latitude=-3.7319, longitude=-38.5267, city=city, country=country,
            country_code=code, geocoded_at=datetime.now(UTC),
        )
        memory_repository.set_location(db, memory=memory, location=loc)


def _registered_on(memory_id: str, day: str) -> None:
    """Muda o DIA DO REGISTRO (created_at), que a API não deixa escrever."""
    with SessionLocal() as db:
        db.execute(
            update(Memory)
            .where(Memory.id == uuid.UUID(memory_id))
            .values(created_at=datetime.fromisoformat(f"{day}T15:00:00+00:00"))
        )
        db.commit()


def _titles(client, headers, query: str) -> list[str]:
    r = client.get(f"/memories?{query}", headers=headers)
    assert r.status_code == 200, r.text
    return [m["title"] for m in r.json()]


def test_exigem_autenticacao(client):
    assert client.get("/me/places").status_code == 401
    assert client.get("/me/days").status_code == 401


def test_colecao_vazia_responde_listas_vazias(client, auth_headers):
    headers = auth_headers()
    assert client.get("/me/places", headers=headers).json() == {
        "cities": [],
        "countries": [],
    }
    assert client.get("/me/days", headers=headers).json() == []


def test_cidades_e_paises_agrupados_da_mais_vivida_para_a_menos(client, auth_headers):
    headers = auth_headers()
    a = _memory(client, headers, title="A")
    b = _memory(client, headers, title="B")
    c = _memory(client, headers, title="C")
    _memory(client, headers, title="Sem lugar")
    _geocode(client, headers, a["id"], city="Lisboa", country="Portugal", code="PT")
    _geocode(client, headers, b["id"], city="Fortaleza", country="Brasil", code="BR")
    _geocode(client, headers, c["id"], city="Fortaleza", country="Brasil", code="BR")

    body = client.get("/me/places", headers=headers).json()

    assert body["cities"] == [
        {"city": "Fortaleza", "country": "Brasil", "country_code": "BR", "memories": 2},
        {"city": "Lisboa", "country": "Portugal", "country_code": "PT", "memories": 1},
    ]
    assert body["countries"] == [
        {"country_code": "BR", "country": "Brasil", "memories": 2, "cities": 1},
        {"country_code": "PT", "country": "Portugal", "memories": 1, "cities": 1},
    ]
    stats = client.get("/me/profile", headers=headers).json()["stats"]
    assert stats["cities"] == len(body["cities"])
    assert stats["countries"] == len(body["countries"])


def test_cidade_homonima_em_outro_pais_e_outro_lugar(client, auth_headers):
    headers = auth_headers()
    es = _memory(client, headers, title="Espanha")
    ve = _memory(client, headers, title="Venezuela")
    _geocode(client, headers, es["id"], city="Valencia", country="Espanha", code="ES")
    _geocode(client, headers, ve["id"], city="Valencia", country="Venezuela", code="VE")

    cities = client.get("/me/places", headers=headers).json()["cities"]
    assert {(c["city"], c["country_code"]) for c in cities} == {
        ("Valencia", "ES"),
        ("Valencia", "VE"),
    }
    assert _titles(client, headers, "city=Valencia&country_code=ES") == ["Espanha"]
    assert sorted(_titles(client, headers, "city=Valencia")) == ["Espanha", "Venezuela"]


def test_filtro_por_pais_aceita_codigo_minusculo(client, auth_headers):
    headers = auth_headers()
    a = _memory(client, headers, title="A")
    b = _memory(client, headers, title="B")
    _geocode(client, headers, a["id"], city="Lisboa", country="Portugal", code="PT")
    _geocode(client, headers, b["id"], city="Fortaleza", country="Brasil", code="BR")

    assert _titles(client, headers, "country_code=pt") == ["A"]


def test_codigo_de_pais_malformado_e_422(client, auth_headers):
    headers = auth_headers()
    assert client.get("/memories?country_code=BRA", headers=headers).status_code == 422
    assert client.get("/memories?country_code=1A", headers=headers).status_code == 422


def test_so_com_foto_ignora_foto_apagada(client, auth_headers, monkeypatch):
    from app.core import storage

    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "upload", lambda *a, **k: None)
    monkeypatch.setattr(storage, "delete", lambda *a, **k: None)
    monkeypatch.setattr(
        storage, "sign_urls", lambda paths, ttl=None: {p: f"https://signed/{p}" for p in paths}
    )
    headers = auth_headers()
    com = _memory(client, headers, title="Com foto")
    _memory(client, headers, title="Sem foto")
    apagada = _memory(client, headers, title="Foto apagada")
    for m in (com, apagada):
        r = client.post(
            f"/memories/{m['id']}/images",
            files={"file": ("x.png", _PNG, "image/png")},
            headers=headers,
        )
        assert r.status_code == 200, r.text
    imagem = client.get(f"/memories/{apagada['id']}", headers=headers).json()["images"][0]
    r = client.delete(f"/memories/{apagada['id']}/images/{imagem['id']}", headers=headers)
    assert r.status_code == 200, r.text

    assert _titles(client, headers, "has_images=true") == ["Com foto"]
    assert len(_titles(client, headers, "has_images=false")) == 3


def test_dias_de_registro_e_o_filtro_do_dia_contam_igual(client, auth_headers):
    headers = auth_headers()
    a = _memory(client, headers, title="A")
    b = _memory(client, headers, title="B")
    c = _memory(client, headers, title="C")
    _registered_on(a["id"], "2026-03-10")
    _registered_on(b["id"], "2026-03-10")
    _registered_on(c["id"], "2026-05-02")

    days = client.get("/me/days", headers=headers).json()
    assert days == [
        {"day": "2026-05-02", "memories": 1},
        {"day": "2026-03-10", "memories": 2},
    ]
    assert client.get("/me/profile", headers=headers).json()["stats"]["active_days"] == 2
    assert sorted(_titles(client, headers, "created_on=2026-03-10")) == ["A", "B"]
    assert _titles(client, headers, "created_on=2026-04-01") == []


def test_filtro_pagina_com_o_mesmo_keyset(client, auth_headers):
    headers = auth_headers()
    ids = []
    for i in range(3):
        m = _memory(client, headers, title=f"P{i}", when=f"2026-0{i + 1}-01")
        _geocode(client, headers, m["id"], city="Porto", country="Portugal", code="PT")
        ids.append(m["id"])
    _memory(client, headers, title="Fora")

    first = client.get("/memories?limit=2&country_code=PT", headers=headers)
    assert [m["title"] for m in first.json()] == ["P2", "P1"]
    cursor = first.headers["X-Next-Cursor"]
    rest = client.get(
        "/memories", params={"cursor": cursor, "country_code": "PT"}, headers=headers
    )
    assert [m["title"] for m in rest.json()] == ["P0"]
    assert "X-Next-Cursor" not in rest.headers


def test_nao_ve_a_colecao_de_outra_pessoa(client, auth_headers):
    dono = auth_headers("dono@example.com")
    outro = auth_headers("outro@example.com")
    m = _memory(client, dono, title="Minha")
    _geocode(client, dono, m["id"], city="Lisboa", country="Portugal", code="PT")

    assert client.get("/me/places", headers=outro).json()["cities"] == []
    assert client.get("/me/days", headers=outro).json() == []
    assert _titles(client, outro, "country_code=PT") == []
