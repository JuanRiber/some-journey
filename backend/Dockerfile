# Backend FastAPI do Some Journey — imagem de deploy (Render / Koyeb / Cloud Run).
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt ./
RUN pip install -r requirements.txt

COPY . .

# A plataforma injeta a porta em $PORT. Aplica as migrations e sobe a API.
# (2 workers: o suficiente para poucos usuários no free tier.)
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 2"]
