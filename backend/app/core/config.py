from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # HTTP edge / environment
    APP_ENV: Literal["development", "production", "test"] = "development"
    CORS_ALLOWED_ORIGINS: str = "http://localhost:8081,http://127.0.0.1:8081,http://localhost:19006"
    CORS_ALLOW_ORIGIN_REGEX: str | None = r"http://(localhost|127\.0\.0\.1):\d+"
    TRUSTED_HOSTS: str = "localhost,127.0.0.1,10.0.2.2"

    # Database
    DATABASE_URL: str

    # Auth / JWT
    JWT_SECRET_KEY: str = Field(min_length=32)
    JWT_ALGORITHM: Literal["HS256"] = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(default=60, gt=0, le=1440)

    # Per-process guard for public auth endpoints. In production, keep this and
    # add an infrastructure-level limiter shared by all workers.
    AUTH_RATE_LIMIT_ATTEMPTS: int = Field(default=8, gt=0, le=100)
    AUTH_RATE_LIMIT_WINDOW_SECONDS: int = Field(default=300, ge=30, le=3600)

    # Storage de imagens (Supabase). OPCIONAL: sem SUPABASE_URL +
    # SUPABASE_SERVICE_KEY o upload fica desabilitado (o endpoint responde 503) e
    # image_url volta None. Bucket PRIVADO: o backend gera URLs assinadas de
    # curta duração na leitura; o service key NUNCA chega ao cliente.
    SUPABASE_URL: str | None = None
    SUPABASE_SERVICE_KEY: str | None = None
    SUPABASE_BUCKET: str = "memories"
    # Validade da URL assinada (s) e teto do upload (bytes).
    IMAGE_SIGNED_URL_TTL: int = Field(default=3600, ge=60, le=604800)
    MAX_IMAGE_BYTES: int = Field(default=5 * 1024 * 1024, gt=0, le=52428800)

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @staticmethod
    def _csv(value: str) -> list[str]:
        return [item.strip() for item in value.split(",") if item.strip()]

    @property
    def cors_allowed_origins(self) -> list[str]:
        return self._csv(self.CORS_ALLOWED_ORIGINS)

    @property
    def trusted_hosts(self) -> list[str]:
        return self._csv(self.TRUSTED_HOSTS)

    @property
    def storage_enabled(self) -> bool:
        """True só quando o Supabase Storage está configurado."""
        return bool(self.SUPABASE_URL and self.SUPABASE_SERVICE_KEY)


settings = Settings()
