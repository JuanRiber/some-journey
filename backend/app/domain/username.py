"""`@username` — regras de domínio.

Um username é um IDENTIFICADOR PÚBLICO e (no futuro) parte de uma URL de perfil
compartilhável. Por isso as regras nascem aqui, puras e testáveis, e não
espalhadas em validações de schema: a mesma regra vale para cadastro, edição,
seed e qualquer importação futura.

Decisões:
- **Comparação sem caixa**: `@Juan` e `@juan` são A MESMA pessoa. Guardamos a
  forma escolhida (para exibir) e garantimos unicidade por `lower(username)`.
- **Conjunto restrito** (letras, números, `_`, começando por letra): evita
  homógrafos, espaços, emojis e nomes que quebrariam uma URL.
- **Palavras reservadas**: `admin`, `api`, `me`... seriam colisão de rota ou
  convite a falsa identidade. Bloquear agora custa nada; depois custa migração.
"""

import re

MIN_LENGTH = 3
MAX_LENGTH = 30

# Começa com letra; depois letras, números ou _ . Sem pontos/hífens de propósito:
# menos ambiguidade visual em @menções.
_PATTERN = re.compile(r"^[a-z][a-z0-9_]{2,29}$")

# Reservados: rotas atuais/prováveis do produto e nomes que sugerem autoridade.
RESERVED: frozenset[str] = frozenset(
    {
        "admin", "administrator", "api", "app", "auth", "backup", "blog",
        "config", "contact", "dashboard", "dev", "docs", "explore", "export",
        "help", "home", "journey", "journeys", "login", "logout", "map", "me",
        "memories", "memory", "new", "null", "profile", "register", "root",
        "search", "settings", "signin", "signup", "somejourney", "static",
        "support", "system", "terms", "test", "undefined", "user", "users",
    }
)


class InvalidUsernameError(ValueError):
    """Username fora das regras — a rota traduz em 422 com a mensagem daqui."""


def normalize(raw: str) -> str:
    """Forma CANÔNICA usada para comparar e garantir unicidade.

    Só apara espaços e baixa a caixa; não "conserta" caracteres inválidos —
    corrigir silenciosamente faria a pessoa receber um @ diferente do que digitou.
    """
    return raw.strip().lower()


def validate(raw: str) -> str:
    """Valida e devolve a forma canônica, ou levanta [InvalidUsernameError].

    As mensagens são para o usuário final (pt-BR), não para o log."""
    candidate = normalize(raw)
    if not candidate:
        raise InvalidUsernameError("Escolha um nome de usuário.")
    if len(candidate) < MIN_LENGTH:
        raise InvalidUsernameError(
            f"O nome de usuário precisa de pelo menos {MIN_LENGTH} caracteres."
        )
    if len(candidate) > MAX_LENGTH:
        raise InvalidUsernameError(
            f"O nome de usuário pode ter no máximo {MAX_LENGTH} caracteres."
        )
    if not _PATTERN.match(candidate):
        raise InvalidUsernameError(
            "Use apenas letras, números e _ , começando por uma letra."
        )
    if candidate in RESERVED:
        raise InvalidUsernameError("Esse nome de usuário não está disponível.")
    return candidate
