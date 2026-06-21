from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

import app.models  # noqa: F401 — importa os models para registrá-los no metadata
from app.api.routes import auth
from app.db.base import Base
from app.db.session import engine


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # MVP: cria as tabelas no startup (idempotente). Em produção, migrar para
    # migrations versionadas (Alembic) em vez de create_all.
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(
    title="Some Journey API",
    version="0.1.0",
    lifespan=lifespan,
)

# CORS: em desenvolvimento liberamos qualquer porta de localhost (Expo web/Metro).
# Em produção, troque por uma lista EXPLÍCITA das origens reais do app
# (nunca "*" junto com allow_credentials=True).
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://localhost:\d+",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)


@app.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "ok"}
