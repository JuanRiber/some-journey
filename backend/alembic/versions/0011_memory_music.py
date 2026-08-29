"""memory_music: a canção que estava tocando

Uma memória pode ter música. O app já sabia buscar faixas (o `MusicProvider` e o
adapter do iTunes existem desde julho) e não tinha onde guardá-las: dava para
achar a canção e não para salvá-la.

Guardamos o SNAPSHOT da faixa, não uma referência ao catálogo. Título, artista,
álbum, capa e duração ficam gravados aqui. É deliberado: catálogos mudam de
política, tiram faixas do ar e reorganizam ids, e a lembrança de qual música
tocava não pode depender de um terceiro continuar existindo. `provider` +
`external_id` ficam junto para reabrir a faixa no serviço quando ela ainda está
lá — mas o registro sobrevive sem isso.

Uma faixa não entra duas vezes na mesma memória: índice único parcial em
(memory_id, provider, external_id) enquanto ativa. É a mesma regra que o
`MusicTrack` do app já expressa no seu `operator ==`, agora garantida pelo banco
em vez de pela boa vontade do cliente.

Revision ID: 0011_memory_music
Revises: 0010_user_profile
Create Date: 2026-08-29

"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0011_memory_music"
down_revision: str | None = "0010_user_profile"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "memory_music",
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("memory_id", sa.Uuid(), nullable=False),
        # Origem da faixa. Trocar de catálogo no futuro (Apple Music, Spotify)
        # não invalida o que já foi salvo: cada linha diz de onde veio.
        sa.Column("provider", sa.String(length=20), nullable=False),
        sa.Column("external_id", sa.String(length=64), nullable=False),
        # O snapshot. title e artist são obrigatórios porque sem eles a linha
        # não conta nada a quem lembra; o resto é enfeite do provedor.
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("artist", sa.String(length=200), nullable=False),
        sa.Column("album", sa.String(length=200), nullable=True),
        sa.Column("artwork_url", sa.Text(), nullable=True),
        sa.Column("preview_url", sa.Text(), nullable=True),
        sa.Column("external_url", sa.Text(), nullable=True),
        sa.Column("duration_ms", sa.Integer(), nullable=True),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["memory_id"], ["memories.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    # Leitura: as faixas ativas de uma memória, na ordem.
    op.create_index(
        "ix_memory_music_memory_active",
        "memory_music",
        ["memory_id", "position"],
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    # A mesma faixa não entra duas vezes na mesma memória. Parcial em
    # deleted_at IS NULL: remover e reanexar depois continua permitido.
    op.create_index(
        "uq_memory_music_track_active",
        "memory_music",
        ["memory_id", "provider", "external_id"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    # Contagem do Perfil ("56 músicas"): varre só as faixas ativas.
    op.create_index(
        "ix_memory_music_active",
        "memory_music",
        ["memory_id"],
        postgresql_where=sa.text("deleted_at IS NULL"),
    )


def downgrade() -> None:
    op.drop_index("ix_memory_music_active", table_name="memory_music")
    op.drop_index("uq_memory_music_track_active", table_name="memory_music")
    op.drop_index("ix_memory_music_memory_active", table_name="memory_music")
    op.drop_table("memory_music")
