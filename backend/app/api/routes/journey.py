import uuid

from fastapi import APIRouter, Body, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.core import storage
from app.core.config import settings
from app.db.session import get_db
from app.dependencies.auth import get_current_user
from app.models.user import User
from app.schemas.journey import (
    JourneyCreate,
    JourneyDetailRead,
    JourneyFinish,
    JourneyMemoryAdd,
    JourneyMemoryCreate,
    JourneyRead,
    JourneyReorder,
    JourneyUpdate,
)
from app.schemas.memory import MemoryRead
from app.services import journey_service
from app.services.journey_service import (
    ActiveJourneyExistsError,
    InvalidCoverImageError,
    InvalidJourneyReorderError,
    InvalidJourneyTransitionError,
    JourneyClosedError,
    JourneyConflictError,
    JourneyLinkNotFoundError,
    JourneyNotFoundError,
    MemoryAlreadyInJourneyError,
)

router = APIRouter(prefix="/journeys", tags=["journeys"])

_not_found = HTTPException(
    status_code=status.HTTP_404_NOT_FOUND,
    detail="Journey not found.",
)


def _conflict(detail: str) -> HTTPException:
    return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detail)


@router.post("", response_model=JourneyRead, status_code=status.HTTP_201_CREATED)
def create_journey(
    data: JourneyCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> JourneyRead:
    return journey_service.create(db, user_id=current_user.id, data=data)


@router.get("", response_model=list[JourneyRead])
def list_journeys(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[JourneyRead]:
    return journey_service.list_for_user(db, user_id=current_user.id)


@router.get("/{journey_id}", response_model=JourneyDetailRead)
def get_journey(
    journey_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> JourneyDetailRead:
    try:
        return journey_service.get(db, user_id=current_user.id, journey_id=journey_id)
    except JourneyNotFoundError:
        raise _not_found


@router.patch("/{journey_id}", response_model=JourneyRead)
def update_journey(
    journey_id: uuid.UUID,
    data: JourneyUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> JourneyRead:
    """Edita título/descrição da jornada (não mexe no status/ciclo de vida)."""
    try:
        return journey_service.update(
            db, user_id=current_user.id, journey_id=journey_id, data=data
        )
    except JourneyNotFoundError:
        raise _not_found


@router.post("/{journey_id}/start", response_model=JourneyRead)
def start_journey(
    journey_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> JourneyRead:
    try:
        return journey_service.start(db, user_id=current_user.id, journey_id=journey_id)
    except JourneyNotFoundError:
        raise _not_found
    except ActiveJourneyExistsError:
        raise _conflict("Another journey is already active.")
    except InvalidJourneyTransitionError:
        raise _conflict("Only a draft journey can be started.")


@router.post("/{journey_id}/pause", response_model=JourneyRead)
def pause_journey(
    journey_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> JourneyRead:
    try:
        return journey_service.pause(db, user_id=current_user.id, journey_id=journey_id)
    except JourneyNotFoundError:
        raise _not_found
    except InvalidJourneyTransitionError:
        raise _conflict("Only an active journey can be paused.")


@router.post("/{journey_id}/resume", response_model=JourneyRead)
def resume_journey(
    journey_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> JourneyRead:
    try:
        return journey_service.resume(db, user_id=current_user.id, journey_id=journey_id)
    except JourneyNotFoundError:
        raise _not_found
    except ActiveJourneyExistsError:
        raise _conflict("Another journey is already active.")
    except InvalidJourneyTransitionError:
        raise _conflict("Only a paused journey can be resumed.")


@router.post("/{journey_id}/finish", response_model=JourneyRead)
def finish_journey(
    journey_id: uuid.UUID,
    data: JourneyFinish | None = Body(default=None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> JourneyRead:
    try:
        return journey_service.finish(
            db,
            user_id=current_user.id,
            journey_id=journey_id,
            data=data or JourneyFinish(),
        )
    except JourneyNotFoundError:
        raise _not_found
    except InvalidJourneyTransitionError:
        raise _conflict("Only an active or paused journey can be finished.")


@router.post("/{journey_id}/points", response_model=JourneyDetailRead)
def add_memory_to_journey(
    journey_id: uuid.UUID,
    data: JourneyMemoryAdd,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> JourneyDetailRead:
    try:
        return journey_service.add_existing_memory(
            db, user_id=current_user.id, journey_id=journey_id, data=data
        )
    except JourneyNotFoundError:
        raise _not_found
    except MemoryAlreadyInJourneyError:
        raise _conflict("Memory already belongs to a journey. Unlink it first.")
    except JourneyClosedError:
        raise _conflict("Cannot add points to a finished journey.")


@router.get("/{journey_id}/memories", response_model=list[MemoryRead])
def list_journey_memories(
    journey_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[MemoryRead]:
    """Memórias da jornada em ordem cronológica (timeline da jornada). 404 se a
    jornada não é do usuário."""
    try:
        return journey_service.list_memories(
            db, user_id=current_user.id, journey_id=journey_id
        )
    except JourneyNotFoundError:
        raise _not_found


@router.post("/{journey_id}/memories", response_model=JourneyDetailRead, status_code=status.HTTP_201_CREATED)
def create_memory_in_journey(
    journey_id: uuid.UUID,
    data: JourneyMemoryCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> JourneyDetailRead:
    try:
        return journey_service.create_memory_in_journey(
            db, user_id=current_user.id, journey_id=journey_id, data=data
        )
    except JourneyNotFoundError:
        raise _not_found
    except JourneyClosedError:
        raise _conflict("Cannot add points to a finished journey.")
    except JourneyConflictError:
        raise _conflict("Could not add the point due to a conflict. Try again.")


@router.delete(
    "/{journey_id}/points/{memory_id}", status_code=status.HTTP_204_NO_CONTENT
)
def remove_memory_from_journey(
    journey_id: uuid.UUID,
    memory_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    """Desvincula a memory da journey SEM apagar a memory (ela volta a ser um
    ponto solto). 404 se a journey nao e do usuario ou o vinculo nao existe."""
    try:
        journey_service.unlink_memory(
            db, user_id=current_user.id, journey_id=journey_id, memory_id=memory_id
        )
    except (JourneyNotFoundError, JourneyLinkNotFoundError):
        raise _not_found


@router.patch("/{journey_id}/points/reorder", response_model=JourneyDetailRead)
def reorder_journey_points(
    journey_id: uuid.UUID,
    data: JourneyReorder,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> JourneyDetailRead:
    try:
        return journey_service.reorder_points(
            db, user_id=current_user.id, journey_id=journey_id, data=data
        )
    except JourneyNotFoundError:
        raise _not_found
    except InvalidJourneyReorderError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="memory_ids must match the current journey points exactly.",
        )


@router.post("/{journey_id}/cover", response_model=JourneyRead)
def set_journey_cover(
    journey_id: uuid.UUID,
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> JourneyRead:
    """Define a capa da jornada (multipart, campo `file`). Mesmo teto e leitura
    em blocos do upload de foto de memória."""
    max_bytes = settings.MAX_IMAGE_BYTES
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = file.file.read(1024 * 1024)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail="Image too large.",
            )
        chunks.append(chunk)
    data = b"".join(chunks)
    if not data:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Empty file.")
    try:
        return journey_service.set_cover(
            db,
            user_id=current_user.id,
            journey_id=journey_id,
            data=data,
            content_type=file.content_type or "",
        )
    except JourneyNotFoundError:
        raise _not_found
    except InvalidCoverImageError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Unsupported image type. Use JPEG, PNG or WebP.",
        )
    except storage.StorageNotConfigured:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Image storage is not configured.",
        )
    except storage.StorageError:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Could not store the image. Try again.",
        )


@router.delete("/{journey_id}/cover", response_model=JourneyRead)
def remove_journey_cover(
    journey_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> JourneyRead:
    """Remove a capa explícita (volta ao fallback: primeira foto do rastro)."""
    try:
        return journey_service.remove_cover(
            db, user_id=current_user.id, journey_id=journey_id
        )
    except JourneyNotFoundError:
        raise _not_found


@router.delete("/{journey_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_journey(
    journey_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    try:
        journey_service.delete(db, user_id=current_user.id, journey_id=journey_id)
    except JourneyNotFoundError:
        raise _not_found
