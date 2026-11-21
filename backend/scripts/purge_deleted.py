"""Roda o expurgo à mão: apaga de vez o que foi apagado há mais que o prazo.

A API já faz isso sozinha de tempos em tempos (PURGE_INTERVAL_HOURS). Este
script é para quando se quer rodar AGORA, ou ver o que sairia antes de sair.

Uso (a partir de `backend/`, com o .venv ativo; em produção, pelo
`scripts/with_production_env.sh`):

    python -m scripts.purge_deleted --dry-run     # só conta, não apaga nada
    python -m scripts.purge_deleted               # apaga
    python -m scripts.purge_deleted --days 90     # com outro prazo de retenção

Não imprime caminho, e-mail nem id: só contagens.
"""

import argparse

from app.core.config import settings
from app.db.session import SessionLocal
from app.services import purge_service


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true", help="só conta, não apaga")
    parser.add_argument(
        "--days",
        type=int,
        default=settings.PURGE_DELETED_AFTER_DAYS,
        help=f"prazo de retenção em dias (padrão: {settings.PURGE_DELETED_AFTER_DAYS})",
    )
    args = parser.parse_args(argv)
    if args.days < 1:
        parser.error("--days precisa ser 1 ou mais")

    with SessionLocal() as db:
        if args.dry_run:
            r = purge_service.preview(db, older_than_days=args.days)
            print(f"Sairiam (apagados há mais de {args.days} dias):")
        else:
            r = purge_service.purge_expired(db, older_than_days=args.days)
            print(f"Saíram (apagados há mais de {args.days} dias):")

    print(f"  memórias ............ {r.memories}")
    print(f"  jornadas ............ {r.journeys}")
    print(f"  trechos de GPS ...... {r.tracks}")
    print(f"  fases ............... {r.life_phases}")
    print(f"  fotos/músicas/vínculos soltos ... {r.detached}")
    if args.dry_run:
        print(f"  arquivos já na fila . {r.files_queued}")
    else:
        print(f"  tokens vencidos ..... {r.tokens}")
        print(f"  arquivos: {r.files_queued} na fila, {r.files_deleted} apagados, "
              f"{r.files_failed} a tentar de novo")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
