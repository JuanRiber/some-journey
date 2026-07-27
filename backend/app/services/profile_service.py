"""Serviço do Perfil: monta o payload da tela a partir das agregações SQL.

Não faz conta em Python — só compõe o que o repository já agregou e aplica as
regras de APRESENTAÇÃO do domínio (ex.: o passaporte mostra TODOS os continentes,
marcados ou não, porque o que falta explorar é parte da narrativa).
"""

import uuid

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import images, storage
from app.domain.continents import CONTINENTS_IN_ORDER
from app.domain.username import InvalidUsernameError, validate as validate_username
from app.models.user import User
from app.repositories import profile_repository, user_repository
from app.schemas.profile import (  # noqa: I001
    CurrentJourney,
    LastAdventure,
    PassportStamp,
    ProfileIdentity,
    ProfileRead,
    ProfileStats,
)


def get_profile(db: Session, *, user: User) -> ProfileRead:
    """Tudo que o Perfil precisa, numa resposta só.

    São poucas consultas agregadas (contagens, distintos, PostGIS) — nenhuma
    baixa listas. O cliente não calcula nada."""
    user_id: uuid.UUID = user.id

    memory_counts = profile_repository.counts(db, user_id=user_id)
    journeys = profile_repository.journey_counts(db, user_id=user_id)
    visited = set(profile_repository.visited_continents(db, user_id=user_id))
    adventure = profile_repository.last_adventure(db, user_id=user_id)
    journey = profile_repository.current_journey(db, user_id=user_id)

    return ProfileRead(
        identity=ProfileIdentity(
            id=user.id,
            name=user.name,
            email=user.email,
            joined_at=user.created_at,
            member_since=profile_repository.member_since(db, user_id=user_id),
            username=user.username,
            # URL ASSINADA e temporária: o bucket é privado, o caminho nunca sai.
            avatar_url=storage.sign_url(user.avatar_path) if user.avatar_path else None,
            bio=user.bio,
        ),
        stats=ProfileStats(
            memories=memory_counts["memories"],
            journeys=journeys["journeys"],
            journeys_finished=journeys["journeys_finished"],
            cities=memory_counts["cities"],
            countries=memory_counts["countries"],
            continents=memory_counts["continents"],
            photos=profile_repository.photo_count(db, user_id=user_id),
            tracked_meters=profile_repository.tracked_meters(db, user_id=user_id),
            active_days=profile_repository.active_days(db, user_id=user_id),
            pending_geocode=memory_counts["pending_geocode"],
        ),
        # O passaporte lista TODOS os continentes: o vazio ("⬜ Ásia") é convite,
        # não ausência de dado — mostrar só os visitados esconderia a jornada que
        # falta.
        passport=[
            PassportStamp(continent=name, visited=name in visited)
            for name in CONTINENTS_IN_ORDER
        ],
        last_adventure=LastAdventure(**adventure) if adventure else None,
        current_journey=CurrentJourney(**journey) if journey else None,
    )


# --- Escrita da identidade pública -----------------------------------------

# Tipos aceitos no avatar -> extensão no Storage (mesmo critério das fotos).
_AVATAR_EXT = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}


class UsernameTakenError(Exception):
    """@username já usado por outra pessoa — a rota traduz em 409."""


class InvalidAvatarError(Exception):
    """Arquivo não é uma imagem suportada — a rota traduz em 400."""


def update_profile(db: Session, *, user: User, data) -> ProfileRead:
    """Edita nome, @username e bio (parcial).

    O @username passa pelas regras de DOMÍNIO (formato, tamanho, reservados) e
    depois pela unicidade: checagem prévia para a mensagem limpa (409) e o índice
    único como garantia final contra corrida."""
    username = None
    if data.username is not None:
        try:
            username = validate_username(data.username)
        except InvalidUsernameError:
            raise  # a rota traduz em 422 com a mensagem em pt-BR
        existing = user_repository.get_by_username(db, username)
        if existing is not None and existing.id != user.id:
            raise UsernameTakenError()
    try:
        updated = user_repository.update_profile(
            db, user=user, name=data.name, username=username, bio=data.bio
        )
    except IntegrityError as exc:
        # Corrida: dois pedidos com o mesmo @ no mesmo instante.
        raise UsernameTakenError() from exc
    return get_profile(db, user=updated)


def set_avatar(db: Session, *, user: User, data: bytes) -> ProfileRead:
    """Sobe a foto de perfil e grava o caminho.

    O tipo vem dos BYTES (magic bytes), nunca do Content-Type do cliente. Se a
    gravação no banco falhar depois do upload, o objeto recém-enviado é apagado —
    a mesma compensação usada nas fotos de memória, para não deixar lixo órfão no
    bucket."""
    mime = images.sniff_image_type(data)
    if mime is None or mime not in _AVATAR_EXT:
        raise InvalidAvatarError()
    old_path = user.avatar_path
    path = f"{user.id}/avatar/{uuid.uuid4().hex}.{_AVATAR_EXT[mime]}"
    storage.upload(path, data, mime)
    try:
        updated = user_repository.set_avatar_path(db, user=user, path=path)
    except Exception:
        storage.delete(path)
        raise
    # Só depois de o novo estar durável é que o antigo sai (best-effort).
    if old_path:
        storage.delete(old_path)
    return get_profile(db, user=updated)


def remove_avatar(db: Session, *, user: User) -> ProfileRead:
    """Remove a foto: o Perfil volta a mostrar as iniciais."""
    old_path = user.avatar_path
    updated = user
    if old_path:
        updated = user_repository.set_avatar_path(db, user=user, path=None)
        storage.delete(old_path)
    return get_profile(db, user=updated)
