# Convenções do projeto — o que o analisador não vê

> Nada aqui é preferência de estilo. São as regras que o `flutter analyze` aprova,
> que o `pytest` deixa passar e que mesmo assim já custaram tempo a alguém. Quase
> todas falham **em silêncio**: a tela salva, a API responde 200, o teste fica
> verde — e o comportamento está errado. Até hoje essas regras só existiam em
> docstring de arquivo, em corpo de commit e em teste escrito depois do estrago.
> Este documento junta tudo num lugar só.

Formato de cada item: **a regra · onde ela mora · o que acontece se errar.**

---

## 1. No `PATCH`, `null` não mexe no campo; string vazia é que apaga

**Onde.** `backend/app/repositories/journey_repository.py` (`update_journey`) e
`backend/app/repositories/memory_repository.py` (`update`). Os dois guardam cada
atribuição com `if campo is not None`. Do lado do app, quem monta o corpo é
`app_flutter/lib/screens/journey_edit.dart` e `memory_edit.dart`; a regra está
travada por `app_flutter/test/journey_patch_test.dart`.

**Por quê.** Ausente e vazio são coisas diferentes: "não quis tocar neste campo"
não é "quis deixar em branco". Uma edição parcial que mandasse todos os campos
sempre sobrescreveria trabalho alheio sem motivo.

**Se errar.** Mandar `null` para limpar uma descrição — que é o intuitivo — não
produz erro nenhum: a resposta é 200, e o texto antigo reaparece na leitura
seguinte. O mesmo vale para o título da memória, que desde outubro é opcional e
segue a mesma convenção (`""` apaga, `null` não mexe).

**Detalhe que já pegou.** Em `memory_repository.update`, latitude e longitude são
aplicadas **juntas** (`if latitude is not None and longitude is not None`).
Mandar só uma das duas é um no-op silencioso — o ponto não se move.

---

## 2. PostGIS é longitude PRIMEIRO; `flutter_map` é latitude primeiro

**Onde.** O helper `_point()` está escrito duas vezes, de propósito, com o aviso
repetido no docstring: `backend/app/repositories/memory_repository.py` e
`backend/app/repositories/track_repository.py`. A mesma ordem aparece no
recorte por janela (`_bbox_filter`, que recebe `(min_lng, min_lat, max_lng,
max_lat)`) e no GeoJSON de `backend/app/services/map_service.py`, que emite
`[longitude, latitude]`. Na fronteira com o app a ordem **inverte**:
`app_flutter/lib/widgets/atlas_map.dart` desvira com `LatLng(c[1], c[0])`,
porque `LatLng` é latitude primeiro.

**Por quê.** É a ordem do WKT/GeoJSON (`POINT(x y)`, e `x` é longitude). Não é
escolha nossa e não adianta brigar: o que dá para fazer é deixar o aviso colado
em cada lugar que escreve ou lê coordenada crua.

**Se errar.** Nada quebra. O ponto só aparece em outro lugar do mundo: Fortaleza
(`-3.73, -38.52`) invertida cai no meio do Atlântico Sul. Não há exceção, não há
log, e a memória fica gravada assim.

**Ao mexer.** Os dois `_point()` são cópias. Quem alterar um precisa olhar o
outro — e `map_service.py` e `atlas_map.dart` são as outras duas pontas do mesmo
contrato.

---

## 3. `occurred_at` é canonicamente um DIA em UTC, e se formata pelas partes UTC

**Onde.** Na entrada, `backend/app/schemas/_fields.py` normaliza todo datetime
para UTC-aware (`AwareUtcDatetime`) antes de persistir — as colunas são
`TIMESTAMPTZ`. Na saída, quem formata usa `.toUtc()` e monta a data pelas partes:
`app_flutter/lib/screens/timeline.dart` (que também agrupa por ano assim),
`memory_detail.dart`, `features/journeys/journey_domain.dart` (o período e a
data de cada parada, para a estante e para a jornada aberta), e
`memory_new.dart`, que inicializa o campo com `DateTime.now().toUtc()`.

**Por quê.** A data de uma lembrança é o dia em que ela aconteceu, não um
instante que muda de dia conforme o aparelho. Um datetime naive, sem a
normalização, seria reinterpretado no fuso da sessão do Postgres e corromperia
ordenação, cursor de paginação e agrupamento.

**Se errar.** `DateTime.parse(iso)` sem `.toUtc()` devolve hora local. Em
America/Fortaleza (UTC−3), uma memória de 01/05 às 00:00Z é exibida como 30/04 —
e na virada do ano a timeline a coloca no capítulo errado.

**Consequência para quem roda testes.** Os runners do CI são UTC e esta máquina
não é. Rode a suíte do app como
`TZ=UTC ~/development/flutter/bin/flutter test` para ver o mesmo resultado que o
CI vê.

---

## 4. O design system é `package:flutter/widgets`, não Material

**Onde.** `app_flutter/lib/design/tokens.dart`, `sj_theme.dart`,
`illustrations.dart` e todo o `design/components/` importam
`package:flutter/widgets.dart`. `design/gallery.dart` importa `material.dart`
com `show Icons` e **nada mais** — a linha é literalmente
`import 'package:flutter/material.dart' show Icons;`. A única outra concessão
dentro de `components/` é `sheet.dart`, com `show showModalBottomSheet`.

**Exceções declaradas.** `design/basemap.dart`, `design/theme.dart` e
`design/theme_controller.dart` usam Material por inteiro — são a ponte com o
`flutter_map` e com o `MaterialApp` que embrulha o app. Fora dessas três, um
import de Material em `design/` é um erro.

**Por quê.** O look é 100% dos tokens. Arrastar a decoração e o ink do Material
para dentro dos componentes desfaria exatamente o que o design system resolve —
e um widget Material exige um ancestral que a árvore da galeria não tem.

**Se errar.** `No Material widget found`, em tempo de execução, no momento em que
a árvore é desenhada. Já aconteceu: um `Slider` entrou na galeria e ela passou a
quebrar na abertura (commit `966b9e7`). O analisador aprova isso sem reclamar —
só um teste de widget que **monte** a árvore pega
(`app_flutter/test/design_gallery_test.dart`).

---

## 5. Em teste de widget, procure `EditableText` — nunca `TextField`

**Onde.** `app_flutter/lib/design/components/text_field.dart`: o `SJTextField`
envolve um `CupertinoTextField` (com `decoration: null`) e desenha a caixa por
fora. Uso real em `app_flutter/test/memory_music_test.dart`, onde o comentário já
registra o motivo.

**Por quê.** `EditableText` é o que existe por baixo de qualquer campo editável,
Material ou Cupertino. É o único finder que funciona para os dois.

**Se errar.** `find.byType(TextField)` acha zero widgets e o teste falha com
"Found 0 widgets", que lê como bug na tela e não como finder errado. Quando a
tela tem mais de um campo, use `.last` (ou um finder mais específico), como os
testes de música fazem.

---

## 6. `SJButton` renderiza o rótulo em CAIXA ALTA, menos na variante `text`

**Onde.** `app_flutter/lib/design/components/buttons.dart`:
`final text = isLink ? label : label.toUpperCase();`, onde `isLink` é
`variant == SJButtonVariant.text`. O mesmo vale para `components/badge.dart` e
`components/overline.dart`, que também sobem o texto.

**Se errar.** `find.text('Salvar')` não acha nada: o que está na tela é
`SALVAR`. O rótulo passado ao widget continua em caixa mista — a transformação é
só na renderização.

---

## 7. O contrato de listagem: array JSON puro + `X-Next-Cursor`

**Onde.** `backend/app/core/pagination.py` é a fonte única. As rotas que o
cumprem são `GET /memories` (`backend/app/api/routes/memory.py`) e
`GET /journeys` (`backend/app/api/routes/journey.py`); `backend/app/main.py`
expõe o header no CORS. Do lado do app, `app_flutter/lib/api.dart` (`_page`,
`Page`, `nextCursorHeader`).

**As regras, todas juntas:**

| Item | Valor |
| --- | --- |
| Corpo | array JSON **puro** — nada de envelope `{ "items": [...] }` |
| Continuação | só no header `X-Next-Cursor`; sem header, acabou |
| Cursor | opaco: base64url de `<iso8601>\|<uuid>` |
| `?limit` | default **30**, teto **100**, normalizado por `clamp_limit` |
| Cursor inválido | `CursorError` → **400**, nunca 500 |

**Por quê.** Keyset, e não offset: páginas profundas continuam O(limit) e não
pulam nem duplicam linhas quando algo é inserido entre duas requisições. O corpo
continua sendo um array porque os clientes já iteravam a lista direto.

**Se errar.** Tirar o `expose_headers` do CORS não gera erro: o navegador
simplesmente não entrega o header, e a lista para na primeira página de 30 sem
que ninguém perceba. Devolver um envelope em vez do array quebra o app inteiro
de uma vez.

**Estado real, para não prometer demais.** Só as duas coleções de topo paginam.
`GET /journeys/{id}/memories`, `GET /journeys/{id}/tracks` e `GET /life-phases`
devolvem a lista inteira, sem cursor — e o docstring de `pagination.py` já diz
exatamente isso.

---

## 8. `tests/conftest.py` é costurado à mão, e as duas costuras falham caladas

**Onde.** `backend/tests/conftest.py`.

**Primeira costura: a ordem dos imports.** `DATABASE_URL`, `JWT_SECRET_KEY` e
`APP_ENV` são escritos em `os.environ` **antes** de qualquer import de `app` —
é o que dá precedência sobre o `.env` no pydantic-settings e faz o engine nascer
apontando para `some_journey_test`. Por isso todos os imports seguintes carregam
`# noqa: E402`. Eles não estão fora de ordem por descuido; estão fora de ordem
porque precisam estar.

**Se errar.** Mover um import para o topo "para organizar" faz o engine do app
nascer apontando para o banco do `.env`: os testes passam a **gravar no banco de
desenvolvimento**, enquanto o `TRUNCATE` da suíte continua indo para o banco de
teste — o lixo fica e ninguém limpa. Não há aviso.

**Segunda costura: a lista de tabelas sai do metadata, não da mão de ninguém.**
`_tabelas_a_truncar` monta o `TRUNCATE` a partir de `Base.metadata.sorted_tables`,
e `_assert_schema_coberto` interrompe a suíte — com o nome da tabela na mensagem
— se o banco de teste e o metadata discordarem. Já foi uma lista escrita à mão
(`_TABLES`), que nomeava sete de nove tabelas e só não vazava linha por sorte.
A suíte também se recusa a derrubar tabelas num banco cujo nome não termine em
`_test`.

**Se errar.** Um model novo que não seja registrado em `app/models/__init__.py`
não entra no metadata: a tabela não é criada no banco de teste, e o erro aparece
como "relação não existe" no primeiro teste que a usa.

---

## 9. `auth_headers` é uma FÁBRICA, não um dicionário

**Onde.** `backend/tests/conftest.py`. Use `h = auth_headers()`.

**Por quê.** Cada chamada registra e loga um usuário **novo**. É assim que se
escreve o teste de ownership: dois `auth_headers()` são dois donos diferentes, e
o recurso de um tem de responder 404 para o outro.

**Se errar.** Passar a fixture direto como header dá `TypeError` na hora — esse
pelo menos é barulhento. O erro caro é o inverso: reaproveitar o mesmo `h` num
teste que precisava de dois usuários, e concluir que a regra de ownership
funciona quando ela nunca foi exercitada.

---

## 10. O README não leva acento; `docs/` leva

**Onde.** `README.md` — hoje o arquivo inteiro não tem **uma única letra
acentuada**; os caracteres não-ASCII dele são só travessões (—) e setas (→). Os
documentos de `docs/`, incluindo este, usam acentuação normal.

**Por quê.** É uma decisão antiga do arquivo, e manter é mais barato que
converter.

**Se errar.** Escrever "memória" no README enche o diff de mudanças que não são a
sua, e a próxima pessoa reverte sem saber qual era a intenção.

---

## 11. Português no comentário, inglês no identificador

Comentários, docstrings e nomes de teste são em **português com acento** e
explicam o **porquê**, não o quê — o quê já está no código logo abaixo.
Identificadores, nomes de arquivo e mensagens de commit são em **inglês**.

**Commits.** Conventional Commits, `tipo(escopo): mensagem no imperativo`, como o
README registra. Os tipos que de fato aparecem no histórico são `feat`, `fix`,
`docs`, `test`, `chore`, `security` e `infra`. **Não existe tipo `ci`**: o
workflow de integração contínua entrou como `infra(ci): ...` (commit `7a58d75`).
O corpo do commit é onde mora a explicação — vários dos porquês deste documento
foram recuperados de lá.

---

## 12. Não existe formatador automático neste repositório

**Onde (pela ausência).** O backend não tem `pyproject.toml`, nem configuração de
black ou flake8; o `backend/ruff.toml` liga só o que acusa DEFEITO (erro de
sintaxe, nome que não existe, import sem uso), e nenhuma regra de estilo.
`backend/requirements-dev.txt` traz `pytest`, `httpx`, `httpx2`, `pillow` (para os
testes de imagem) e `ruff`. O app tem `analysis_options.yaml` com `flutter_lints`,
e nada além disso. O `.github/workflows/ci.yml` roda o `ruff check`, a paridade
com os clientes, `pytest`, o ciclo de migrations com `alembic check`, `flutter
analyze --fatal-infos` e `flutter test` — **nenhum passo de formatação**.

**Se errar.** Um `dart format` reescreve a maior parte dos arquivos `.dart` do
app de uma vez. A mudança real desaparece dentro de um diff que ninguém
consegue revisar, e o histórico perde a capacidade de responder "quando isto
mudou?".

---

## 13. Regra de domínio mora fora do Flutter

**Onde.** `app_flutter/lib/features/atlas/atlas_domain.dart`,
`features/tracks/track_domain.dart`, `features/hero/light_domain.dart` e
`features/hero/scene_domain.dart` são Dart puro, sem um
`import 'package:flutter/...'` sequer — todos dizem isso na primeira linha do
docstring. O widget correspondente só desenha o que o módulo
calcula.

**Por quê.** Dá para testar sem renderizar, e dá para trocar o provedor de mapa
sem reescrever regra. Os testes de domínio do atlas e do percurso rodam em
milissegundos justamente por isso.

**Se errar.** Basta um `Color` ou um `BuildContext` cruzar a fronteira para o
módulo deixar de ser testável sozinho — e a regra volta a só existir dentro de
uma tela.

---

## 14. A versão do Flutter está presa de propósito

**Onde.** `.github/workflows/ci.yml` fixa `flutter-version: '3.38.10'`;
`app_flutter/pubspec.yaml` pede `sdk: ^3.10.9`.

**Por quê.** O Dart subiu o mínimo de macOS para 14 a partir do 3.11. Um CI em
versão maior aprovaria código que não roda na máquina de quem escreve.

**Se errar.** O verde do CI deixa de significar "funciona aqui".

---

## 15. Regras que já moram em outro documento

Não estão repetidas aqui porque o lugar delas é onde a decisão foi tomada — mas
são da mesma família e mordem do mesmo jeito:

- **Revision id do Alembic com no máximo 32 caracteres** —
  `alembic_version.version_num` é `varchar(32)` e isso já quebrou uma vez. Ver
  [`10-localizacao.md`](10-localizacao.md), critério 4.
- **Ownership e 404 uniforme; `deleted_at IS NULL` em toda consulta** — nenhuma
  rota confia em `user_id` vindo do cliente. Ver
  [`04-decisoes-tecnicas.md`](04-decisoes-tecnicas.md).
- **Nenhum valor de cor, espaçamento ou tipografia escrito solto numa tela** —
  tudo vem de `app_flutter/lib/design/tokens.dart`. Ver
  [`08-design-system.md`](08-design-system.md).
- **Um cliente só** — `app_flutter/`, que atende celular e web pelo mesmo
  código. O app Expo que vivia em `mobile/` foi removido em outubro de 2026.
  Ver o README.

---

## Como manter esta lista

Uma convenção entra aqui quando satisfaz os três critérios que todas as de cima
satisfazem: **o analisador e a suíte não a veem**, **errar não produz erro** e
**alguém já errou**. Palpite de estilo não entra — vira ruído e esvazia o resto.

Quando uma delas for finalmente coberta por teste ou por lint, o item não some:
ganha a linha dizendo quem passou a vigiá-la. É a diferença entre uma regra que
alguém precisa lembrar e uma regra que a máquina cobra.
