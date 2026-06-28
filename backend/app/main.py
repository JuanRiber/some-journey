from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware

import app.models  # noqa: F401 - register models in SQLAlchemy metadata
from app.api.routes import auth, journey, map, memory
from app.core.config import settings


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # O schema é gerido por migrations versionadas (Alembic): rode
    # `alembic upgrade head` antes de subir a API. Não criamos tabelas no
    # startup — isso mascarava drift (create_all nunca altera tabelas existentes).
    yield


app = FastAPI(
    title="Some Journey API",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=settings.trusted_hosts,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allowed_origins,
    allow_origin_regex=settings.CORS_ALLOW_ORIGIN_REGEX,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

app.include_router(auth.router)
app.include_router(memory.router)
app.include_router(journey.router)
app.include_router(map.router)


@app.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "ok"}
