"""Rotas de Memórias: CRUD protegido por autenticação.

TODAS as rotas exigem Bearer token (Depends(get_current_user)) — não existe
memória pública. O user_id vem SEMPRE do token, nunca do cliente, garantindo
ownership. As exceções de domínio do service viram status HTTP aqui; um id
inexistente OU de outro usuário resulta no MESMO 404 (não revela existência).
"""

import uuid

from fastapi import (
    APIRouter,
    Depends,
    File,
    HTTPException,
    Query,
    Response,
    UploadFile,
    status,
)
from sqlalchemy.orm import Session

from app.core import storage
from app.core.config import settings
from app.core.pagination import (
    NEXT_CURSOR_HEADER,
    CursorError,
    clamp_limit,
    decode_cursor,
)
from app.db.session import get_db
from app.dependencies.auth import get_current_user
from app.models.user import User
from app.schemas.memory import MemoryCreate, MemoryRead, MemoryUpdate
from app.services import memory_service
from app.services.memory_service import (
    InvalidImageError,
    MemoryImageNotFoundError,
    MemoryNotFoundError,
    TooManyImagesError,
)

router = APIRouter(prefix="/memories", tags=["memories"])

_not_found = HTTPException(
    status_code=status.HTTP_404_NOT_FOUND,
    detail="Memory not found.",
)


@router.post("", response_model=MemoryRead, status_code=status.HTTP_201_CREATED)
def create_memory(
    data: MemoryCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> MemoryRead:
    return memory_service.create(db, user_id=current_user.id, data=data)


@router.get("", response_model=list[MemoryRead])
def list_memories(
    response: Response,
    limit: int | None = Query(default=None),
    cursor: str | None = Query(default=None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[MemoryRead]:
    """Lista paginada por keyset. Corpo = ARRAY puro (retrocompatível); quando há
    próxima página, o cursor vai no header X-Next-Cursor. `?limit` é normalizado
    para [1, MAX_LIMIT]; `?cursor` opaco e malformado -> 400 (nunca 500)."""
    decoded = None
    if cursor is not None:
        try:
            decoded = decode_cursor(cursor)
        except CursorError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid pagination cursor.",
            )
    items, next_cursor = memory_service.list_for_user(
        db, user_id=current_user.id, limit=clamp_limit(limit), cursor=decoded
    )
    if next_cursor is not None:
        response.headers[NEXT_CURSOR_HEADER] = next_cursor
    return items


@router.get("/{memory_id}", response_model=MemoryRead)
def get_memory(
    memory_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> MemoryRead:
    try:
        return memory_service.get(db, user_id=current_user.id, memory_id=memory_id)
    except MemoryNotFoundError:
        raise _not_found


@router.patch("/{memory_id}", response_model=MemoryRead)
def update_memory(
    memory_id: uuid.UUID,
    data: MemoryUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> MemoryRead:
    try:
        return memory_service.update(
            db, user_id=current_user.id, memory_id=memory_id, data=data
        )
    except MemoryNotFoundError:
        raise _not_found


@router.delete("/{memory_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_memory(
    memory_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    try:
        memory_service.delete(db, user_id=current_user.id, memory_id=memory_id)
    except MemoryNotFoundError:
        raise _not_found


@router.post("/{memory_id}/images", response_model=MemoryRead)
def add_memory_image(
    memory_id: uuid.UUID,
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> MemoryRead:
    """Adiciona uma foto à memória do usuário (multipart), até o teto por memória.

    Lê o arquivo em blocos e corta no limite antes de materializar tudo na RAM.
    Rota síncrona: file.file.read roda em threadpool, sem travar o event loop."""
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
        return memory_service.add_image(
            db,
            user_id=current_user.id,
            memory_id=memory_id,
            data=data,
        )
    except MemoryNotFoundError:
        raise _not_found
    except InvalidImageError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Unsupported image type. Use JPEG, PNG or WebP.",
        )
    except TooManyImagesError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This memory already has the maximum number of photos.",
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


@router.delete("/{memory_id}/images/{image_id}", response_model=MemoryRead)
def delete_memory_image(
    memory_id: uuid.UUID,
    image_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> MemoryRead:
    """Remove UMA foto da memória (apaga o arquivo, best-effort). 404 se a
    memória ou a foto não são do usuário."""
    try:
        return memory_service.remove_image(
            db,
            user_id=current_user.id,
            memory_id=memory_id,
            image_id=image_id,
        )
    except (MemoryNotFoundError, MemoryImageNotFoundError):
        raise _not_found
