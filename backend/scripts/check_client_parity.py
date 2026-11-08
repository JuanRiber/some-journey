"""Paridade entre o que a API expõe e o que os clientes de fato chamam.

Por que existe: já aconteceu três vezes de uma capacidade nascer no backend
testada, documentada e sem ninguém do outro lado — `POST`/`DELETE`
`/journeys/{id}/cover` e `GET /journeys/{id}/memories` ficaram no ar sem
chamador até alguém auditar rota por rota, na mão. Auditoria manual não se
repete sozinha; este script repete, de graça, a cada execução da suíte.

Como ele lê cada lado:

- **Backend**: a tabela de rotas do app FastAPI, não os decoradores. Os
  prefixos moram nos routers (`APIRouter(prefix="/journeys")`), então um grep
  nos `@router.get` devolveria `/{journey_id}/cover` — caminho que não existe.
- **Clientes**: os literais de caminho de `app_flutter/lib/api.dart` e
  que é o único lugar onde um caminho de
  API é escrito. Cada interpolação (`$id`, `${id}`) vira `{}`, que é a mesma
  forma que o parâmetro tem na tabela de rotas — é assim que
  `/journeys/$id/cover` encontra `/journeys/{journey_id}/cover`.

Uso (a partir de `backend/`, com o .venv ativo):

    python -m scripts.check_client_parity          # relatório; saída 1 se houver deriva
    python -m scripts.check_client_parity --all    # mostra também as lacunas já aceitas

O mesmo veredito é cobrado pela suíte em `tests/test_client_parity.py`. O
script é a versão legível do que o pytest já reprova: no CI ele roda ANTES do
pytest justamente porque, rodando depois, o relatório nunca seria impresso —
a suíte teria falhado primeiro, com um assert no lugar da lista de rotas.
"""

import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import NamedTuple

# backend/scripts/este_arquivo.py -> backend/scripts -> backend -> raiz do repo.
_REPO_ROOT = Path(__file__).resolve().parents[2]

# Importar o app exige que as configurações obrigatórias existam, mas NENHUMA
# conexão é aberta aqui — só lemos a tabela de rotas. Estes valores de último
# recurso deixam o script rodar onde não há .env (CI, checkout limpo); onde as
# variáveis reais estão definidas, `setdefault` não encosta nelas.
os.environ.setdefault(
    "DATABASE_URL", "postgresql+psycopg://parity:parity@localhost:5432/parity"
)
os.environ.setdefault(
    "JWT_SECRET_KEY", "client-parity-check-placeholder-key-32b"
)

from fastapi.routing import APIRoute  # noqa: E402 - depois dos defaults acima

_METHODS = ("GET", "POST", "PUT", "PATCH", "DELETE")


class Endpoint(NamedTuple):
    """Uma rota comparável: verbo + caminho com os parâmetros apagados."""

    method: str
    path: str

    def __str__(self) -> str:
        return f"{self.method:<7}{self.path}"


def _order(endpoint: Endpoint) -> tuple[str, str]:
    """Ordena por caminho e depois por verbo: as rotas irmãs ficam juntas."""
    return (endpoint.path, endpoint.method)


# ---------------------------------------------------------------------------
# Lacunas conhecidas e ACEITAS
# ---------------------------------------------------------------------------
# Rotas que nenhum cliente chama de propósito. Só entra aqui o que tem motivo
# escrito ao lado — a lista existe para que o relatório fale apenas de deriva
# NOVA. Sem ela, o check acusaria as mesmas duas sondas de saúde todo dia, e um
# check que grita à toa é desligado na primeira semana.
#
# Quando uma dessas rotas ganhar cliente, o relatório avisa que a entrada já
# pode sair daqui (ele NÃO falha por isso: quem fechou a lacuna não merece um
# vermelho).
KNOWN_GAPS: dict[Endpoint, str] = {
    Endpoint("GET", "/health"): (
        "Liveness. Quem bate aqui é o orquestrador (Render), não o app — e de "
        "propósito não toca o banco."
    ),
    Endpoint("POST", "/auth/google"): (
        "Entrar com o Google: o backend ficou pronto antes do cliente, e de "
        "propósito. A verificação do id_token, o vínculo por `sub` e a "
        "prevenção de conta duplicada são a parte que dá para construir e "
        "testar sem credencial do Google Cloud e sem build assinado de "
        "aparelho. O botão no app continua desenhado e DESLIGADO até existir "
        "um client id — ligar antes seria um botão que não faz nada. Esta "
        "entrada sai daqui no dia em que o cliente chamar a rota."
    ),
    Endpoint("GET", "/journeys/{}/memories"): (
        "Redundante: GET /journeys/{id} devolve JourneyDetailRead, que já traz "
        "`points` com as memórias da jornada — e é por ali que o app lê. Esta "
        "rota parecia alcançada até outubro de 2026 só porque o cliente Expo "
        "declarava um wrapper que nenhuma tela chamava; removido o Expo, ela "
        "apareceu pelo que é. Fica de pé porque o contrato está publicado, sem "
        "cliente porque não há o que ela resolva."
    ),
    Endpoint("GET", "/health/ready"): (
        "Readiness e keep-warm. Também é infraestrutura: o app não deve decidir "
        "nada a partir dela, só tentar a chamada real e tratar o erro."
    ),
}


# O único lugar onde um caminho de API é escrito do lado do cliente. Qualquer
# chamada fora daqui passa despercebida por este check; é o preço de não varrer
# as telas atrás de string.
#
# Continua sendo um dicionário, e não um caminho só, porque a estrutura é o que
# torna barato acrescentar um segundo cliente se um dia existir — foi assim que
# o app Expo entrou e saiu sem reescrever este arquivo.
# Caminhos que o cliente MONTA em tempo de execução, e que por isso nunca
# aparecem inteiros no arquivo.
#
# `_lifecycle(id, action)` escreve `'/journeys/$id/$action'` e recebe
# 'start'|'pause'|'resume'|'finish' dos quatro métodos logo abaixo dele. O
# extrator enxerga `/journeys/{}/{}` e não tem como saber que segmento é aquele.
#
# Declarar é mais honesto que ensinar o parser a adivinhar: expandir `{}` contra
# todo literal do arquivo marcaria `/journeys/{}/memories` como alcançada só
# porque a palavra "memories" aparece em outro lugar — encobrindo exatamente a
# deriva que este check existe para achar. O teste ao lado cobra que cada
# entrada continue verdadeira nas duas pontas.
ASSEMBLED: dict[str, tuple[str, ...]] = {
    "/journeys/{}/{}": (
        "/journeys/{}/start",
        "/journeys/{}/pause",
        "/journeys/{}/resume",
        "/journeys/{}/finish",
    ),
}


CLIENTS: dict[str, Path] = {
    "app_flutter": _REPO_ROOT / "app_flutter" / "lib" / "api.dart",
}


# ---------------------------------------------------------------------------
# Lado do backend
# ---------------------------------------------------------------------------

_PARAM = re.compile(r"\{[^}]*\}")


def normalise_route(path: str) -> str:
    """`/journeys/{journey_id}/cover` vira `/journeys/{}/cover`.

    O nome do parâmetro é escolha do backend; o cliente interpola um valor e não
    tem nome nenhum para oferecer. Comparar com o nome dentro acusaria deriva em
    toda rota que recebe um id — ou seja, em quase todas.
    """
    return _PARAM.sub("{}", path)


def _api_routes(routes):
    """Percorre a tabela de rotas, descendo nos routers incluídos.

    A partir do FastAPI 0.138 o `include_router` guarda um nó que embrulha o
    router original em vez de achatar as rotas no app; em versões anteriores a
    tabela já vinha achatada e este laço simplesmente não encontra o que descer.
    """
    for route in routes:
        nested = getattr(getattr(route, "original_router", None), "routes", None)
        if nested is not None:
            yield from _api_routes(nested)
        elif isinstance(route, APIRoute):
            yield route


def backend_routes(application=None) -> set[Endpoint]:
    """Toda rota que a API expõe hoje.

    Duas fontes, unidas de propósito: a tabela de rotas enxerga também o que foi
    marcado `include_in_schema=False`, e o esquema OpenAPI é a leitura pública e
    estável. Se uma versão nova do FastAPI mudar de novo o formato da tabela, a
    união impede que a coleta volte vazia — e uma coleta vazia faria este check
    passar para sempre, que é o pior desfecho possível para ele.
    """
    if application is None:
        from app.main import app as application

    found: set[Endpoint] = set()
    for route in _api_routes(application.routes):
        for method in route.methods or ():
            if method in _METHODS:
                found.add(Endpoint(method, normalise_route(route.path)))
    for path, operations in application.openapi().get("paths", {}).items():
        for method in operations:
            if method.upper() in _METHODS:
                found.add(Endpoint(method.upper(), normalise_route(path)))

    if not found:
        raise RuntimeError(
            "Nenhuma rota lida do app FastAPI: a coleta quebrou. Sem isto o "
            "check passaria em silêncio, que é exatamente o que ele existe para "
            "evitar."
        )
    return found


# ---------------------------------------------------------------------------
# Lado dos clientes
# ---------------------------------------------------------------------------

_QUOTES = "'\"`"

# A forma em que o verbo vem DEPOIS do caminho, nas opções:
# `fetch(url, { method: "POST", ... })`. Nenhum cliente atual escreve assim —
# fica porque é barato e porque foi a forma do cliente anterior.
_METHOD_OPTION = re.compile(r"""method\s*[:=]\s*["'`](GET|POST|PUT|PATCH|DELETE)["'`]""")

# Quanto o verbo pode estar antes do caminho para ainda ser dele. Cobre
# `request("POST", "/journeys")` quebrado em várias linhas sem alcançar a
# chamada anterior.
_METHOD_REACH_BEFORE = 120
_METHOD_REACH_AFTER = 400


def _skip_interpolation(source: str, start: int) -> int:
    """Pula a expressão interpolada que começa na chave em `source[start]`.

    Atravessa chaves aninhadas E literais de string dentro da expressão — é o
    que impede a barra de `type.split("/")[1]` de ser lida como um caminho de
    API e encobrir uma deriva de verdade.
    """
    depth = 0
    i = start
    while i < len(source):
        char = source[i]
        if char in _QUOTES:
            _, i = _scan_literal(source, i)
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return i


def _scan_literal(source: str, start: int) -> tuple[str | None, int]:
    """Lê o literal de string que começa em `source[start]`.

    Devolve (conteúdo, índice seguinte). Cada interpolação — `$id` e `${id}` no
    Dart, `${id}` no TypeScript — vira o marcador `{}`, que é a forma que o
    parâmetro tem na tabela de rotas depois de `normalise_route`.

    Literal que atravessa a linha volta como None: caminho de API não faz isso,
    e parar na quebra evita que uma aspa solta engula o resto do arquivo.
    """
    quote = source[start]
    i = start + 1
    out: list[str] = []
    while i < len(source):
        char = source[i]
        if char == "\\":
            out.append(source[i + 1 : i + 2])
            i += 2
            continue
        if char == quote:
            return "".join(out), i + 1
        if char == "\n":
            return None, i + 1
        if char == "$" and source[i + 1 : i + 2] == "{":
            out.append("{}")
            i = _skip_interpolation(source, i + 1)
            continue
        if char == "$":
            end = i + 1
            while end < len(source) and (source[end].isalnum() or source[end] == "_"):
                end += 1
            if end > i + 1:
                out.append("{}")
                i = end
                continue
        out.append(char)
        i += 1
    return None, i


def _literals(source: str) -> list[tuple[int, str]]:
    """Os literais de string do fonte, cada um com a posição em que começa.

    Comentários são pulados antes de qualquer coisa. Além de não conterem
    chamada nenhuma, os deste projeto são em português e cheios de aspas e
    crases: ler um deles como código desalinharia a varredura do arquivo
    inteiro, e o resultado seria uma lista de caminhos inventados.
    """
    found: list[tuple[int, str]] = []
    i, size = 0, len(source)
    while i < size:
        if source.startswith("//", i):
            end = source.find("\n", i)
            i = size if end < 0 else end + 1
            continue
        if source.startswith("/*", i):
            end = source.find("*/", i)
            i = size if end < 0 else end + 2
            continue
        if source[i] in _QUOTES:
            start = i
            text, i = _scan_literal(source, start)
            if text is not None:
                found.append((start, text))
            continue
        i += 1
    return found


def as_path(literal: str) -> str | None:
    """Normaliza um literal de cliente no caminho comparável, ou None.

    `${API_URL}/memories/${id}/images` vira `/memories/{}/images`: a base sai
    fora, cada interpolação vira `{}` e a querystring é descartada — o que sobra
    tem exatamente o formato da tabela de rotas.
    """
    text = literal
    if text.startswith("{}/"):
        # A base (`$apiUrl`, `${API_URL}`) não faz parte da rota.
        text = text[2:]
    if not text.startswith("/"):
        return None
    text = text.split("?", 1)[0].split("#", 1)[0]

    segments: list[str] = []
    for segment in text.strip("/").split("/"):
        if segment == "{}":
            segments.append("{}")
            continue
        if "{}" in segment:
            # Segmento meio fixo, meio expressão (`/map${qs ? "?" + qs : ""}`):
            # só o pedaço fixo é caminho; do `{}` em diante é querystring ou
            # sufixo montado em tempo de execução.
            prefix = segment.split("{}", 1)[0]
            if prefix:
                segments.append(prefix)
            break
        segments.append(segment)
    return "/" + "/".join(segments)


def client_calls(source: str) -> set[tuple[str | None, str]]:
    """Os endpoints que este fonte chama, como (verbo, caminho).

    O verbo é o literal imediatamente anterior ao caminho
    (`request("POST", "/journeys")`) ou, quando o caminho vai para um `fetch`, o
    `method:` das opções logo adiante. Quando nenhum dos dois aparece — os
    ajudantes do cliente Flutter (`_page`, `_upload`, `_uploadJson`) fixam o
    verbo dentro deles —, o verbo fica None e o caminho passa a valer para
    QUALQUER verbo.

    Esse None é deliberado. Errar para o lado de "coberto" perde alguma deriva;
    errar para o lado de "descoberto" põe no relatório uma rota que alguém
    chama. Um relatório com ruído é desligado; um relatório que perde um caso
    ainda pega os outros.
    """
    found: set[tuple[str | None, str]] = set()
    entries = _literals(source)
    for index, (position, text) in enumerate(entries):
        path = as_path(text)
        if path is None:
            continue
        method: str | None = None
        if index:
            before_position, before_text = entries[index - 1]
            if (
                before_text in _METHODS
                and position - before_position <= _METHOD_REACH_BEFORE
            ):
                method = before_text
        if method is None:
            ahead = _METHOD_OPTION.search(
                source, position, position + _METHOD_REACH_AFTER
            )
            if ahead is not None:
                method = ahead.group(1)
        found.add((method, path))
    return found


def client_endpoints(clients: dict[str, Path] | None = None) -> set[tuple[str | None, str]]:
    """A união do que todos os clientes chamam.

    Um arquivo de cliente que sumiu é erro, não resultado: sem ele TODA rota
    pareceria sem chamador e o relatório viraria ruído puro.
    """
    found: set[tuple[str | None, str]] = set()
    for name, path in (CLIENTS if clients is None else clients).items():
        if not path.exists():
            raise FileNotFoundError(
                f"Cliente '{name}' não encontrado em {path}. Sem o arquivo, toda "
                "rota pareceria sem chamador — corrija o caminho em CLIENTS."
            )
        found |= client_calls(path.read_text(encoding="utf-8"))
    return found | _expand_assembled(found)


def _expand_assembled(
    calls: set[tuple[str | None, str]],
    assembled: dict[str, tuple[str, ...]] | None = None,
) -> set[tuple[str | None, str]]:
    """Resolve os caminhos montados em tempo de execução (ver ASSEMBLED).

    O verbo da chamada original é preservado: quem monta o caminho não muda de
    método no caminho.
    """
    tabela = ASSEMBLED if assembled is None else assembled
    extra: set[tuple[str | None, str]] = set()
    for method, path in calls:
        for concreto in tabela.get(path, ()):
            extra.add((method, concreto))
    return extra


# ---------------------------------------------------------------------------
# Comparação e relatório
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Report:
    """O cruzamento das duas coletas."""

    routes: set[Endpoint]
    reached: set[Endpoint]
    # Sem cliente e sem motivo declarado: é isto que reprova.
    drift: list[Endpoint]
    # Sem cliente, mas com motivo escrito em KNOWN_GAPS.
    accepted: list[Endpoint]
    # Em KNOWN_GAPS e JÁ alcançadas: a entrada pode sair da lista.
    settled: list[Endpoint]
    # Em KNOWN_GAPS e sem rota correspondente: a entrada ficou órfã.
    orphans: list[Endpoint]


def compare(
    routes: set[Endpoint],
    calls: set[tuple[str | None, str]],
    known_gaps: dict[Endpoint, str] | None = None,
) -> Report:
    """Cruza rotas e chamadas.

    Uma rota está alcançada quando algum cliente chama exatamente (verbo,
    caminho) ou quando chama aquele caminho por um ajudante que fixa o verbo
    dentro de si (verbo None).
    """
    gaps = KNOWN_GAPS if known_gaps is None else known_gaps
    any_method = {path for method, path in calls if method is None}
    exact = {Endpoint(method, path) for method, path in calls if method is not None}

    reached = {r for r in routes if r in exact or r.path in any_method}
    missing = sorted(routes - reached, key=_order)
    return Report(
        routes=set(routes),
        reached=reached,
        drift=[r for r in missing if r not in gaps],
        accepted=[r for r in missing if r in gaps],
        settled=sorted((r for r in gaps if r in reached), key=_order),
        orphans=sorted((r for r in gaps if r not in routes), key=_order),
    )


def run() -> Report:
    """A verificação completa, como o CI e a suíte a executam."""
    return compare(backend_routes(), client_endpoints())


def format_report(report: Report, show_accepted: bool = False) -> str:
    """O relatório legível. É o que o CI imprime e o que o pytest anexa ao erro."""
    lines = [
        "Paridade cliente <-> backend",
        "",
        f"  rotas expostas pelo backend ........ {len(report.routes)}",
        f"  alcançadas por algum cliente ....... {len(report.reached)}",
        f"  lacunas declaradas em KNOWN_GAPS ... {len(report.accepted)}",
        "",
    ]

    if report.drift:
        quantas = len(report.drift)
        lines.append(
            f"DERIVA: {quantas} rota{'s' if quantas > 1 else ''} que nenhum cliente "
            f"chama e que ninguém declarou."
        )
        lines.append("")
        lines += [f"  {endpoint}" for endpoint in report.drift]
        lines += [
            "",
            "Ou algum cliente passa a chamar (app_flutter/lib/api.dart),",
            "ou a lacuna entra em KNOWN_GAPS, em",
            "backend/scripts/check_client_parity.py, com o motivo escrito ao lado.",
        ]
    else:
        lines.append(
            "Sem deriva: toda rota tem cliente, ou tem motivo escrito para não ter."
        )

    if show_accepted and report.accepted:
        lines += ["", "Lacunas aceitas:"]
        for endpoint in report.accepted:
            lines.append(f"  {endpoint}")
            lines.append(f"          {KNOWN_GAPS[endpoint]}")

    # Os dois avisos abaixo NÃO reprovam: quem fechou uma lacuna ou apagou uma
    # rota fez a coisa certa e não merece um vermelho por causa da lista.
    if report.settled:
        lines += ["", "Já têm cliente — podem sair de KNOWN_GAPS:"]
        lines += [f"  {endpoint}" for endpoint in report.settled]
    if report.orphans:
        lines += ["", "Não existem mais como rota — podem sair de KNOWN_GAPS:"]
        lines += [f"  {endpoint}" for endpoint in report.orphans]

    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Aponta as rotas do backend que nenhum cliente chama."
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="lista também as lacunas já aceitas, com o motivo de cada uma",
    )
    args = parser.parse_args(argv)

    report = run()
    print(format_report(report, show_accepted=args.all))
    return 1 if report.drift else 0


if __name__ == "__main__":
    sys.exit(main())
