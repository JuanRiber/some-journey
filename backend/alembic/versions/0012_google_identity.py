"""google_identity: entrar com o Google sem criar uma segunda conta

Duas mudanças na tabela `users`, e as duas existem pela mesma razão: até aqui
a única porta era e-mail + senha, e o schema dizia isso.

`google_sub` guarda o identificador estável da conta Google (a claim `sub` do
id_token). O vínculo é por ele e não pelo e-mail: o e-mail de uma conta Google
pode mudar de dono dentro de um domínio, o `sub` não. UNIQUE porque uma conta
Google não pode apontar para dois usuários — sem a constraint, uma corrida
entre dois logins simultâneos do mesmo Google criaria dois cadastros, e o
segundo só apareceria como "minhas memórias sumiram".

`password_hash` passa a aceitar NULL, porque quem entra pelo Google nunca
definiu senha. A alternativa — gravar um hash aleatório inutilizável — manteria
o NOT NULL ao custo de uma linha que MENTE: pareceria ter senha, e o próximo a
ler a tabela trataria como se tivesse. O serviço de login recusa quem não tem
hash com a mesma mensagem genérica de credencial inválida, sem revelar que a
conta existe e é do Google.

Revision ID: 0012_google_identity
Revises: 0011_memory_music
Create Date: 2026-11-02

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0012_google_identity"
down_revision: str | Sequence[str] | None = "0011_memory_music"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("google_sub", sa.String(length=255), nullable=True))
    op.create_unique_constraint("uq_users_google_sub", "users", ["google_sub"])
    op.alter_column("users", "password_hash", existing_type=sa.Text(), nullable=True)


def downgrade() -> None:
    # Voltar o NOT NULL exige que nao haja conta sem senha. Quem entrou pelo
    # Google nao tem hash, entao a descida APAGA essas contas — e e melhor
    # falhar alto aqui do que inventar uma senha para elas.
    op.execute("DELETE FROM users WHERE password_hash IS NULL")
    op.alter_column("users", "password_hash", existing_type=sa.Text(), nullable=False)
    op.drop_constraint("uq_users_google_sub", "users", type_="unique")
    op.drop_column("users", "google_sub")
