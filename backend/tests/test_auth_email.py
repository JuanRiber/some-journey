"""Normalização de e-mail na auth: register/login canonizam para strip+lowercase.

Garante que a rota HTTP converge para a mesma forma que os scripts (seed/reset)
já usam, evitando conta duplicada por case e login que falharia só por maiúscula.
"""


def test_register_normalizes_email(client):
    # Espaços nas pontas + maiúsculas: o cadastro grava a forma canônica.
    r = client.post(
        "/auth/register",
        json={"name": "X", "email": "  Foo@Example.COM  ", "password": "whatever12345"},
    )
    assert r.status_code == 201, r.text
    assert r.json()["email"] == "foo@example.com"


def test_login_is_case_insensitive_to_email(client):
    client.post(
        "/auth/register",
        json={"name": "X", "email": "person@example.com", "password": "whatever12345"},
    )
    # Case diferente do cadastro ainda casa, porque o login normaliza igual.
    r = client.post(
        "/auth/login",
        json={"email": "PERSON@Example.com", "password": "whatever12345"},
    )
    assert r.status_code == 200, r.text
    assert r.json()["access_token"]


def test_register_rejects_case_variant_as_duplicate(client):
    first = client.post(
        "/auth/register",
        json={"name": "X", "email": "dup@example.com", "password": "whatever12345"},
    )
    assert first.status_code == 201, first.text
    # Mesma conta com case diferente -> 409 (não cria uma segunda linha).
    second = client.post(
        "/auth/register",
        json={"name": "Y", "email": "DUP@Example.com", "password": "whatever12345"},
    )
    assert second.status_code == 409
