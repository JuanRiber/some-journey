"""Entrega de e-mail transacional (SMTP), hoje usada só pela recuperação de senha.

Abstração fina e PLUGÁVEL: se o SMTP estiver configurado (settings.smtp_enabled),
envia de verdade via smtplib; caso contrário faz um fallback seguro:
- fora de produção, LOGA o link de reset (com o token) para os testers usarem;
- em produção, LOGA um erro dizendo que o SMTP não está configurado — NUNCA o
  token (não vaza segredo em log de produção).

Regras de ouro:
- NUNCA logar o token em produção. NUNCA logar senha, hash ou o corpo cru.
- O envio nunca deve derrubar a requisição: falha de SMTP é engolida (logada
  sem PII) — o contrato anti-enumeração da rota exige resposta genérica sempre.
- Chamado a partir de um BackgroundTask do FastAPI: roda DEPOIS da resposta, sem
  somar latência de rede ao request nem criar um oráculo de timing.
"""

import logging
import smtplib
from email.message import EmailMessage

from app.core.config import settings

logger = logging.getLogger("app.email")


def _reset_link(raw_token: str) -> str:
    """Monta o link de redefinição a partir da base + token na querystring."""
    base = settings.PASSWORD_RESET_URL_BASE.rstrip("/")
    sep = "&" if "?" in base else "?"
    return f"{base}{sep}token={raw_token}"


def _build_reset_message(to_email: str, raw_token: str) -> EmailMessage:
    link = _reset_link(raw_token)
    ttl = settings.PASSWORD_RESET_TOKEN_TTL_MINUTES
    msg = EmailMessage()
    msg["Subject"] = "Redefinir sua senha — Some Journey"
    msg["From"] = settings.SMTP_FROM or "no-reply@some-journey.app"
    msg["To"] = to_email
    msg.set_content(
        "Você pediu para redefinir a senha da sua conta no Some Journey.\n\n"
        f"Abra este link para escolher uma nova senha (expira em {ttl} minutos):\n"
        f"{link}\n\n"
        "Se não foi você, ignore este e-mail — sua senha continua a mesma."
    )
    return msg


def send_password_reset(to_email: str, raw_token: str) -> None:
    """Entrega o e-mail de recuperação de senha (best-effort).

    Sem SMTP configurado: fallback logado (token só fora de produção). Com SMTP:
    envia via STARTTLS quando habilitado. Qualquer falha é logada SEM PII e
    engolida — a rota responde genericamente de qualquer forma."""
    if not settings.smtp_enabled:
        if settings.is_production:
            logger.error(
                "Password reset requested but SMTP is not configured; email not sent."
            )
        else:
            # Dev/test: os testers pegam o link direto do log do servidor.
            logger.warning("[dev] Password reset link: %s", _reset_link(raw_token))
        return

    message = _build_reset_message(to_email, raw_token)
    try:
        with smtplib.SMTP(
            settings.SMTP_HOST, settings.SMTP_PORT, timeout=settings.SMTP_TIMEOUT_SECONDS
        ) as server:
            if settings.SMTP_STARTTLS:
                server.starttls()
            if settings.SMTP_USERNAME and settings.SMTP_PASSWORD:
                server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
            server.send_message(message)
    except Exception as exc:  # noqa: BLE001 - nunca derrubar a rota por falha de e-mail
        # Loga o TIPO do erro, nunca o destinatário nem o token.
        logger.error("Failed to send password reset email: %s", type(exc).__name__)
