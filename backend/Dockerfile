# Backend FastAPI do Some Journey — imagem de deploy (Render / Koyeb / Cloud Run).
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt ./
RUN pip install -r requirements.txt

COPY . .

# Sem root. Se algo dentro da API um dia for explorado, o processo não manda no
# contêiner: os arquivos do app são do root e só legíveis para este usuário.
# Ele não precisa escrever nada — o Python não grava .pyc (acima), as fotos vão
# para o Storage e os logs para a saída padrão.
RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin app
USER app

# Boot via script resiliente: aplica migrations com retry/backoff (sobrevive a
# banco acordando/blip de conexão) e só então sobe a API (um processo; ver o
# porquê no próprio script). $PORT é injetado pela plataforma. Roda via `sh`
# (não depende do bit de executável nem do shebang).
CMD ["sh", "scripts/start.sh"]
