"""Rotas das fases da vida — os capítulos que a pessoa reconhece.

Todas exigem Bearer token e só enxergam as fases de quem está autenticado.
Nenhuma fase é criada pelo sistema: não há lista predefinida, e quem nunca
criar nenhuma usa o produto inteiro sem perceber que isto existe.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.dependencies.auth import get_current_user
from app.domain.life_phase import InvalidPhaseError
from app.models.user import User
from app.schemas.life_phase import LifePhaseCreate, LifePhaseRead, LifePhaseUpdate
from app.services import life_phase_service

router = APIRouter(prefix="/life-phases", tags=["life-phases"])


def _nao_encontrada() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND, detail="Life phase not found."
    )


def fase_do_corpo_inexistente() -> HTTPException:
    """Para as rotas de memória e jornada, quando o corpo aponta para uma fase
    que esta pessoa não tem.

    422 e não 404: o recurso da URL (a memória, a jornada) existe; quem não
    serve é um valor do corpo. Responder 404 diria que a memória sumiu.
    """
    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        detail="Essa fase da vida não existe mais. Escolha outra ou deixe sem fase.",
    )


def fase_do_filtro_inexistente() -> HTTPException:
    """Para os filtros (`?life_phase_id=`): 404, como o `?journey_id=` do mapa.

    Devolver lista vazia seria pior — "nenhuma memória nesta fase" é uma
    resposta plausível, e esconderia que a fase pedida não existe.
    """
    return _nao_encontrada()


def _invalida(exc: InvalidPhaseError) -> HTTPException:
    # A mensagem vem do domínio, já em pt-BR e escrita para quem vai ler.
    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
    )


@router.get("", response_model=list[LifePhaseRead])
def list_phases(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[LifePhaseRead]:
    fases = life_phase_service.list_phases(db, user_id=current_user.id)
    return [LifePhaseRead.model_validate(f) for f in fases]


@router.post("", response_model=LifePhaseRead, status_code=status.HTTP_201_CREATED)
def create_phase(
    data: LifePhaseCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> LifePhaseRead:
    try:
        fase = life_phase_service.create_phase(db, user_id=current_user.id, data=data)
    except InvalidPhaseError as exc:
        raise _invalida(exc)
    return LifePhaseRead.model_validate(fase)


@router.get("/{phase_id}", response_model=LifePhaseRead)
def get_phase(
    phase_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> LifePhaseRead:
    try:
        fase = life_phase_service.get_phase(
            db, phase_id=phase_id, user_id=current_user.id
        )
    except life_phase_service.PhaseNotFoundError:
        raise _nao_encontrada()
    return LifePhaseRead.model_validate(fase)


@router.patch("/{phase_id}", response_model=LifePhaseRead)
def update_phase(
    phase_id: uuid.UUID,
    data: LifePhaseUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> LifePhaseRead:
    try:
        fase = life_phase_service.update_phase(
            db, phase_id=phase_id, user_id=current_user.id, data=data
        )
    except life_phase_service.PhaseNotFoundError:
        raise _nao_encontrada()
    except InvalidPhaseError as exc:
        raise _invalida(exc)
    return LifePhaseRead.model_validate(fase)


@router.delete("/{phase_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_phase(
    phase_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    try:
        life_phase_service.delete_phase(db, phase_id=phase_id, user_id=current_user.id)
    except life_phase_service.PhaseNotFoundError:
        raise _nao_encontrada()
