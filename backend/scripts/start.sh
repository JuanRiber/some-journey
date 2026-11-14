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

# --proxy-headers + --forwarded-allow-ips='*': em produção a API roda ATRÁS do
# proxy do Render, então request.client.host seria sempre o IP do proxy. Sem
# isto, o rate limit por IP (login/register/change-password) colapsaria num
# ÚNICO balde global (o do proxy) — um atacante afogaria todo mundo. Com os
# proxy-headers, o uvicorn lê o X-Forwarded-For e request.client passa a refletir
# o IP real do cliente. Confiamos no XFF porque no Render só o proxy da própria
# plataforma alcança o container (borda controlada); daí o '*'.
# LIMITE CONHECIDO: com '*' o uvicorn usa a entrada mais à ESQUERDA do XFF, que
# o cliente pode escrever se o proxy acrescenta em vez de sobrescrever. O balde
# por e-mail do rate limit (app/api/routes/auth.py) não depende de IP e segura
# o brute-force numa conta; acertar o IP pede ver o XFF real em produção.
#
# UM processo por padrão (WEB_CONCURRENCY sobrepõe). No plano grátis do Render a
# máquina tem uma fração de CPU: um segundo processo não traz CPU, só gasta RAM
# — e partia ao meio tudo o que mora em memória de processo. Com 2, o teto de
# tentativas de login era ~40 por janela em vez de 20 (cada processo contava o
# seu), e o intervalo de 1 s do Nominatim virava ~2 por segundo. As rotas
# síncronas rodam num pool de threads; um processo atende vários pedidos.
#
# --no-server-header: a resposta não anuncia qual servidor está do outro lado.
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}" \
  --workers "${WEB_CONCURRENCY:-1}" --no-server-header \
  --proxy-headers --forwarded-allow-ips='*'
