"""Tira os metadados das fotos que JÁ estão no Storage.

Toda foto nova sobe sem metadados (app/core/image_metadata.py). As que subiram
antes disso continuam com o que o celular gravou nelas — GPS, aparelho, data.
Este script passa por cada arquivo que o banco conhece (fotos de memória, capas
de jornada, avatares), baixa, limpa e, se algo saiu, grava de volta no MESMO
caminho.

Por padrão ele só CONTA. Para gravar é preciso pedir:

    python -m scripts.strip_photo_metadata              # só conta, não grava nada
    python -m scripts.strip_photo_metadata --apply      # grava as limpas por cima

(a partir de `backend/`, com o .venv ativo; em produção, pelo
`scripts/with_production_env.sh`, que também precisa das variáveis do Supabase.)

**Gravar por cima não tem volta** — a foto com metadados deixa de existir, que
é o objetivo. O que protege a imagem em si:

- a limpeza não recodifica: copia os compartimentos de imagem byte a byte;
- antes de gravar, o resultado é limpo de novo e tem de dar NO MESMO arquivo, e
  não pode ser maior que o original. Se uma das duas falhar, o arquivo é
  deixado como está e contado como "não deu para limpar";
- um arquivo que não dá para percorrer não é tocado.

Rodar duas vezes é inofensivo: na segunda, tudo aparece como "já estava limpa".
Não imprime caminho, id nem e-mail: só contagens.
"""

import argparse
from dataclasses import dataclass

from sqlalchemy import select

from app.core import images, storage
from app.core.image_metadata import MalformedImage, strip_metadata
from app.db.session import SessionLocal
from app.models.journey import Journey
from app.models.memory import Memory, MemoryImage
from app.models.user import User


@dataclass
class Report:
    examined: int = 0
    already_clean: int = 0
    cleaned: int = 0
    bytes_removed: int = 0
    unreadable: int = 0  # não baixou: o arquivo sumiu ou o Storage não respondeu
    not_cleanable: int = 0  # não é imagem que saibamos percorrer
    failed_upload: int = 0


def stored_paths(db) -> list[str]:
    """Todo arquivo de imagem que o banco conhece e que ainda deve existir."""
    fotos = db.scalars(
        select(MemoryImage.image_path)
        .join(Memory, Memory.id == MemoryImage.memory_id)
        .where(MemoryImage.deleted_at.is_(None), Memory.deleted_at.is_(None))
    ).all()
    capas = db.scalars(
        select(Journey.cover_image_path).where(
            Journey.cover_image_path.is_not(None), Journey.deleted_at.is_(None)
        )
    ).all()
    avatares = db.scalars(
        select(User.avatar_path).where(User.avatar_path.is_not(None))
    ).all()
    # Ordenado: duas execuções percorrem na mesma ordem.
    return sorted({*fotos, *capas, *avatares})


def clean_stored(path: str, *, apply: bool, report: Report) -> None:
    """Baixa, limpa e (com `apply`) grava de volta UM arquivo."""
    report.examined += 1
    original = storage.download(path)
    if original is None:
        report.unreadable += 1
        return
    mime = images.sniff_image_type(original)
    if mime is None:
        report.not_cleanable += 1
        return
    try:
        limpo = strip_metadata(original, mime)
        # A trava antes de gravar por cima: limpar o limpo tem de dar no mesmo.
        estavel = strip_metadata(limpo, mime) == limpo
    except MalformedImage:
        report.not_cleanable += 1
        return
    if not estavel or len(limpo) > len(original):
        report.not_cleanable += 1
        return
    if limpo == original:
        report.already_clean += 1
        return
    if apply:
        try:
            storage.upload(path, limpo, mime)
        except (storage.StorageError, storage.StorageNotConfigured):
            report.failed_upload += 1
            return
    report.cleaned += 1
    report.bytes_removed += len(original) - len(limpo)


def run(*, apply: bool) -> Report:
    report = Report()
    with SessionLocal() as db:
        caminhos = stored_paths(db)
    for caminho in caminhos:
        clean_stored(caminho, apply=apply, report=report)
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--apply",
        action="store_true",
        help="grava as fotos limpas por cima das originais (sem isto, só conta)",
    )
    args = parser.parse_args(argv)

    if not storage.enabled():
        print("Storage não configurado (SUPABASE_URL / SUPABASE_SERVICE_KEY): nada a fazer.")
        return 1

    r = run(apply=args.apply)
    kb = r.bytes_removed / 1024
    print("Fotos no Storage" + ("" if args.apply else " (ensaio: nada foi gravado)") + ":")
    print(f"  examinadas ................ {r.examined}")
    print(f"  já estavam limpas ......... {r.already_clean}")
    print(
        f"  {'limpas agora' if args.apply else 'seriam limpas'} ............ "
        f"{r.cleaned} ({kb:.0f} KB de metadados)"
    )
    print(f"  não baixaram .............. {r.unreadable}")
    print(f"  não deu para limpar ....... {r.not_cleanable}")
    if args.apply:
        print(f"  falharam ao gravar ........ {r.failed_upload}")
    return 0 if r.failed_upload == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
