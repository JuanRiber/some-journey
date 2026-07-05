"""Reseta a senha de contas EXISTENTES.

O seed (scripts.seed_users) PULA quem já existe, então não serve para trocar
senha. Este script troca a senha de contas que já existem.

Uso (com DATABASE_URL apontando pro banco de destino — ex.: o Supabase de prod):
    python -m scripts.reset_password email1@x.com [email2@x.com ...]
    python -m scripts.reset_password email1@x.com --password "SenhaEscolhida123"

Sem --password: gera uma senha forte por conta e imprime UMA vez.
Com --password: aplica a mesma senha (>= 10 caracteres) a todos os e-mails.
Não cria contas — e-mails inexistentes são reportados e pulados.
"""

import secrets
import sys

from app.core.security import hash_password
from app.db.session import SessionLocal
from app.repositories import user_repository


def _password() -> str:
    return secrets.token_urlsafe(15)


def _parse(argv: list[str]) -> tuple[list[str], str | None]:
    emails: list[str] = []
    chosen: str | None = None
    i = 0
    while i < len(argv):
        if argv[i] == "--password":
            if i + 1 >= len(argv):
                print("--password exige um valor.")
                raise SystemExit(1)
            chosen = argv[i + 1]
            i += 2
        else:
            emails.append(argv[i])
            i += 1
    return emails, chosen


def main(emails: list[str], chosen: str | None) -> None:
    if chosen is not None and len(chosen) < 10:
        print("A senha escolhida precisa ter pelo menos 10 caracteres.")
        raise SystemExit(1)
    db = SessionLocal()
    changed: list[tuple[str, str]] = []
    try:
        for raw in emails:
            email = raw.strip().lower()
            if not email:
                continue
            user = user_repository.get_by_email(db, email)
            if user is None:
                print(f"!  {email}  (não existe — pulado)")
                continue
            pw = chosen or _password()
            user_repository.set_password_hash(
                db, user=user, password_hash=hash_password(pw)
            )
            changed.append((email, pw))
            print(f"~  {email}  nova senha: {pw}")
    finally:
        db.close()
    if changed:
        print("\nGuarde estas senhas — não serão mostradas de novo.")


if __name__ == "__main__":
    emails, chosen = _parse(sys.argv[1:])
    if not emails:
        print("uso: python -m scripts.reset_password email1 [email2 ...] [--password SENHA]")
        raise SystemExit(1)
    main(emails, chosen)
