"""Schemas Pydantic (v2) dos contratos de Memórias.

A API fala em linguagem humana — `latitude`/`longitude`; o model guarda
`GEOGRAPHY(POINT, 4326)`. A conversão lat/long ↔ POINT acontece no SERVICE,
não aqui: estes são DTOs puros.

Segurança: `image_path` NUNCA entra por estes schemas (upload é um fluxo
separado, controlado pelo backend). `user_id` também não — vem do token.
Na saída só aparece `image_url` (URL temporária; por ora None).
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.schemas._fields import AwareUtcDatetime

# Teto das URLs de catálogo (capa, prévia e link do provedor). Eram os três
# únicos campos de texto da API sem limite próprio, gravados em colunas Text: o
# único freio era o MAX_JSON_BODY_BYTES, então cada POST enfiava quase 1 MB
# nessas três colunas — cinco faixas por memória, memórias sem teto.
# 2048 é o limite prático que navegadores e proxies aceitam numa URL: folga de
# sobra para os ~100 caracteres que o iTunes devolve, e ainda assim um limite.
MAX_URL_LENGTH = 2048


class MemoryCreate(BaseModel):
    """Entrada do POST /memories."""

    # extra="forbid": bloqueia campos não declarados (ex.: image_path, user_id).
    model_config = ConfigDict(extra="forbid")

    # Título OPCIONAL: uma memória precisa de data e lugar, não de um rótulo.
    # Exigir um obrigava a pessoa a inventar uma etiqueta ("Praia", "Jantar")
    # para poder guardar a lembrança — pedia o índice e dispensava o conteúdo.
    # Vazio é "" e não NULL, pela mesma razão que `text`: a coluna é NOT NULL, e
    # dois jeitos de dizer "não tem" (NULL e "") viram dois caminhos em cada
    # cliente.
    title: str = Field(default="", max_length=120)
    # Descrição OPCIONAL: o texto ainda não é exigido. Ver a divergência aberta
    # em docs/01-regras-negocio.md — o produto quer o texto como núcleo.
    text: str = Field(default="", max_length=5000)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    # Normaliza para UTC-aware: um horário naive seria reinterpretado no fuso da
    # sessão do Postgres (TIMESTAMPTZ), corrompendo a ordem da timeline.
    occurred_at: AwareUtcDatetime


class MemoryUpdate(BaseModel):
    """Entrada do PATCH /memories/{id}. Tudo opcional (atualização parcial)."""

    model_config = ConfigDict(extra="forbid")

    # Sem min_length: string vazia LIMPA o título. É a convenção do PATCH aqui —
    # `null` não mexe no campo, `""` apaga.
    title: str | None = Field(default=None, max_length=120)
    text: str | None = Field(default=None, max_length=5000)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    occurred_at: AwareUtcDatetime | None = None

    @model_validator(mode="after")
    def _lat_long_juntas(self) -> "MemoryUpdate":
        # Não dá pra mover só metade do ponto: latitude e longitude andam juntas.
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("latitude e longitude devem ser enviadas juntas")
        return self


class MemoryImageRead(BaseModel):
    """Uma foto da memória: id (para remover) + URL assinada temporária."""

    id: uuid.UUID
    url: str


class MemoryMusicIn(BaseModel):
    """Entrada do POST /memories/{id}/music — o snapshot da faixa escolhida.

    O cliente manda o que o catálogo devolveu; o backend não consulta provedor
    nenhum. Isso mantém a busca (que exige rede e é do provedor) separada do
    ato de guardar (que é nosso), e deixa o app trocar de catálogo sem que a
    API precise saber."""

    model_config = ConfigDict(extra="forbid")

    provider: str = Field(default="itunes", min_length=1, max_length=20)
    external_id: str = Field(min_length=1, max_length=64)
    title: str = Field(min_length=1, max_length=200)
    artist: str = Field(min_length=1, max_length=200)
    album: str | None = Field(default=None, max_length=200)
    artwork_url: str | None = Field(default=None, max_length=MAX_URL_LENGTH)
    preview_url: str | None = Field(default=None, max_length=MAX_URL_LENGTH)
    external_url: str | None = Field(default=None, max_length=MAX_URL_LENGTH)
    duration_ms: int | None = Field(default=None, ge=0, le=86_400_000)

    @model_validator(mode="after")
    def _urls_sao_web(self) -> "MemoryMusicIn":
        # Só http/https. Estes três valores saem daqui direto para dentro de
        # widgets do app — a capa vira `Image.network`, e o link do provedor
        # existe justamente para um dia reabrir a faixa —, então um
        # `javascript:`, `file:` ou `data:` gravado hoje é uma arma carregada
        # apontada para quem consumir o campo amanhã. Barrar na fronteira de
        # escrita custa estas linhas; auditar para sempre todo widget que tocar
        # no valor, não.
        #
        # A regra vale só na ENTRADA, e é por isso que ela é segura: o que já
        # está gravado continua saindo pelo MemoryMusicRead, que não valida nada
        # — nenhuma linha antiga deixa de ser legível. E o único caminho até
        # aqui é um POST novo, que o app monta com o que o catálogo devolveu
        # (sempre https).
        #
        # `http` segue aceito de propósito: a regra existe para excluir esquema
        # que não é web, não para exigir TLS de um catálogo alheio.
        for campo in ("artwork_url", "preview_url", "external_url"):
            valor = getattr(self, campo)
            # "" é "o provedor não informou" — o app já trata vazio como nulo na
            # leitura. Recusar isso derrubaria uma faixa boa vinda de catálogo
            # pobre, que é o caso que `test_so_titulo_e_artista_bastam` protege.
            if not valor:
                continue
            # lower() porque o esquema é case-insensitive na RFC: "HTTPS://" é
            # uma URL legítima e não pode virar 422.
            if not valor.lower().startswith(("http://", "https://")):
                raise ValueError(f"{campo} deve ser uma URL http ou https")
        return self


class MemoryMusicRead(BaseModel):
    """Uma faixa da memória. Mesmo formato que o `MusicTrack` do app espera."""

    id: uuid.UUID
    provider: str
    external_id: str
    title: str
    artist: str
    album: str | None
    artwork_url: str | None
    preview_url: str | None
    external_url: str | None
    duration_ms: int | None


class MemoryRead(BaseModel):
    """Saída: o que a API devolve de uma memória. Sem user_id, sem location
    crua, sem image_path — o service constrói este DTO a partir do model."""

    id: uuid.UUID
    title: str
    text: str
    latitude: float
    longitude: float
    occurred_at: datetime
    created_at: datetime
    # Fotos (URLs assinadas), na ordem. image_url = a primeira (capa), mantido
    # por compatibilidade com o cliente atual.
    images: list[MemoryImageRead] = []
    # As faixas viajam junto da memória: quem abre uma lembrança quer ver a
    # música com ela, não fazer uma segunda requisição para descobrir.
    music: list[MemoryMusicRead] = []
    image_url: str | None = None
    # O LUGAR (preenchido por geocodificação em segundo plano; nulo enquanto não
    # resolve). `place_label` é o que a UI mostra; os demais alimentam Passaporte,
    # filtros e estatísticas sem o cliente precisar geocodificar nada.
    place_label: str | None = None
    city: str | None = None
    state_province: str | None = None
    country: str | None = None
    country_code: str | None = None
    continent: str | None = None
