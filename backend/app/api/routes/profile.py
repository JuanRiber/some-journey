"""Rota do Perfil: GET /me/profile (Bearer token).

Um endpoint AGREGADO de propósito. A alternativa — o cliente pedir memórias e
jornadas e contar — derrubaria a paginação por keyset e cresceria com o acervo do
usuário. Aqui a resposta tem tamanho constante, independentemente de a pessoa ter
10 ou 10.000 memórias.
"""

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.core import storage
from app.core.config import settings
from app.db.session import get_db
from app.dependencies.auth import get_current_user
from app.domain.username import InvalidUsernameError
from app.models.user import User
from app.schemas.profile import ProfileRead, ProfileUpdate
from app.services import profile_service

router = APIRouter(prefix="/me", tags=["profile"])


@router.get("/profile", response_model=ProfileRead)
def get_profile(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ProfileRead:
    """Identidade, estatísticas, passaporte, última aventura e jornada atual."""
    return profile_service.get_profile(db, user=current_user)


@router.patch("/profile", response_model=ProfileRead)
def update_profile(
    data: ProfileUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ProfileRead:
    """Edita nome, @username e bio (parcial) e devolve o Perfil já atualizado —
    o cliente não precisa de uma segunda chamada para redesenhar a tela."""
    try:
        return profile_service.update_profile(db, user=current_user, data=data)
    except InvalidUsernameError as exc:
        # Mensagem de domínio, em pt-BR, pronta para a UI.
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
        )
    except profile_service.UsernameTakenError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Esse nome de usuário já está em uso.",
        )


@router.post("/avatar", response_model=ProfileRead)
def set_avatar(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ProfileRead:
    """Envia a foto de perfil (multipart).

    Lê em blocos e corta no teto ANTES de materializar tudo na RAM (mesma defesa
    das fotos de memória). O tipo real vem dos bytes, não do cabeçalho."""
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
        return profile_service.set_avatar(db, user=current_user, data=data)
    except profile_service.InvalidAvatarError:
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


@router.delete("/avatar", response_model=ProfileRead)
def remove_avatar(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ProfileRead:
    """Remove a foto de perfil (idempotente: sem foto, não faz nada)."""
    return profile_service.remove_avatar(db, user=current_user)
