"""Rota do mapa principal: GET /map (protegida por Bearer token).

Devolve, em uma só resposta, tudo que o front precisa para desenhar o mapa do
usuário: pins soltos + jornadas (pins ordenados + rastro). O user_id vem SEMPRE
do token (ownership). Filtros opcionais:
- bbox: recorta pela viewport (mundo/país/região/cidade é só zoom no front);
- journey_id: foca uma jornada específica.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.dependencies.auth import get_current_user
from app.models.user import User
from app.repositories.memory_repository import Bbox
from app.schemas.map import MapResponse
from app.services import map_service
from app.services.journey_service import JourneyNotFoundError

router = APIRouter(prefix="/map", tags=["map"])


def _bad_request(detail: str) -> HTTPException:
    return HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=detail)


def _parse_bbox(bbox: str | None) -> Bbox | None:
    """'min_lng,min_lat,max_lng,max_lat' -> tupla validada, ou None."""
    if bbox is None:
        return None
    parts = bbox.split(",")
    if len(parts) != 4:
        raise _bad_request("bbox must be 'min_lng,min_lat,max_lng,max_lat'.")
    try:
        min_lng, min_lat, max_lng, max_lat = (float(p) for p in parts)
    except ValueError:
        raise _bad_request("bbox values must be numbers.")
    if not (-180 <= min_lng <= 180 and -180 <= max_lng <= 180):
        raise _bad_request("bbox longitude must be within [-180, 180].")
    if not (-90 <= min_lat <= 90 and -90 <= max_lat <= 90):
        raise _bad_request("bbox latitude must be within [-90, 90].")
    if min_lng >= max_lng or min_lat >= max_lat:
        raise _bad_request("bbox must have min < max for both axes.")
    return (min_lng, min_lat, max_lng, max_lat)


@router.get("", response_model=MapResponse)
def get_map(
    bbox: str | None = Query(
        default=None, description="Viewport: 'min_lng,min_lat,max_lng,max_lat'."
    ),
    journey_id: uuid.UUID | None = Query(default=None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> MapResponse:
    parsed = _parse_bbox(bbox)
    try:
        return map_service.get_map(
            db, user_id=current_user.id, bbox=parsed, journey_id=journey_id
        )
    except JourneyNotFoundError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Journey not found."
        )
