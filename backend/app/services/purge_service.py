"""Apagar de verdade: a exclusão de conta e o expurgo do que foi apagado.

Quase tudo no Some Journey é apagado "de leve" — a linha ganha `deleted_at` e
some das consultas, mas continua no banco. Isso protege de um toque errado, e
tinha um custo que ninguém estava pagando: nada jamais saía. A memória que a
pessoa apagou há um ano seguia guardada, com as fotos no Storage; e não havia
como alguém ir embora levando os próprios dados da nossa mão.

Este módulo é onde as coisas saem:

- **Excluir conta** (`delete_account`): na hora, tudo. A linha do usuário é
  apagada e o banco leva o resto por `ON DELETE CASCADE` — memórias, fotos,
  músicas, jornadas, percursos, fases, tokens.
- **Expurgo** (`purge_expired`): o que está apagado "de leve" há mais que o
  prazo de retenção (`PURGE_DELETED_AFTER_DAYS`) é apagado de vez.

**Os arquivos.** Foto, capa e avatar moram no Storage, e não há transação que
cubra banco e Storage juntos. O caminho de cada arquivo entra na fila
`pending_file_deletions` na MESMA transação que apaga a linha; o arquivo é
removido em seguida (`drain_file_deletions`). Se o Storage falhar, o caminho
continua na fila e a próxima passada tenta de novo. A ordem inversa — apagar a
linha e só então tentar o arquivo — perderia o caminho na primeira falha, e a
foto ficaria guardada para sempre sem nada que levasse a ela.

Nada daqui loga caminho, e-mail ou id: os números bastam para saber que rodou.
"""

from __future__ import annotations

import logging
import uuid
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.core import storage
from app.core.config import settings
from app.models.file_deletion import PendingFileDeletion
from app.models.journey import Journey, JourneyMemory
from app.models.life_phase import LifePhase
from app.models.memory import Memory, MemoryImage, MemoryMusic
from app.models.password_reset import PasswordResetToken
from app.models.refresh_token import RefreshToken
from app.models.track import JourneyTrack
from app.models.user import User

logger = logging.getLogger(__name__)

# Quantos arquivos uma passada tenta apagar. Cada um é uma ida ao Storage; o
# teto mantém a passada curta, e o que sobrar fica para a próxima.
_DRAIN_BATCH = 200

# Token de recuperação vencido ainda serve, por um dia, para responder "este
# link expirou" em vez de "link inválido"; depois disso é só linha parada.
_KEEP_EXPIRED_RESET_TOKENS = timedelta(days=1)


@dataclass(frozen=True)
class PurgeReport:
    """O que uma passada do expurgo tirou do banco. Só contagens."""

    memories: int = 0
    journeys: int = 0
    tracks: int = 0
    life_phases: int = 0
    # Fotos, músicas e vínculos removidos um a um, de memórias que continuam.
    detached: int = 0
    tokens: int = 0
    files_queued: int = 0
    files_deleted: int = 0
    files_failed: int = 0

    @property
    def rows(self) -> int:
        return (
            self.memories
            + self.journeys
            + self.tracks
            + self.life_phases
            + self.detached
            + self.tokens
        )


# --- a fila de arquivos -----------------------------------------------------


def enqueue_files(db: Session, paths: Iterable[str | None]) -> int:
    """Põe caminhos na fila de exclusão (sem commit). Devolve quantos entraram.

    Quem chama comita junto com o que apagou as linhas — é isso que garante que
    nenhum arquivo fique sem dono E sem registro."""
    unicos = {p for p in paths if p}
    db.add_all(PendingFileDeletion(path=p) for p in unicos)
    return len(unicos)


def drain_file_deletions(db: Session, *, limit: int = _DRAIN_BATCH) -> tuple[int, int]:
    """Apaga do Storage o que está na fila. Devolve (apagados, falhos).

    Sem Storage configurado não faz nada e não conta como falha: a fila espera.
    Um arquivo que falha ganha uma tentativa e volta para o fim, então um
    caminho que nunca sai não segura os outros."""
    if not storage.enabled():
        return 0, 0
    pendentes = db.scalars(
        select(PendingFileDeletion)
        .order_by(PendingFileDeletion.attempts, PendingFileDeletion.created_at)
        .limit(limit)
    ).all()
    apagados = falhos = 0
    for item in pendentes:
        if storage.remove(item.path):
            db.delete(item)
            apagados += 1
        else:
            item.attempts += 1
            item.last_attempt_at = func.now()
            falhos += 1
    db.commit()
    return apagados, falhos


# --- excluir conta ----------------------------------------------------------


def _user_file_paths(db: Session, user: User) -> list[str | None]:
    """Todo arquivo da pessoa no Storage: fotos, capas e avatar.

    Inclui o que já estava apagado "de leve". A foto removida de uma memória
    teve o arquivo apagado na hora, mas em melhor-esforço — se aquela chamada
    falhou, é aqui que ela é alcançada. Apagar o que já não existe é inofensivo.
    """
    fotos = db.scalars(
        select(MemoryImage.image_path)
        .join(Memory, Memory.id == MemoryImage.memory_id)
        .where(Memory.user_id == user.id)
    ).all()
    capas = db.scalars(
        select(Journey.cover_image_path).where(
            Journey.user_id == user.id, Journey.cover_image_path.is_not(None)
        )
    ).all()
    return [*fotos, *capas, user.avatar_path]


def delete_account(db: Session, *, user: User) -> None:
    """Exclui a conta e tudo o que é dela. Sem volta.

    Quem chama já conferiu que é a própria pessoa pedindo (ver
    auth_service.delete_account). Aqui só acontece: os caminhos dos arquivos
    entram na fila, a linha do usuário sai — e o `ON DELETE CASCADE` das chaves
    estrangeiras leva memórias, jornadas, percursos, fases e tokens —, tudo num
    commit. Só então os arquivos são removidos, em melhor-esforço: o que o
    Storage não apagar agora continua na fila.
    """
    user_id: uuid.UUID = user.id
    enqueue_files(db, _user_file_paths(db, user))
    # Sai da sessão antes do DELETE: depois do commit a linha não existe, e um
    # objeto ainda preso à sessão tentaria se recarregar dela.
    db.expunge(user)
    db.execute(delete(User).where(User.id == user_id))
    db.commit()
    try:
        drain_file_deletions(db)
    except Exception:  # noqa: BLE001 - a conta JÁ foi excluída; a fila tenta depois
        db.rollback()
        logger.warning("Arquivos da conta excluída ficaram na fila para depois.")


# --- expurgo ----------------------------------------------------------------


def _cutoff(days: int) -> datetime:
    return datetime.now(UTC) - timedelta(days=days)


def preview(db: Session, *, older_than_days: int | None = None) -> PurgeReport:
    """O que `purge_expired` apagaria agora, sem apagar nada."""
    corte = _cutoff(older_than_days or settings.PURGE_DELETED_AFTER_DAYS)

    def contar(model) -> int:
        return int(
            db.scalar(
                select(func.count()).select_from(model).where(model.deleted_at < corte)
            )
            or 0
        )

    return PurgeReport(
        memories=contar(Memory),
        journeys=contar(Journey),
        tracks=contar(JourneyTrack),
        life_phases=contar(LifePhase),
        detached=contar(MemoryImage) + contar(MemoryMusic) + contar(JourneyMemory),
        files_queued=int(
            db.scalar(select(func.count()).select_from(PendingFileDeletion)) or 0
        ),
    )


def purge_expired(db: Session, *, older_than_days: int | None = None) -> PurgeReport:
    """Apaga de vez o que está apagado "de leve" há mais que o prazo.

    A ordem importa só num ponto: os caminhos das fotos são lidos ANTES de as
    memórias saírem, porque o cascade leva as linhas de foto junto e o caminho
    iria com elas. Tudo o que é banco vai num commit; os arquivos, depois.

    Idempotente: rodar duas vezes seguidas, ou em dois processos ao mesmo
    tempo, apaga as mesmas linhas uma vez só.
    """
    corte = _cutoff(older_than_days or settings.PURGE_DELETED_AFTER_DAYS)

    def apagar(model, *condicoes) -> int:
        return db.execute(delete(model).where(*condicoes)).rowcount

    # Fotos: as de memórias que vão sair, e as removidas uma a uma há muito.
    memorias_vencidas = select(Memory.id).where(Memory.deleted_at < corte)
    fotos = db.scalars(
        select(MemoryImage.image_path).where(
            MemoryImage.memory_id.in_(memorias_vencidas)
            | (MemoryImage.deleted_at < corte)
        )
    ).all()
    capas = db.scalars(
        select(Journey.cover_image_path).where(
            Journey.deleted_at < corte, Journey.cover_image_path.is_not(None)
        )
    ).all()
    na_fila = enqueue_files(db, [*fotos, *capas])

    # O cascade das chaves estrangeiras leva o que pende de cada linha: fotos,
    # músicas e vínculos da memória; vínculos, trechos e pontos da jornada.
    memorias = apagar(Memory, Memory.deleted_at < corte)
    jornadas = apagar(Journey, Journey.deleted_at < corte)
    trechos = apagar(JourneyTrack, JourneyTrack.deleted_at < corte)
    fases = apagar(LifePhase, LifePhase.deleted_at < corte)
    soltos = (
        apagar(MemoryImage, MemoryImage.deleted_at < corte)
        + apagar(MemoryMusic, MemoryMusic.deleted_at < corte)
        + apagar(JourneyMemory, JourneyMemory.deleted_at < corte)
    )
    agora = datetime.now(UTC)
    tokens = apagar(
        PasswordResetToken,
        PasswordResetToken.expires_at < agora - _KEEP_EXPIRED_RESET_TOKENS,
    ) + apagar(RefreshToken, RefreshToken.expires_at < agora)
    db.commit()

    apagados, falhos = drain_file_deletions(db)
    return PurgeReport(
        memories=memorias,
        journeys=jornadas,
        tracks=trechos,
        life_phases=fases,
        detached=soltos,
        tokens=tokens,
        files_queued=na_fila,
        files_deleted=apagados,
        files_failed=falhos,
    )


def run_once() -> PurgeReport:
    """Uma passada, com sessão própria — é o que o agendador e o script chamam."""
    from app.db.session import SessionLocal

    with SessionLocal() as db:
        relatorio = purge_expired(db)
    if relatorio.rows or relatorio.files_deleted or relatorio.files_failed:
        logger.info(
            "Expurgo: %d linhas, %d arquivos apagados, %d a tentar de novo.",
            relatorio.rows,
            relatorio.files_deleted,
            relatorio.files_failed,
        )
    return relatorio
