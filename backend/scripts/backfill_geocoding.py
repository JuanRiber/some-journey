"""Backfill de geocodificação: resolve o LUGAR de memórias antigas.

Por que existe: memórias criadas antes da migração 0009 (ou cujo provedor falhou
na hora) têm `geocoded_at IS NULL`. Sem isto, o Passaporte e as estatísticas
geográficas do Perfil ficariam vazios para sempre para quem já usa o app.

Uso (a partir de backend/, com o .venv ativo):

    python -m scripts.backfill_geocoding                # processa até 100
    python -m scripts.backfill_geocoding --limit 500
    python -m scripts.backfill_geocoding --dry-run      # só mostra o que faria

Seguro por construção:
- Lê exatamente a fila do índice parcial `ix_memories_pending_geocode`.
- RESPEITA o limite de 1 req/s do Nominatim (o adapter cuida; aqui damos a folga
  entre chamadas para não sermos bloqueados numa execução longa).
- Cada memória é uma transação: uma falha não perde o progresso das anteriores.
- Idempotente: rodar de novo só pega o que ainda falta.
"""

import argparse
import logging
import time

from geoalchemy2.shape import to_shape
from sqlalchemy import select

from app.db.session import SessionLocal
from app.models.memory import Memory
from app.repositories import memory_repository
from app.services import geocoding

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("backfill")

# Um pouco acima do mínimo exigido pelo Nominatim (1 req/s), por educação e para
# não levar bloqueio numa execução longa.
_SLEEP_SECONDS = 1.1


def pending(db, limit: int) -> list[Memory]:
    """A fila: memórias vivas sem lugar resolvido, mais antigas primeiro."""
    return list(
        db.scalars(
            select(Memory)
            .where(Memory.deleted_at.is_(None), Memory.geocoded_at.is_(None))
            .order_by(Memory.created_at)
            .limit(limit)
        )
    )


def run(limit: int, dry_run: bool) -> int:
    provider = geocoding.get_provider()
    if isinstance(provider, geocoding.NullGeocodingProvider):
        logger.warning(
            "Geocoding DESLIGADO (GEOCODING_ENABLED/APP_ENV). Nada a fazer."
        )
        return 0

    with SessionLocal() as db:
        queue = pending(db, limit)
        total = len(queue)
        if total == 0:
            logger.info("Nada pendente — todas as memórias já têm lugar.")
            return 0
        logger.info("%d memória(s) na fila.", total)

        done = 0
        for index, memory in enumerate(queue, start=1):
            point = to_shape(memory.location)
            if dry_run:
                logger.info("[%d/%d] %s -> %.4f, %.4f (dry-run)",
                            index, total, memory.id, point.y, point.x)
                continue
            located = geocoding.resolve_location(
                provider, latitude=point.y, longitude=point.x
            )
            if located.is_geocoded:
                memory_repository.set_location(db, memory=memory, location=located)
                done += 1
                logger.info("[%d/%d] %s -> %s", index, total, memory.id,
                            located.display_label)
            else:
                # Não interrompe: a próxima execução tenta de novo.
                logger.warning("[%d/%d] %s -> provedor não resolveu; fica na fila.",
                               index, total, memory.id)
            if index < total:
                time.sleep(_SLEEP_SECONDS)

        logger.info("Concluído: %d de %d resolvidas.", done, total)
        return done


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, default=100,
                        help="quantas memórias processar nesta execução")
    parser.add_argument("--dry-run", action="store_true",
                        help="lista a fila sem chamar o provedor nem gravar")
    args = parser.parse_args()
    run(limit=max(1, args.limit), dry_run=args.dry_run)


if __name__ == "__main__":
    main()
