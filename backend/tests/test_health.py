"""Health checks: /health (liveness, NÃO toca o banco) e /health/ready
(readiness, executa SELECT 1). Com o banco de teste no ar os dois respondem 200.
O keep-warm bate no /health/ready para aquecer também o caminho do banco."""


def test_health_liveness_returns_ok(client):
    # Liveness: independe do banco — só confirma que o processo responde.
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_health_ready_returns_ready_when_db_up(client):
    # Readiness: roda SELECT 1 numa sessão curta; 200 com o banco disponível.
    r = client.get("/health/ready")
    assert r.status_code == 200
    assert r.json() == {"status": "ready"}
