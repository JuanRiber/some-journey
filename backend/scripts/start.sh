#!/usr/bin/env sh
# Boot resiliente da API (usado pelo Dockerfile em produção).
#
# Problema que isto resolve: o CMD antigo era `alembic upgrade head && uvicorn`.
# Se o banco (ex.: Supabase free) estivesse acordando/pausado ou desse um blip
# de conexão, o `alembic` falhava e o container morria — derrubando TODA a API
# (503 até no /health, que nem depende do banco). Aqui tentamos a migration
# algumas vezes com backoff antes de desistir e só então falhamos, com log claro
# (visível nos Logs do Render). Se as migrations passam, sobe o uvicorn.
set -u

ATTEMPTS="${MIGRATE_ATTEMPTS:-12}"
SLEEP_SECONDS="${MIGRATE_RETRY_SECONDS:-5}"

i=1
while :; do
  echo "[start] alembic upgrade head (tentativa ${i}/${ATTEMPTS})"
  if alembic upgrade head; then
    echo "[start] migrations OK"
    break
  fi
  if [ "${i}" -ge "${ATTEMPTS}" ]; then
    echo "[start] ERRO: migrations falharam apos ${ATTEMPTS} tentativas."
    echo "[start] Causa provavel: banco inacessivel/pausado (ex.: Supabase free hibernado)"
    echo "[start] ou DATABASE_URL incorreta. Verifique o banco e o env do servico."
    exit 1
  fi
  echo "[start] falhou; aguardando ${SLEEP_SECONDS}s (o banco pode estar acordando)..."
  sleep "${SLEEP_SECONDS}"
  i=$((i + 1))
done

exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}" --workers 2
