"""O limite de tentativas mora no banco.

O que estes testes prendem é o motivo da mudança: a contagem não pode depender
de nada que viva na memória do processo — nem para sobreviver a um reinício,
nem para valer igual com mais de um processo.
"""

from concurrent.futures import ThreadPoolExecutor

from sqlalchemy import text

from app.core import rate_limit
from app.core.rate_limit import check_rate_limit, purge_expired


def _linhas(db_session) -> list[tuple[str, int]]:
    return [
        (key, attempts)
        for key, attempts in db_session.execute(
            text("SELECT key, attempts FROM auth_rate_limits ORDER BY key")
        )
    ]


def test_conta_ate_o_teto_e_recusa_a_seguinte():
    resultados = [
        check_rate_limit("t", ["a"], max_attempts=3, window_seconds=60)
        for _ in range(4)
    ]

    assert [ok for ok, _ in resultados] == [True, True, True, False]
    assert resultados[0][1] == 0
    assert 1 <= resultados[3][1] <= 60


def test_a_contagem_esta_na_tabela_e_nao_no_processo(db_session):
    """Um reinício da API não tem o que zerar: o módulo não guarda balde."""
    for _ in range(2):
        check_rate_limit("t", ["a"], max_attempts=5, window_seconds=60)

    assert not hasattr(rate_limit, "_buckets")
    assert [attempts for _, attempts in _linhas(db_session)] == [2]


def test_a_chave_nao_guarda_email_nem_ip(db_session):
    check_rate_limit(
        "login", ["203.0.113.9", "ana@example.com"], max_attempts=5, window_seconds=60
    )

    (chave, _), = _linhas(db_session)
    assert chave.startswith("login:")
    assert "ana" not in chave and "203.0.113.9" not in chave


def test_baldes_diferentes_nao_se_somam():
    for _ in range(3):
        check_rate_limit("t", ["a"], max_attempts=3, window_seconds=60)

    ok, _ = check_rate_limit("t", ["b"], max_attempts=3, window_seconds=60)
    assert ok is True


def test_janela_vencida_recomeca_do_um(db_session):
    for _ in range(4):
        check_rate_limit("t", ["a"], max_attempts=3, window_seconds=60)
    db_session.execute(
        text(
            "UPDATE auth_rate_limits "
            "SET window_started_at = now() - interval '61 seconds'"
        )
    )
    db_session.commit()

    ok, espera = check_rate_limit("t", ["a"], max_attempts=3, window_seconds=60)

    assert (ok, espera) == (True, 0)
    assert [attempts for _, attempts in _linhas(db_session)] == [1]


def test_quem_insiste_depois_do_429_nao_ganha_a_vaga_de_volta():
    for _ in range(10):
        check_rate_limit("t", ["a"], max_attempts=3, window_seconds=60)

    ok, espera = check_rate_limit("t", ["a"], max_attempts=3, window_seconds=60)
    assert ok is False and espera >= 1


def test_tentativas_simultaneas_sao_todas_contadas(db_session):
    """Duas tentativas ao mesmo tempo nunca leem o mesmo número: com a contagem
    em memória de dois processos, cada um veria metade."""
    total = 40

    def tentar(_):
        return check_rate_limit("t", ["a"], max_attempts=25, window_seconds=60)[0]

    with ThreadPoolExecutor(max_workers=8) as pool:
        permitidas = sum(pool.map(tentar, range(total)))

    assert permitidas == 25
    assert [attempts for _, attempts in _linhas(db_session)] == [total]


def test_a_faxina_apaga_so_o_que_venceu_ha_muito(db_session):
    check_rate_limit("t", ["velho"], max_attempts=3, window_seconds=60)
    db_session.execute(
        text(
            "UPDATE auth_rate_limits "
            "SET window_started_at = now() - interval '2 days'"
        )
    )
    db_session.commit()
    check_rate_limit("t", ["novo"], max_attempts=3, window_seconds=60)

    assert purge_expired() == 1
    assert len(_linhas(db_session)) == 1


def test_o_login_bloqueado_continua_bloqueado_sem_estado_em_memoria(
    client, monkeypatch
):
    """De ponta a ponta: o 429 do login vem da tabela."""
    from app.core.config import settings

    monkeypatch.setattr(settings, "AUTH_RATE_LIMIT_ATTEMPTS", 2)
    corpo = {"email": "ninguem@test.com", "password": "errada-errada"}

    respostas = [client.post("/auth/login", json=corpo).status_code for _ in range(3)]

    assert respostas == [401, 401, 429]
    # "Reiniciar" a API não muda nada: não há o que perder.
    rate_limit._last_purge = None
    assert client.post("/auth/login", json=corpo).status_code == 429
