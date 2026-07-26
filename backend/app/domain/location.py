"""`Location` — o LUGAR de uma memória, como conceito de domínio.

Regra da casa: as colunas ficam achatadas em `memories` (as agregações do Perfil
dependem disso), mas nenhuma regra de lugar mora nas rotas, nas telas ou espalhada
pelos services. Tudo passa por este Value Object.

Características:
- **Imutável** (`frozen=True`) e **igual por VALOR** — dois lugares com os mesmos
  dados SÃO o mesmo lugar, o que permite agrupar/deduplicar sem gambiarra.
- **Sem dependência de ORM nem de HTTP**: dá para usar (e testar) sem banco e sem
  rede. Quem mapeia para colunas é o repository; quem preenche via provedor é o
  serviço de geocodificação.
- Reutilizável: o mesmo objeto servirá Memórias, Jornadas (origem/destino), Atlas
  e Eras. É por isso que ele nasce separado do model de memória.
"""

from dataclasses import dataclass, replace
from datetime import datetime

from app.core.geohash import encode as geohash_encode
from app.domain.continents import continent_for


@dataclass(frozen=True, slots=True)
class Location:
    """Coordenadas + o lugar que elas significam.

    Só `latitude`/`longitude` são obrigatórias: uma memória sempre tem ponto, mas
    pode não ter (ainda) os dados do lugar — geocodificar falha, e registrar a
    memória nunca pode depender disso.
    """

    latitude: float
    longitude: float

    place_name: str | None = None
    place_label: str | None = None
    city: str | None = None
    state_province: str | None = None
    country: str | None = None
    country_code: str | None = None
    continent: str | None = None
    formatted_address: str | None = None
    timezone: str | None = None
    geohash: str | None = None
    geocoded_at: datetime | None = None

    def __post_init__(self) -> None:
        # Validação de mundo: coordenada impossível é erro de programação/entrada,
        # não algo a persistir silenciosamente.
        if not -90 <= self.latitude <= 90:
            raise ValueError("latitude deve estar entre -90 e 90")
        if not -180 <= self.longitude <= 180:
            raise ValueError("longitude deve estar entre -180 e 180")
        # Normaliza o código do país para ISO-2 MAIÚSCULO já na fronteira: o
        # Passaporte conta `COUNT(DISTINCT country_code)` e "br" vs "BR" viraria
        # dois países.
        if self.country_code is not None:
            object.__setattr__(self, "country_code", self.country_code.strip().upper() or None)
        # O geohash é derivado, nunca digitado: se não veio, calcula.
        if self.geohash is None:
            object.__setattr__(self, "geohash", geohash_encode(self.latitude, self.longitude))
        # Continente é DERIVADO do país (tabela estática, sem rede).
        if self.continent is None and self.country_code:
            object.__setattr__(self, "continent", continent_for(self.country_code))

    @property
    def is_geocoded(self) -> bool:
        """True quando o lugar já foi resolvido pelo provedor.

        `geocoded_at IS NULL` é justamente a fila de reprocessamento (backfill)."""
        return self.geocoded_at is not None

    @property
    def display_label(self) -> str:
        """Rótulo curto para a UI: "Praia de Iracema, Fortaleza" → "Fortaleza,
        Brasil" → coordenadas, nesta ordem de preferência.

        Sempre devolve ALGO: uma memória sem geocodificação ainda precisa se
        apresentar em lista, e mostrar vazio seria uma tela morta.
        """
        if self.place_label:
            return self.place_label
        parts = [p for p in (self.place_name or self.city, self.country) if p]
        if parts:
            return ", ".join(parts)
        return f"{self.latitude:.4f}, {self.longitude:.4f}"

    def with_geocoding(
        self,
        *,
        place_name: str | None = None,
        place_label: str | None = None,
        city: str | None = None,
        state_province: str | None = None,
        country: str | None = None,
        country_code: str | None = None,
        formatted_address: str | None = None,
        timezone: str | None = None,
        geocoded_at: datetime,
    ) -> "Location":
        """Devolve uma NOVA Location com os dados do provedor aplicados.

        Imutável de propósito: o serviço de geocodificação não muda o lugar "por
        baixo" de quem já o segurava. O continente é recalculado a partir do novo
        país (por isso `continent` não é parâmetro)."""
        return replace(
            self,
            place_name=place_name,
            place_label=place_label,
            city=city,
            state_province=state_province,
            country=country,
            country_code=country_code,
            continent=None,  # __post_init__ deriva do country_code novo
            formatted_address=formatted_address,
            timezone=timezone,
            geocoded_at=geocoded_at,
        )

    def to_columns(self) -> dict[str, object]:
        """Achata o VO nas colunas de `memories`.

        Só o repository usa isto — é o único ponto do sistema que conhece o
        mapeamento objeto↔colunas. `latitude`/`longitude` ficam de fora porque a
        posição é gravada na coluna GEOGRAPHY (POINT), não em dois floats.
        """
        return {
            "place_name": self.place_name,
            "place_label": self.place_label,
            "city": self.city,
            "state_province": self.state_province,
            "country": self.country,
            "country_code": self.country_code,
            "continent": self.continent,
            "formatted_address": self.formatted_address,
            "timezone": self.timezone,
            "geohash": self.geohash,
            "geocoded_at": self.geocoded_at,
        }

    @classmethod
    def from_row(cls, *, latitude: float, longitude: float, row: object) -> "Location":
        """Reconstrói o VO a partir de uma linha do ORM (ou de qualquer objeto com
        os mesmos atributos). Contraparte de `to_columns`, também exclusiva do
        repository."""
        get = lambda name: getattr(row, name, None)  # noqa: E731
        return cls(
            latitude=latitude,
            longitude=longitude,
            place_name=get("place_name"),
            place_label=get("place_label"),
            city=get("city"),
            state_province=get("state_province"),
            country=get("country"),
            country_code=get("country_code"),
            continent=get("continent"),
            formatted_address=get("formatted_address"),
            timezone=get("timezone"),
            geohash=get("geohash"),
            geocoded_at=get("geocoded_at"),
        )
