"""Rotas do percurso real (GPS) de uma jornada e o mapa da jornada (GeoJSON).

Prefixo /journeys (mesmo do router de jornadas; os caminhos não colidem). Todas
exigem Bearer token e validam ownership pelo token — nunca por dado do cliente.
Dado de localização é sensível: só o dono acessa; recurso de outro dá 404.
"""

import uuid

from fastapi import APIRouter, Body, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.dependencies.auth import get_current_user
from app.models.user import User
from app.schemas.track import (
    JourneyMapResponse,
    TrackPointsBatch,
    TrackRead,
    TrackStart,
)
from app.services import track_service
from app.services.journey_service import JourneyClosedError, JourneyNotFoundError
from app.services.track_service import (
    TrackAlreadyActiveError,
    TrackClosedError,
    TrackNotFoundError,
)

router = APIRouter(prefix="/journeys", tags=["tracks"])

_not_found = HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Journey not found.")
_track_not_found = HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Track not found.")


def _conflict(detail: str) -> HTTPException:
    return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detail)


@router.post(
    "/{journey_id}/tracks/start",
    response_model=TrackRead,
    status_code=status.HTTP_201_CREATED,
)
def start_track(
    journey_id: uuid.UUID,
    data: TrackStart | None = Body(default=None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> TrackRead:
    """Abre um trecho de gravação. 409 se já houver um trecho aberto na jornada."""
    try:
        return track_service.start_track(
            db, user_id=current_user.id, journey_id=journey_id, data=data or TrackStart()
        )
    except JourneyNotFoundError:
        raise _not_found
    except JourneyClosedError:
        raise _conflict("Cannot start a track on a finished journey.")
    except TrackAlreadyActiveError:
        raise _conflict("This journey already has an open track. Finish it first.")


@router.post("/{journey_id}/tracks/{track_id}/points", response_model=TrackRead)
def add_track_points(
    journey_id: uuid.UUID,
    track_id: uuid.UUID,
    data: TrackPointsBatch,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> TrackRead:
    """Envia pontos GPS em lote ao trecho aberto. 404 se o trecho não é do
    usuário/jornada; 409 se o trecho já foi finalizado."""
    try:
        return track_service.add_points(
            db,
            user_id=current_user.id,
            journey_id=journey_id,
            track_id=track_id,
            data=data,
        )
    except TrackNotFoundError:
        raise _track_not_found
    except TrackClosedError:
        raise _conflict("Track is already finished; start a new one.")
    except JourneyClosedError:
        raise _conflict("Cannot add points to a finished journey.")


@router.post("/{journey_id}/tracks/{track_id}/finish", response_model=TrackRead)
def finish_track(
    journey_id: uuid.UUID,
    track_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> TrackRead:
    try:
        return track_service.finish_track(
            db, user_id=current_user.id, journey_id=journey_id, track_id=track_id
        )
    except TrackNotFoundError:
        raise _track_not_found


@router.get("/{journey_id}/tracks", response_model=list[TrackRead])
def list_tracks(
    journey_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[TrackRead]:
    try:
        return track_service.list_tracks(
            db, user_id=current_user.id, journey_id=journey_id
        )
    except JourneyNotFoundError:
        raise _not_found


@router.delete(
    "/{journey_id}/tracks/{track_id}", status_code=status.HTTP_204_NO_CONTENT
)
def delete_track(
    journey_id: uuid.UUID,
    track_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    """Remove o percurso (soft-delete). Não apaga as memórias da jornada."""
    try:
        track_service.delete_track(
            db, user_id=current_user.id, journey_id=journey_id, track_id=track_id
        )
    except TrackNotFoundError:
        raise _track_not_found


@router.get("/{journey_id}/map", response_model=JourneyMapResponse)
def journey_map(
    journey_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> JourneyMapResponse:
    """GeoJSON da jornada: percurso real (tracks) + memórias + rastro simbólico."""
    try:
        return track_service.get_journey_map(
            db, user_id=current_user.id, journey_id=journey_id
        )
    except JourneyNotFoundError:
        raise _not_found
