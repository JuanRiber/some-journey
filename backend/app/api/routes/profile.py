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
from app.dependencies.limits import limit_uploads, limit_writes
from app.domain.username import InvalidUsernameError
from app.models.user import User
from app.schemas.profile import DayEntry, PlacesRead, ProfileRead, ProfileUpdate
from app.services import profile_service

router = APIRouter(
    prefix="/me", tags=["profile"],
    # Toda escrita deste router conta no teto de uso da pessoa (leitura não).
    dependencies=[Depends(limit_writes)],
)


@router.get("/profile", response_model=ProfileRead)
def get_profile(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ProfileRead:
    """Identidade, estatísticas, passaporte, última aventura e jornada atual."""
    return profile_service.get_profile(db, user=current_user)


@router.get("/places", response_model=PlacesRead)
def get_places(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> PlacesRead:
    """As cidades e os países da coleção, agrupados no banco — a porta dos
    quadrados "cidades" e "países" do Perfil. Cada item abre as próprias
    memórias por `GET /memories?city=…&country_code=…`."""
    return profile_service.get_places(db, user=current_user)


@router.get("/days", response_model=list[DayEntry])
def get_days(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[DayEntry]:
    """Os dias em que a pessoa registrou algo, do mais recente ao mais antigo.
    Cada dia abre as próprias memórias por `GET /memories?created_on=…`."""
    return profile_service.get_days(db, user=current_user)


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
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        )
    except profile_service.UsernameTakenError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Esse nome de usuário já está em uso.",
        )


@router.post(
    "/avatar", response_model=ProfileRead, dependencies=[Depends(limit_uploads)]
)
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
                status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                detail="A imagem é grande demais.",
            )
        chunks.append(chunk)
    data = b"".join(chunks)
    if not data:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="O arquivo está vazio.")
    try:
        return profile_service.set_avatar(db, user=current_user, data=data)
    except profile_service.InvalidAvatarError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Formato de imagem não aceito. Use JPEG, PNG ou WebP.",
        )
    except storage.StorageNotConfigured:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="O armazenamento de imagens não está configurado.",
        )
    except storage.StorageError:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Não foi possível guardar a imagem. Tente de novo.",
        )


@router.delete("/avatar", response_model=ProfileRead)
def remove_avatar(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ProfileRead:
    """Remove a foto de perfil (idempotente: sem foto, não faz nada)."""
    return profile_service.remove_avatar(db, user=current_user)
