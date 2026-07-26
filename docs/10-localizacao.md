# Localização da memória — objeto completo (migração 0009)

> **Substitui** a recomendação reduzida (`city`/`country`/`place_label`) da seção
> "bloqueador" de [`09-perfil.md`](09-perfil.md). Uma memória não guarda um par de
> coordenadas: ela guarda O LUGAR onde aconteceu, por inteiro e para sempre.

## Princípio

O lugar é preenchido por **reverse geocoding no momento da escrita** e fica
persistido. O app nunca volta ao provedor para saber onde uma memória aconteceu —
nem para montar o Passaporte, nem para estatísticas, nem daqui a cinco anos se o
provedor mudar de política ou sair do ar.

## Campos em `memories` (todos NULLABLE)

| Campo | Tipo | Nota |
| --- | --- | --- |
| `latitude`, `longitude` | já existem | `GEOGRAPHY(POINT)` continua a fonte espacial |
| `place_name` | `text` | nome do ponto (ex.: "Praia de Iracema") |
| `place_label` | `text` | rótulo exibido ao usuário (hoje é descartado pelo picker) |
| `city` | `text` | agregado no Perfil |
| `state_province` | `text` | estado/província |
| `country` | `text` | nome por extenso |
| `country_code` | `char(2)` | ISO-3166-1 alpha-2; base do continente |
| `continent` | `text` | **derivado** de `country_code` |
| `formatted_address` | `text` | endereço completo do provedor |
| `timezone` | `text` | IANA (ex.: `America/Fortaleza`) |
| `geohash` | `varchar(12)` | ver `app/core/geohash.py` (já commitado) |
| `geocoded_at` | `timestamptz` | `NULL` = ainda não geocodificado (para backfill) |

**Por que tudo nullable:** geocodificar pode falhar (rede, limite de uso, lugar no
meio do oceano). Registrar a memória **nunca** pode depender disso — as coordenadas
bastam. `geocoded_at IS NULL` é a fila de reprocessamento.

**Índices:** `city`, `country_code` e `geohash` (o Perfil agrega por eles; o
geohash serve busca por prefixo). Parciais `WHERE deleted_at IS NULL`, como o
restante do schema.

## `Location` é um CONCEITO DE DOMÍNIO, não um punhado de colunas

As colunas ficam **achatadas** em `memories` (consulta e agregação em SQL são
rápidas assim — o Perfil depende disso), mas **nenhuma regra de lugar mora nas
telas nem nos services espalhados**. Toda manipulação passa por um Value Object:

- `Location` (frozen/imutável, sem dependência de ORM ou HTTP): compõe as
  coordenadas + os campos do lugar, sabe se está geocodificado
  (`is_geocoded`), deriva o `continent` a partir do `country_code`, calcula o
  `geohash`, e formata o rótulo curto ("Fortaleza, Brasil") que a UI exibe.
- Igualdade por VALOR (dois lugares iguais são o mesmo lugar) — é o que permite
  agrupar, deduplicar e comparar sem gambiarra.
- O ORM **mapeia** o VO de/para as colunas (composição), e o repository é o único
  lugar que conhece esse mapeamento.

**Por que agora:** o mesmo `Location` será reutilizado por Memórias, **Jornadas**
(origem/destino), **Atlas**, **Eras** e o que vier. Se a regra nascer solta dentro
do service de memória, cada nova funcionalidade a duplicará com pequenas
diferenças — exatamente a dívida que estamos evitando.

### A modelagem precisa sustentar (não só o Perfil)

Passaporte de países/continentes · estatísticas geográficas · Atlas e Eras ·
Revisitar · heatmaps e clustering · sugestões de memórias próximas · filtros por
região/cidade/país.

Consequências práticas disso na 0009: `country_code` normalizado (ISO-2, não texto
livre) para o Passaporte contar sem ambiguidade; `city` + `country_code` indexados
para os filtros; `geohash` indexado para vizinhança/clustering; `geocoded_at` para
reprocessar quando o provedor melhorar. Nada disso exige nova migração depois.

## Decisões de arquitetura

- **Serviço dedicado e desacoplado.** `GeocodingProvider` (interface) +
  `NominatimGeocodingProvider` (adapter) — mesmo padrão do `MusicProvider`. Trocar
  de provedor = uma classe nova.
- **Nunca bloquear a escrita.** A memória é gravada primeiro; o geocode preenche o
  objeto. Falha → persiste sem lugar, `geocoded_at` nulo, backfill depois.
- **`continent`** não vem do Nominatim: derivar de `country_code` por **tabela
  estática** (sem chamada extra de rede).
- **`timezone`** também não vem do Nominatim: resolver **pelas coordenadas**
  (biblioteca de lookup tz offline, ex. `timezonefinder`) — evita mais uma
  dependência de rede por memória.
- **Nominatim exige** User-Agent identificável e **máx. 1 req/s**: rate limit e
  cabeçalho ficam DENTRO do adapter, nunca espalhados.

## `GET /me/profile` (depois da 0009)

Um único endpoint, **todas as contagens em SQL** — o cliente jamais baixa memórias
para contar (isso derrubaria a paginação por keyset já implementada).

Deve servir: **Passaporte** (`COUNT(DISTINCT city)`, `COUNT(DISTINCT country)`,
continentes visitados), **última aventura**, estatísticas (memórias, jornadas
concluídas, fotos, músicas, km via PostGIS), **mapa pessoal**, **jornada atual**
(a `active` + progresso) e atividade recente.

## Critérios de conclusão (a migração só está pronta com todos)

1. `alembic upgrade head` **e** `downgrade` validados em banco LIMPO.
2. Suíte inteira passando, sem regressões.
3. Modelagem preparada para Passaporte, Atlas, Eras, Revisitar e estatísticas
   geográficas.
4. Revision id com **≤ 32 caracteres** (`alembic_version.version_num` é
   `varchar(32)` — já quebrou uma vez neste projeto).
