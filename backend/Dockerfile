# Backend FastAPI do Some Journey — imagem de deploy (Render / Koyeb / Cloud Run).
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt ./
RUN pip install -r requirements.txt

COPY . .

# Boot via script resiliente: aplica migrations com retry/backoff (sobrevive a
# banco acordando/blip de conexão) e só então sobe a API (2 workers, suficiente
# para o free tier). $PORT é injetado pela plataforma. Roda via `sh` (não depende
# do bit de executável nem do shebang).
CMD ["sh", "scripts/start.sh"]
