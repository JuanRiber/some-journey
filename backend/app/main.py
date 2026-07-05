from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware

import app.models  # noqa: F401 - register models in SQLAlchemy metadata
from app.api.routes import auth, journey, map, memory
from app.core.body_limit import BodySizeLimitMiddleware
from app.core.config import settings


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # O schema é gerido por migrations versionadas (Alembic): rode
    # `alembic upgrade head` antes de subir a API. Não criamos tabelas no
    # startup — isso mascarava drift (create_all nunca altera tabelas existentes).
    yield


def create_app() -> FastAPI:
    """Fábrica do app FastAPI.

    Em produção (APP_ENV=production) os docs interativos (/docs, /redoc) e o
    /openapi.json ficam desabilitados; nos demais ambientes seguem ativos.
    """
    application = FastAPI(
        title="Some Journey API",
        version="0.1.0",
        lifespan=lifespan,
        docs_url=None if settings.is_production else "/docs",
        redoc_url=None if settings.is_production else "/redoc",
        openapi_url=None if settings.is_production else "/openapi.json",
    )

    # Guarda de tamanho de corpo. Adicionado PRIMEIRO => fica como middleware
    # mais INTERNO: roda depois de CORS/TrustedHost (a resposta 413 sai decorada
    # por eles), mas ainda ANTES de o handler ler/bufferizar o corpo.
    application.add_middleware(
        BodySizeLimitMiddleware,
        max_body_bytes=settings.MAX_JSON_BODY_BYTES,
        # o multipart embrulha o arquivo — dá uma folga sobre MAX_IMAGE_BYTES.
        upload_max_body_bytes=settings.MAX_IMAGE_BYTES + 1024 * 1024,
    )

    application.add_middleware(
        TrustedHostMiddleware,
        allowed_hosts=settings.trusted_hosts,
    )

    application.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_allowed_origins,
        allow_origin_regex=settings.CORS_ALLOW_ORIGIN_REGEX,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
    )

    application.include_router(auth.router)
    application.include_router(memory.router)
    application.include_router(journey.router)
    application.include_router(map.router)

    @application.get("/health")
    def health_check() -> dict[str, str]:
        return {"status": "ok"}

    return application


app = create_app()
