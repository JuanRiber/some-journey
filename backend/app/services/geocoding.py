"""Reverse geocoding — serviço DEDICADO e desacoplado do provedor.

Contrato (`GeocodingProvider`) + adapter (`NominatimGeocodingProvider`), no mesmo
padrão do provedor de música do app: trocar de provedor é escrever outra classe.

Regra inegociável: **geocodificar NUNCA bloqueia a escrita**. A memória é gravada
com as coordenadas; se o provedor falhar, `geocoded_at` fica nulo e a linha entra
na fila de backfill (índice `ix_memories_pending_geocode`). Perder o nome do lugar
é um incômodo; perder a memória é inaceitável.
"""

import logging
from datetime import UTC, datetime
from typing import Protocol

import httpx

from app.core.config import settings
from app.domain.location import Location

logger = logging.getLogger("app.geocoding")


class GeocodingProvider(Protocol):
    """Resolve coordenadas em um lugar. Implementações NÃO devem levantar: um
    provedor indisponível devolve None e o fluxo segue sem o lugar."""

    def reverse(self, latitude: float, longitude: float) -> Location | None: ...


class NullGeocodingProvider:
    """Provedor desligado (padrão em testes e quando não se quer rede).

    Existe para que o serviço tenha SEMPRE um colaborador válido — nada de `if
    provider is None` espalhado pelo código."""

    def reverse(self, latitude: float, longitude: float) -> Location | None:
        return None


class NominatimGeocodingProvider:
    """Adapter do Nominatim (OpenStreetMap) — gratuito e sem chave.

    Cuidados que a política de uso do Nominatim EXIGE, e que ficam confinados
    aqui (nunca espalhados pelo resto do sistema):
    - **User-Agent identificável**: requisição anônima é bloqueada.
    - **Máximo ~1 req/s**: respeitamos um intervalo mínimo entre chamadas.

    `timezone` não vem do Nominatim; é resolvido por um colaborador opcional
    (`timezone_resolver`) a partir das coordenadas, para não depender de mais uma
    chamada de rede por memória. Sem resolvedor, o campo fica nulo — e a memória
    é salva do mesmo jeito.
    """

    _ENDPOINT = "https://nominatim.openstreetmap.org/reverse"
    _MIN_INTERVAL_SECONDS = 1.0

    def __init__(
        self,
        *,
        user_agent: str = "SomeJourney/1.0 (contato: suporte@some-journey.app)",
        client: httpx.Client | None = None,
        timeout: float = 8.0,
        timezone_resolver=None,
        now=lambda: datetime.now(UTC),
    ) -> None:
        self._user_agent = user_agent
        self._client = client
        self._timeout = timeout
        self._timezone_resolver = timezone_resolver
        self._now = now
        self._last_call_at: datetime | None = None

    def _respect_rate_limit(self) -> bool:
        """True quando é permitido chamar agora. Preferimos PULAR (e deixar para
        o backfill) a segurar a thread de uma requisição HTTP do usuário."""
        last = self._last_call_at
        if last is None:
            return True
        return (self._now() - last).total_seconds() >= self._MIN_INTERVAL_SECONDS

    def reverse(self, latitude: float, longitude: float) -> Location | None:
        if not self._respect_rate_limit():
            logger.info("Geocoding pulado (rate limit); ficará para o backfill.")
            return None

        params = {
            "lat": f"{latitude}",
            "lon": f"{longitude}",
            "format": "jsonv2",
            "zoom": "16",  # nível de rua/bairro: bom para "Praia de Iracema"
            "addressdetails": "1",
        }
        headers = {"User-Agent": self._user_agent, "Accept-Language": "pt-BR,pt,en"}

        try:
            self._last_call_at = self._now()
            if self._client is not None:
                response = self._client.get(
                    self._ENDPOINT, params=params, headers=headers, timeout=self._timeout
                )
            else:
                with httpx.Client(timeout=self._timeout) as client:
                    response = client.get(self._ENDPOINT, params=params, headers=headers)
            if response.status_code >= 400:
                logger.warning("Geocoding respondeu %s", response.status_code)
                return None
            payload = response.json()
        except Exception as exc:  # noqa: BLE001 - nunca derrubar a escrita
            logger.warning("Geocoding indisponível: %s", type(exc).__name__)
            return None

        return self._to_location(latitude, longitude, payload)

    def _to_location(self, latitude: float, longitude: float, payload: object) -> Location | None:
        """Traduz a resposta do Nominatim para o VO. Único ponto do sistema que
        conhece o formato do provedor."""
        if not isinstance(payload, dict) or "address" not in payload:
            return None
        address = payload.get("address") or {}
        if not isinstance(address, dict):
            return None

        # O Nominatim varia MUITO o campo da cidade conforme o país/zona.
        city = (
            address.get("city")
            or address.get("town")
            or address.get("village")
            or address.get("municipality")
            or address.get("suburb")
        )
        country_code = address.get("country_code")
        place_name = payload.get("name") or address.get("tourism") or address.get("road")
        display_name = payload.get("display_name")

        timezone = None
        if self._timezone_resolver is not None:
            try:
                timezone = self._timezone_resolver(latitude, longitude)
            except Exception:  # noqa: BLE001 - fuso é acessório
                timezone = None

        base = Location(latitude=latitude, longitude=longitude)
        return base.with_geocoding(
            place_name=place_name,
            # Rótulo curto e humano: "Praia de Iracema, Fortaleza".
            place_label=", ".join([p for p in (place_name, city) if p]) or None,
            city=city,
            state_province=address.get("state") or address.get("province"),
            country=address.get("country"),
            country_code=country_code,
            formatted_address=display_name,
            timezone=timezone,
            geocoded_at=self._now(),
        )


def resolve_timezone(latitude: float, longitude: float) -> str | None:
    """Fuso IANA a partir das coordenadas, OFFLINE.

    Mora aqui, e não dentro do adapter, porque nada disto vem do Nominatim: ele
    não devolve fuso, e perguntar a um serviço de fuso seria mais uma chamada de
    rede POR MEMÓRIA — exatamente o que a decisão de arquitetura evita.

    A importação é local de propósito: sem a biblioteca instalada o campo fica
    nulo e a memória é gravada do mesmo jeito (o `geocoded_at` continua válido —
    o fuso é acessório, não motivo de reprocessamento).

    Cuidado: `tzfpy.get_tz` recebe **(longitude, latitude)**, a ordem inversa da
    deste contrato. A troca acontece aqui, uma vez só.
    """
    try:
        from tzfpy import get_tz
    except ImportError:  # pragma: no cover - ambiente sem a dependência opcional
        logger.warning("tzfpy indisponível: o fuso da memória ficará nulo.")
        return None
    return get_tz(longitude, latitude)


def get_provider() -> GeocodingProvider:
    """Composição: qual provedor o app usa AGORA.

    Único ponto que escolhe a implementação — trocar de provedor (ou desligar) não
    toca em service, repository nem rota. Em ambiente de TESTE devolve sempre o
    Null: suíte não faz rede, não depende de terceiros e não fica lenta/instável.
    """
    if not settings.geocoding_enabled:
        return NullGeocodingProvider()
    return NominatimGeocodingProvider(
        user_agent=settings.GEOCODING_USER_AGENT,
        timezone_resolver=resolve_timezone,
    )


def resolve_location(
    provider: GeocodingProvider, *, latitude: float, longitude: float
) -> Location:
    """Ponto de entrada do serviço: devolve SEMPRE uma Location.

    Com geocodificação quando o provedor responde; só com as coordenadas quando
    não responde. Quem chama (o service de memória) não precisa saber de nada
    disso — e não tem como esquecer de tratar a falha."""
    try:
        located = provider.reverse(latitude, longitude)
    except Exception as exc:  # noqa: BLE001 - defesa extra contra adapters mal-comportados
        logger.warning("Provedor de geocoding falhou: %s", type(exc).__name__)
        located = None
    return located or Location(latitude=latitude, longitude=longitude)
