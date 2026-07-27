"""Rota do Perfil: GET /me/profile (Bearer token).

Um endpoint AGREGADO de propósito. A alternativa — o cliente pedir memórias e
jornadas e contar — derrubaria a paginação por keyset e cresceria com o acervo do
usuário. Aqui a resposta tem tamanho constante, independentemente de a pessoa ter
10 ou 10.000 memórias.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.dependencies.auth import get_current_user
from app.models.user import User
from app.schemas.profile import ProfileRead
from app.services import profile_service

router = APIRouter(prefix="/me", tags=["profile"])


@router.get("/profile", response_model=ProfileRead)
def get_profile(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ProfileRead:
    """Identidade, estatísticas, passaporte, última aventura e jornada atual."""
    return profile_service.get_profile(db, user=current_user)
