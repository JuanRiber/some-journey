from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

# Regex de origem CORS para DESENVOLVIMENTO: aceita localhost/127.0.0.1 em
# qualquer porta (Expo/Vite trocam de porta o tempo todo). É o default do campo
# CORS_ALLOW_ORIGIN_REGEX; a property cors_allow_origin_regex o SUPRIME em
# produção (ver abaixo) para que esse curinga de dev jamais vaze para o ar.
_DEV_CORS_ORIGIN_REGEX = r"http://(localhost|127\.0\.0\.1):\d+"


class Settings(BaseSettings):
    # HTTP edge / environment
    APP_ENV: Literal["development", "production", "test"] = "development"
    CORS_ALLOWED_ORIGINS: str = "http://localhost:8081,http://127.0.0.1:8081,http://localhost:19006"
    CORS_ALLOW_ORIGIN_REGEX: str | None = _DEV_CORS_ORIGIN_REGEX
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
    # Teto por IP (independe do email) na mesma janela — trava password spraying
    # (uma senha testada contra muitos e-mails do mesmo IP). Maior que o por-conta.
    AUTH_RATE_LIMIT_IP_ATTEMPTS: int = Field(default=40, gt=0, le=1000)

    # Cadastro público. Se não definido, herda do ambiente: aberto em dev/test e
    # FECHADO em produção (as contas dos testers vêm do seed). Force com
    # REGISTRATION_OPEN=true/false para sobrepor.
    REGISTRATION_OPEN: bool | None = None

    # --- Geocodificação reversa (lugar da memória) ---
    # Ligada por padrão: em produção o lugar É parte do produto (Passaporte,
    # estatísticas, filtros). Desligue para rodar offline. O Nominatim exige um
    # User-Agent identificável com contato — configure o seu.
    GEOCODING_ENABLED: bool = True
    GEOCODING_USER_AGENT: str = "SomeJourney/1.0 (contato: suporte@some-journey.app)"

    # --- Recuperação de senha ---
    # Validade do token de reset (minutos) e destino do link entregue por e-mail.
    # PASSWORD_RESET_URL_BASE recebe o token como querystring `?token=`; aponte
    # para a rota do app (deep link) ou para a página web de redefinição.
    PASSWORD_RESET_TOKEN_TTL_MINUTES: int = Field(default=30, ge=5, le=1440)
    PASSWORD_RESET_URL_BASE: str = "https://some-journey.pages.dev/reset-password"

    # --- E-mail (SMTP) ---
    # OPCIONAL: sem SMTP_HOST + SMTP_FROM o envio fica desabilitado. Nesse caso,
    # fora de produção o token de reset é LOGADO (para os testers); em produção
    # o envio apenas registra um erro (nunca loga o token). Configure para valer.
    SMTP_HOST: str | None = None
    SMTP_PORT: int = Field(default=587, gt=0, le=65535)
    SMTP_USERNAME: str | None = None
    SMTP_PASSWORD: str | None = None
    SMTP_FROM: str | None = None
    SMTP_STARTTLS: bool = True
    SMTP_TIMEOUT_SECONDS: int = Field(default=10, ge=1, le=60)

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
    # Teto do corpo de requests JSON/comuns. O middleware de limite rejeita
    # (413) antes de o corpo ser bufferizado. Uploads de imagem usam um teto
    # próprio derivado de MAX_IMAGE_BYTES (ver app/main.py).
    MAX_JSON_BODY_BYTES: int = Field(default=1 * 1024 * 1024, gt=0, le=52428800)

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
    def cors_allow_origin_regex(self) -> str | None:
        """Regex de origem CORS efetivo — usado pelo CORSMiddleware no main.py.

        Em produção devolve None SALVO se CORS_ALLOW_ORIGIN_REGEX foi
        explicitamente definido para um valor DIFERENTE do curinga de dev: o
        regex localhost/127.0.0.1 de desenvolvimento jamais pode valer no ar
        (deixaria qualquer app local passar pelo CORS). Fora de produção, ou
        quando o operador sobrepõe o valor de propósito, devolve o valor como
        está (inclusive None, se alguém quis desligar o regex)."""
        if self.is_production and self.CORS_ALLOW_ORIGIN_REGEX == _DEV_CORS_ORIGIN_REGEX:
            return None
        return self.CORS_ALLOW_ORIGIN_REGEX

    @property
    def trusted_hosts(self) -> list[str]:
        return self._csv(self.TRUSTED_HOSTS)

    @property
    def storage_enabled(self) -> bool:
        """True só quando o Supabase Storage está configurado — e NUNCA em teste.

        O corte por APP_ENV é proteção real: o `.env` de desenvolvimento tem
        credenciais VÁLIDAS do Supabase, então sem isto a suíte gravava arquivos
        no bucket de verdade (foi o que aconteceu ao subir um avatar num teste).
        Testes não podem escrever em serviço de terceiros nem sujar produção;
        quem precisa exercitar o upload monkeypatcha `storage.enabled`."""
        if self.APP_ENV == "test":
            return False
        return bool(self.SUPABASE_URL and self.SUPABASE_SERVICE_KEY)

    @property
    def is_production(self) -> bool:
        """True em produção — usado para desabilitar docs/openapi, etc."""
        return self.APP_ENV == "production"

    @property
    def geocoding_enabled(self) -> bool:
        """Geocodificar de verdade? Nunca em TESTE — a suíte não pode depender de
        rede nem bater num serviço público de terceiros."""
        return self.GEOCODING_ENABLED and self.APP_ENV != "test"

    @property
    def smtp_enabled(self) -> bool:
        """True só quando o envio de e-mail (SMTP) está configurado."""
        return bool(self.SMTP_HOST and self.SMTP_FROM)

    @property
    def registration_open(self) -> bool:
        """Cadastro liberado? Explícito via REGISTRATION_OPEN; senão, fechado em
        produção e aberto fora dela."""
        if self.REGISTRATION_OPEN is not None:
            return self.REGISTRATION_OPEN
        return not self.is_production


settings = Settings()
