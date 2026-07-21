from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from sqlalchemy import text

import app.models  # noqa: F401 - register models in SQLAlchemy metadata
from app.api.routes import auth, journey, map, memory, track
from app.core.body_limit import BodySizeLimitMiddleware
from app.core.config import settings
from app.core.pagination import NEXT_CURSOR_HEADER
from app.db.session import SessionLocal


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
        # Property (não o campo cru): em produção suprime o regex localhost de dev.
        allow_origin_regex=settings.cors_allow_origin_regex,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
        # O contrato de paginação por cursor devolve o próximo cursor neste
        # header; sem expô-lo, o navegador o esconde do cliente (fetch/XHR).
        expose_headers=[NEXT_CURSOR_HEADER],
    )

    application.include_router(auth.router)
    application.include_router(memory.router)
    application.include_router(journey.router)
    application.include_router(track.router)
    application.include_router(map.router)

    @application.get("/health")
    def health_check() -> dict[str, str]:
        # LIVENESS: o processo está de pé? NÃO toca o banco de propósito — se o
        # Postgres estiver dormindo/instável (ex.: Supabase free), o container
        # ainda responde 200 aqui e não é morto pelo health check do Render.
        return {"status": "ok"}

    @application.get("/health/ready")
    def health_ready() -> dict[str, str]:
        # READINESS: o app consegue FALAR com o banco? Roda um SELECT 1 numa
        # sessão curta (aberta e fechada aqui, fora do get_db de request) e
        # devolve 503 se falhar — assim o keep-warm que bate aqui também aquece
        # o caminho do banco (evita cold start da 1a query real). Não logamos a
        # exceção (pode conter detalhe de conexão); só sinalizamos indisponível.
        db = SessionLocal()
        try:
            db.execute(text("SELECT 1"))
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Database not ready.",
            )
        finally:
            db.close()
        return {"status": "ready"}

    return application


app = create_app()
