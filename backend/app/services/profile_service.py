"""Serviço do Perfil: monta o payload da tela a partir das agregações SQL.

Não faz conta em Python — só compõe o que o repository já agregou e aplica as
regras de APRESENTAÇÃO do domínio (ex.: o passaporte mostra TODOS os continentes,
marcados ou não, porque o que falta explorar é parte da narrativa).
"""

import uuid

from sqlalchemy.orm import Session

from app.domain.continents import CONTINENTS_IN_ORDER
from app.models.user import User
from app.repositories import profile_repository
from app.schemas.profile import (
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
