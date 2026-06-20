from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Banco de dados
    DATABASE_URL: str

    # Autenticação / JWT
    # min_length=32: a app NÃO sobe com secret fraco. O HS256 (RFC 7518) exige
    # uma chave de pelo menos 32 bytes — fail-fast em vez de aviso silencioso.
    JWT_SECRET_KEY: str = Field(min_length=32)
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


settings = Settings()
