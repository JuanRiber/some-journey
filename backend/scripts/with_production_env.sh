#!/usr/bin/env sh
# Roda um comando com as credenciais de PRODUÇÃO de backend/production.env.
#
#   sh scripts/with_production_env.sh .venv/bin/python -m scripts.check_database
#   sh scripts/with_production_env.sh .venv/bin/python -m scripts.seed_users tester@exemplo.com
#
# Existe para a senha do banco nunca aparecer na linha de comando (e, portanto,
# no histórico do terminal). As variáveis do arquivo valem só para o comando
# dado; o shell de quem chamou não as herda.
set -eu

cd "$(dirname "$0")/.."

if [ "$#" -eq 0 ]; then
  echo "uso: sh scripts/with_production_env.sh <comando> [args...]" >&2
  exit 2
fi

if [ ! -f production.env ]; then
  echo "backend/production.env não existe." >&2
  echo "Copie backend/production.env.example para backend/production.env e preencha." >&2
  exit 1
fi

# Um arquivo de produção versionado por engano vazaria a senha no GitHub.
if git ls-files --error-unmatch production.env >/dev/null 2>&1; then
  echo "ERRO: backend/production.env está no git. Remova-o do índice (git rm --cached) e troque a senha do banco." >&2
  exit 1
fi

set -a
. ./production.env
set +a

exec "$@"
