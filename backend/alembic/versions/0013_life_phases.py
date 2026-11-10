"""life_phases: os capítulos que a pessoa reconhece na própria história

Infância, recomeços, novos caminhos. Uma fase é uma LENTE para reler o próprio
atlas, não uma categoria obrigatória — por isso o vínculo é opcional dos dois
lados e não existe lista predefinida no banco.

Três escolhas que o schema registra:

- **Sem restrição de sobreposição.** "Vida adulta" e "recomeços" convivem, e
  uma pessoa pode estar em duas ao mesmo tempo. Exigir períodos disjuntos
  transformaria memória em planilha.
- **`started_at` e `ended_at` nulos.** Nem toda pessoa sabe quando a infância
  virou outra coisa, e a fase em curso não terminou. Pedir uma data de fim
  para salvar seria pedir que ela decretasse o próprio presente no passado.
- **`ON DELETE SET NULL` nos vínculos.** Apagar uma fase solta as memórias e
  jornadas que apontavam para ela. O contrário — levar junto — perderia a
  lembrança por causa da etiqueta, que é exatamente a ordem errada de
  importância.

`color` guarda o nome de um PAPEL da paleta (primary, secondary, accent, moss,
highlight), nunca um hexadecimal. Cor livre quebraria o contraste em um dos
dois modos do app: o que é legível no papel quente some no atlas noturno.

Revision ID: 0013_life_phases
Revises: 0012_google_identity
Create Date: 2026-11-10

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0013_life_phases"
down_revision: str | Sequence[str] | None = "0012_google_identity"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "life_phases",
        sa.Column(
            "id",
            sa.Uuid(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            primary_key=True,
        ),
        sa.Column(
            "user_id",
            sa.Uuid(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("name", sa.String(length=60), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column(
            "color", sa.String(length=20), server_default=sa.text("'accent'"), nullable=False
        ),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_life_phases_user_id", "life_phases", ["user_id"])

    for tabela in ("memories", "journeys"):
        op.add_column(
            tabela, sa.Column("life_phase_id", sa.Uuid(as_uuid=True), nullable=True)
        )
        op.create_foreign_key(
            f"fk_{tabela}_life_phase_id",
            tabela,
            "life_phases",
            ["life_phase_id"],
            ["id"],
            ondelete="SET NULL",
        )
        op.create_index(f"ix_{tabela}_life_phase_id", tabela, ["life_phase_id"])


def downgrade() -> None:
    for tabela in ("memories", "journeys"):
        op.drop_index(f"ix_{tabela}_life_phase_id", table_name=tabela)
        op.drop_constraint(f"fk_{tabela}_life_phase_id", tabela, type_="foreignkey")
        op.drop_column(tabela, "life_phase_id")
    op.drop_index("ix_life_phases_user_id", table_name="life_phases")
    op.drop_table("life_phases")
