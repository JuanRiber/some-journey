"""Cria/garante as contas dos testers (idempotente).

Uso (com DATABASE_URL apontando pro banco de destino — ex.: o Postgres do
Supabase em produção):

    python -m scripts.seed_users email1@x.com email2@x.com email3@x.com

Gera uma senha forte por conta e imprime as credenciais UMA vez. Contas que já
existem são puladas. Roda pelo SERVICE (não pela rota HTTP), então funciona
mesmo com o cadastro fechado (REGISTRATION_OPEN=false) em produção.
"""

import secrets
import sys

from app.db.session import SessionLocal
from app.repositories import user_repository
from app.schemas.auth import RegisterRequest
from app.services import auth_service


def _password() -> str:
    # ~20 chars url-safe: bem acima do mínimo de 10, sem símbolos problemáticos.
    return secrets.token_urlsafe(15)


def main(emails: list[str]) -> None:
    db = SessionLocal()
    created: list[tuple[str, str]] = []
    try:
        for raw in emails:
            email = raw.strip().lower()
            if not email:
                continue
            if user_repository.get_by_email(db, email) is not None:
                print(f"=  {email}  (já existe, pulado)")
                continue
            pw = _password()
            auth_service.register(
                db,
                RegisterRequest(name=email.split("@")[0], email=email, password=pw),
            )
            created.append((email, pw))
            print(f"+  {email}  senha: {pw}")
    finally:
        db.close()
    if created:
        print("\nGuarde estas credenciais — a senha NÃO será mostrada de novo.")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a]
    if not args:
        print("uso: python -m scripts.seed_users email1 [email2 ...]")
        raise SystemExit(1)
    main(args)
