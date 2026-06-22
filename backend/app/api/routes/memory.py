"""Rotas de Memórias: CRUD protegido por autenticação.

TODAS as rotas exigem Bearer token (Depends(get_current_user)) — não existe
memória pública. O user_id vem SEMPRE do token, nunca do cliente, garantindo
ownership. As exceções de domínio do service viram status HTTP aqui; um id
inexistente OU de outro usuário resulta no MESMO 404 (não revela existência).
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.dependencies.auth import get_current_user
from app.models.user import User
from app.schemas.memory import MemoryCreate, MemoryRead, MemoryUpdate
from app.services import memory_service
from app.services.memory_service import MemoryNotFoundError

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
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[MemoryRead]:
    return memory_service.list_for_user(db, user_id=current_user.id)


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
