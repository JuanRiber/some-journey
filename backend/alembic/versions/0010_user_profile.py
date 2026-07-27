"""user profile: username, avatar, bio

O Perfil deixa de ser só nome+e-mail: ganha identidade pública (@username), foto
e uma frase pessoal.

Tudo NULLABLE: as contas que já existem não têm nada disso e continuam válidas —
o app mostra iniciais no lugar da foto e uma frase derivada dos dados enquanto a
pessoa não escolher a sua.

Unicidade do @username é por `lower(username)` (índice funcional): `@Juan` e
`@juan` são a MESMA identidade; guardamos a forma escolhida para exibir.

Revision ID: 0010_user_profile
Revises: 0009_memory_location
Create Date: 2026-07-26

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0010_user_profile"
down_revision: str | None = "0009_memory_location"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("username", sa.String(30), nullable=True))
    # Caminho no bucket PRIVADO (nunca URL pública) — a leitura assina na hora,
    # igual às fotos de memória.
    op.add_column("users", sa.Column("avatar_path", sa.Text(), nullable=True))
    op.add_column("users", sa.Column("bio", sa.String(160), nullable=True))

    # Índice funcional: unicidade sem caixa. Um UNIQUE comum deixaria passar
    # "Juan" e "juan" como pessoas diferentes.
    op.execute(
        "CREATE UNIQUE INDEX uq_users_username_lower "
        "ON users (LOWER(username)) WHERE username IS NOT NULL"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_users_username_lower")
    op.drop_column("users", "bio")
    op.drop_column("users", "avatar_path")
    op.drop_column("users", "username")
