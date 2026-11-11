"""Pool de conexões configurável (DB_POOL_SIZE / DB_MAX_OVERFLOW).

Em produção o banco fica atrás do pooler do Supabase grátis, que aceita poucas
conexões; o render.yaml baixa o pool por variável de ambiente. Estes testes
garantem que a variável chega de fato ao engine — um valor lido e ignorado
passaria em qualquer revisão e só apareceria como "max clients reached" no ar.
"""

import pytest
from pydantic import ValidationError

from app.core.config import Settings, settings
from app.db.session import engine


def test_engine_uses_configured_pool_size():
    assert engine.pool.size() == settings.DB_POOL_SIZE
    assert engine.pool._max_overflow == settings.DB_MAX_OVERFLOW


def test_pool_settings_come_from_environment(monkeypatch):
    monkeypatch.setenv("DB_POOL_SIZE", "3")
    monkeypatch.setenv("DB_MAX_OVERFLOW", "2")
    configured = Settings()
    assert configured.DB_POOL_SIZE == 3
    assert configured.DB_MAX_OVERFLOW == 2


def test_pool_defaults_are_sqlalchemy_defaults(monkeypatch):
    # Em desenvolvimento nada muda: os padrões são os que o engine já usava.
    monkeypatch.delenv("DB_POOL_SIZE", raising=False)
    monkeypatch.delenv("DB_MAX_OVERFLOW", raising=False)
    configured = Settings(_env_file=None)
    assert configured.DB_POOL_SIZE == 5
    assert configured.DB_MAX_OVERFLOW == 10


@pytest.mark.parametrize(
    ("name", "value"),
    [("DB_POOL_SIZE", "0"), ("DB_MAX_OVERFLOW", "-1")],
)
def test_pool_rejects_impossible_values(monkeypatch, name, value):
    # Pool zero não abre conexão nenhuma; o erro tem de vir no boot, não no
    # primeiro request.
    monkeypatch.setenv(name, value)
    with pytest.raises(ValidationError):
        Settings()
