import uuid
from datetime import datetime

from geoalchemy2 import Geography
from geoalchemy2.elements import WKBElement
from sqlalchemy import CHAR, DateTime, ForeignKey, Index, String, Text, Uuid, func
from sqlalchemy import text as sql_text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Memory(Base):
    """Model ORM da tabela 'memories': um acontecimento humano preso a um lugar
    e a um momento.

    Pertence a um usuário (ownership via user_id). Exclusão é LÓGICA
    (deleted_at) — toda consulta deve filtrar deleted_at IS NULL. Estilo
    SQLAlchemy 2.0 (Mapped/mapped_column); defaults vêm do banco (server_default).
    """

    __tablename__ = "memories"

    # Índices parciais (só linhas ativas — o filtro deleted_at IS NULL entra em
    # TODA query, então o índice não carrega lixo soft-deletado):
    # - ix_memories_user_active: acelera o ownership puro (user_id).
    # - ix_memories_user_occurred: casa EXATAMENTE com a paginação por keyset da
    #   listagem — order by (occurred_at DESC, id DESC) filtrando por user_id.
    #   Com as colunas do ORDER BY já ordenadas no índice, o Postgres varre a
    #   página (e o desempate por id) sem sort em memória. O id no fim garante
    #   ordenação estável e um cursor sem ambiguidade (dois occurred_at iguais
    #   nunca "pulam" nem "repetem" linhas entre páginas).
    __table_args__ = (
        Index(
            "ix_memories_user_active",
            "user_id",
            postgresql_where=sql_text("deleted_at IS NULL"),
        ),
        Index(
            "ix_memories_user_occurred",
            "user_id",
            sql_text("occurred_at DESC"),
            sql_text("id DESC"),
            postgresql_where=sql_text("deleted_at IS NULL"),
        ),
        # Agregações do Perfil (Passaporte, estatísticas geográficas) e filtros
        # por região; e prefixo de geohash para vizinhança/clustering do Atlas.
        Index(
            "ix_memories_city_active",
            "user_id",
            "city",
            postgresql_where=sql_text("deleted_at IS NULL AND city IS NOT NULL"),
        ),
        Index(
            "ix_memories_country_active",
            "user_id",
            "country_code",
            postgresql_where=sql_text("deleted_at IS NULL AND country_code IS NOT NULL"),
        ),
        Index(
            "ix_memories_geohash_active",
            sql_text("geohash text_pattern_ops"),
            postgresql_where=sql_text("deleted_at IS NULL AND geohash IS NOT NULL"),
        ),
        Index(
            "ix_memories_pending_geocode",
            "created_at",
            postgresql_where=sql_text("deleted_at IS NULL AND geocoded_at IS NULL"),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        server_default=sql_text("gen_random_uuid()"),
    )

    # Dono da memória. ON DELETE CASCADE: se o usuário for removido de vez, as
    # memórias vão junto (no MVP o usuário é desativado, não removido).
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
    )

    title: Mapped[str] = mapped_column(String(120))
    text: Mapped[str] = mapped_column(Text)

    # Geography(POINT, 4326): armazenado como POINT(longitude, latitude).
    # GeoAlchemy2 cria um índice espacial GiST automaticamente (spatial_index).
    location: Mapped[WKBElement] = mapped_column(
        Geography(geometry_type="POINT", srid=4326)
    )

    # Apenas o caminho no Storage (bucket privado) — nunca uma URL pública.
    # Não é preenchido pelo POST /memories: upload é fluxo separado do backend.
    image_path: Mapped[str | None] = mapped_column(Text)

    # --- O LUGAR (objeto de localização achatado em colunas) -----------------
    # Preenchido por reverse geocoding na escrita e PERSISTIDO: o app nunca volta
    # ao provedor para saber onde a memória aconteceu. Tudo nullable — geocodificar
    # pode falhar e registrar a memória não pode depender disso.
    #
    # A manipulação NÃO acontece aqui: quem compõe/deriva é o Value Object
    # `app.domain.location.Location` (continente a partir do country_code,
    # geohash, rótulo de exibição). Estas colunas existem achatadas porque as
    # agregações do Perfil (COUNT DISTINCT city/country) precisam ser SQL puro.
    place_name: Mapped[str | None] = mapped_column(Text)
    place_label: Mapped[str | None] = mapped_column(Text)
    city: Mapped[str | None] = mapped_column(Text)
    state_province: Mapped[str | None] = mapped_column(Text)
    country: Mapped[str | None] = mapped_column(Text)
    # ISO-3166-1 alpha-2 normalizado em maiúsculo pelo VO (o Passaporte conta
    # DISTINCT: 'br' e 'BR' não podem virar dois países).
    country_code: Mapped[str | None] = mapped_column(CHAR(2))
    continent: Mapped[str | None] = mapped_column(Text)
    formatted_address: Mapped[str | None] = mapped_column(Text)
    timezone: Mapped[str | None] = mapped_column(Text)
    geohash: Mapped[str | None] = mapped_column(String(12))
    # NULL = ainda não geocodificado (é a fila de backfill).
    geocoded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Quando a memória ACONTECEU (alimenta a timeline) — pode ser no passado.
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    # Quando a memória foi cadastrada (não muda em edições; ver updated_at).
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    # Exclusão lógica (soft delete). NULL = ativa.
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class MemoryImage(Base):
    """Foto de uma memória. Uma memória tem VÁRIAS (o teto é imposto no service).
    Guarda só o caminho no Storage privado; soft delete via deleted_at. O legado
    `memories.image_path` continua para compatibilidade, mas fotos novas vivem aqui."""

    __tablename__ = "memory_images"

    __table_args__ = (
        Index(
            "ix_memory_images_memory_active",
            "memory_id",
            postgresql_where=sql_text("deleted_at IS NULL"),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        server_default=sql_text("gen_random_uuid()"),
    )
    memory_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("memories.id", ondelete="CASCADE"),
    )
    image_path: Mapped[str] = mapped_column(Text)
    position: Mapped[int] = mapped_column()
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
