# Some Journey

[![CI](https://github.com/JuanRiber/some-journey/actions/workflows/ci.yml/badge.svg)](https://github.com/JuanRiber/some-journey/actions/workflows/ci.yml)

Uma plataforma de cartografia humana: transforma deslocamentos, memorias e conexoes em jornadas visuais vivas.

A vida deixa rastros. O Some Journey registra esses rastros e une lugar, tempo, atmosfera, pessoas, musica, memoria e narrativa em uma experiencia visual baseada em mapa.

**E:** um atlas pessoal, um sistema de memoria, uma forma de preservar jornadas reais.
**Nao e:** rede social, app de viagem comum, diario simples, feed de likes.

---

## Stack

| Camada | Tecnologias |
| --- | --- |
| Backend | Python 3.12, FastAPI, SQLAlchemy, Pydantic, JWT |
| Banco | PostgreSQL 16 + PostGIS 3.4 |
| App principal | Flutter (Dart >= 3.12.2), `flutter_map` |
| App web | React Native, Expo, Expo Router, TypeScript |
| Mapa | `flutter_map` com tiles OSM/CartoDB; Mapbox planejado |
| Imagens | Supabase Storage (bucket privado, URL assinada) |
| Infra | Docker Compose para PostgreSQL/PostGIS; Render para a API |
| E2E | Playwright sobre o app web (Expo) |

Ha **dois clientes** no repo. O Flutter (`app_flutter/`) e onde a evolucao acontece:
so ele tem Perfil, Configuracoes, avatar e o atlas consumindo `GET /map`. O Expo
(`mobile/`) mantem auth, memorias e jornadas, e e o alvo dos testes E2E.

Decisoes tecnicas atuais: SQLAlchemy sincrono, UUID nativo do PostgreSQL, schema
versionado por Alembic (o `create_all` no startup foi removido), imagens fora do
banco, lugar da memoria resolvido por geocoding reverso na escrita, secrets por
variaveis de ambiente.

---

## Estrutura

```text
some-journey/
|-- backend/
|   |-- app/
|   |   |-- main.py
|   |   |-- api/routes/        # auth, memories, journeys, tracks, map, profile
|   |   |-- core/              # config, security, rate limit, storage, geohash, email
|   |   |-- db/                # engine, session, Base
|   |   |-- dependencies/      # autenticacao atual
|   |   |-- models/            # User, Memory, Journey, tracks, imagens, tokens
|   |   |-- repositories/      # acesso a dados
|   |   |-- schemas/           # contratos Pydantic
|   |   `-- services/          # regras de negocio (inclui geocoding)
|   |-- alembic/               # migrations versionadas (0001..0010)
|   |-- scripts/               # seed_users, reset_password, backfill_geocoding, start.sh
|   |-- tests/                 # pytest (214 testes)
|   |-- Dockerfile
|   |-- requirements.txt
|   `-- requirements-dev.txt
|-- app_flutter/               # app principal (Flutter)
|   |-- lib/
|   |   |-- api.dart           # cliente HTTP da API
|   |   |-- design/            # tokens do design system
|   |   |-- features/          # atlas, profile, music
|   |   |-- screens/           # telas
|   |   `-- widgets/           # UI compartilhada (atlas_map, location_picker)
|   `-- test/
|-- mobile/                    # app web/Expo
|   |-- src/app/               # rotas Expo Router
|   |-- src/components/
|   |-- src/lib/               # API, auth, geo, config
|   |-- src/theme/
|   `-- package.json
|-- .github/workflows/ci.yml   # integracao continua (backend + app)
|-- docs/                      # visao, regras, modelagem, API, design system, perfil
|-- e2e/                       # smoke Playwright do app web
|-- infra/
|   `-- docker-compose.yml
|-- playwright.config.ts
|-- render.yaml                # blueprint de deploy da API
|-- .env.example
`-- README.md
```

---

## Pre-requisitos

- Python 3.11+ (producao roda 3.12; o codigo usa sintaxe 3.10+)
- Docker + Docker Compose (para o PostgreSQL/PostGIS)
- Flutter SDK com Dart >= 3.12.2 (para o app principal)
- Node.js 20+ (apenas para o app Expo e para o E2E)
- Git

---

## Setup local

### 1. Banco

Na raiz do repositorio:

```bash
docker compose -f infra/docker-compose.yml up -d
```

O PostgreSQL/PostGIS fica exposto em `localhost:5433`.

> **Alternativa sem Docker (macOS):** o Postgres.app com PostgreSQL 16 ja embarca
> PostGIS 3.4 e nao exige privilegio de administrador. Crie o cluster com
> `initdb -U somejourney --pwfile=...`, acrescente `port = 5433` ao
> `postgresql.conf` e rode `CREATE EXTENSION postgis` nos bancos `some_journey` e
> `some_journey_test`. As credenciais sao as mesmas do `docker-compose.yml`.

### 2. Backend

```bash
cd backend
python -m venv .venv
```

Ativar o ambiente:

- Windows PowerShell: `.\.venv\Scripts\Activate.ps1`
- Git Bash, Linux ou macOS: `source .venv/Scripts/activate` ou `source .venv/bin/activate`

Instalar dependencias:

```bash
pip install -r requirements.txt
```

Criar o `.env` do backend:

```bash
cp ../.env.example .env
```

Gere um `JWT_SECRET_KEY` forte (a config recusa segredos com menos de 32 bytes):

```bash
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

Aplicar as migrations (o schema e gerido por Alembic, nao pelo startup):

```bash
alembic upgrade head
```

> Se voce ja tinha um banco criado pela versao antiga (que criava tabelas no
> startup), rode `alembic stamp 0001_baseline` uma unica vez antes do
> `upgrade head` para registrar a baseline sem recriar o que ja existe.

Rodar a API:

```bash
uvicorn app.main:app --reload
```

Endpoints uteis:

- Health check: <http://127.0.0.1:8000/health>
- Readiness (checa o banco): <http://127.0.0.1:8000/health/ready>
- Swagger: <http://127.0.0.1:8000/docs>

> Em `APP_ENV=production` o `/docs`, o `/redoc` e o `/openapi.json` ficam
> desligados e o cadastro publico fecha por padrao (contas via `scripts/seed_users`).

Rodar os testes (usa um banco dedicado `some_journey_test`, criado se faltar):

```bash
pip install -r requirements-dev.txt
pytest
```

### 3. App Flutter (principal)

```bash
cd app_flutter
flutter pub get
flutter run
```

A URL da API vem de `String.fromEnvironment('API_URL')`, com
`http://127.0.0.1:8000` como padrao. Para apontar para outro host:

```bash
flutter run --dart-define=API_URL=http://10.0.2.2:8000
```

Verificacoes:

```bash
flutter analyze
flutter test
```

### 4. App Expo (web)

```bash
cd mobile
npm install
npm run web
```

Por padrao, o app usa:

- Android emulator: `http://10.0.2.2:8000`
- Web, iOS e outros: `http://127.0.0.1:8000`

Para apontar para outra API, ajuste `expo.extra.apiUrl` em `mobile/app.json`.

### 5. E2E (Playwright)

Na raiz do repositorio:

```bash
npm install
npm run e2e:install
npm run test:e2e
```

O Playwright sobe o app web sozinho. Os fluxos que batem na API precisam do
backend e do banco no ar.

---

## API atual

O contrato completo e navegavel em `/docs` com a API rodando. Rotas privadas
exigem `Authorization: Bearer <token>`.

### Auth

- `POST /auth/register` — cadastro (fechado por padrao em producao)
- `POST /auth/login`
- `GET /auth/me`
- `POST /auth/change-password` — troca a senha e invalida os tokens antigos
- `POST /auth/forgot-password` — dispara o token de reset (por e-mail, se houver SMTP)
- `POST /auth/reset-password` — redefine a senha com o token

### Memories

Todas as rotas exigem Bearer token.

- `POST /memories`
- `GET /memories` — paginacao keyset (`?limit=&cursor=`)
- `GET /memories/{memory_id}`
- `PATCH /memories/{memory_id}`
- `DELETE /memories/{memory_id}`
- `POST /memories/{memory_id}/images` — upload `multipart/form-data`, ate **5 fotos** por memoria
- `DELETE /memories/{memory_id}/images/{image_id}`
- `POST /memories/{memory_id}/music` — anexa a cancao que estava tocando (ate **5** por memoria)
- `DELETE /memories/{memory_id}/music/{music_id}`

Sem Supabase configurado, o upload responde **503** e a `image_url` volta nula.

As listagens paginadas devolvem um **array JSON puro**; o cursor da proxima pagina
vem no header `X-Next-Cursor` (sem o header, acabou). `limit` tem default 30 e teto 100.

Toda memoria guarda o **lugar** onde aconteceu (cidade, estado, pais,
`country_code`, continente, geohash), resolvido por geocoding reverso **depois**
da escrita — registrar a memoria nunca depende do provedor. Memorias com
`geocoded_at` nulo sao a fila do `python -m scripts.backfill_geocoding`.

### Journeys

Todas as rotas exigem Bearer token. Ciclo de vida do `status`:
`draft -> active <-> paused -> finished` (`finished` e terminal; so uma jornada
`active` por usuario de cada vez — pausar libera o slot).

- `POST /journeys` — cria (nasce `draft`; aceita `mood` e `is_private`)
- `GET /journeys` — lista as do usuario, paginacao keyset (`?limit=&cursor=`)
- `GET /journeys/{journey_id}` — detalhe com pontos ordenados + `route` (LineString; `null` se < 2 pontos)
- `PATCH /journeys/{journey_id}` — edita titulo, descricao, `mood`, `is_private`, datas
- `DELETE /journeys/{journey_id}` — soft delete da jornada
- `POST /journeys/{journey_id}/cover` — define a capa da jornada
- `DELETE /journeys/{journey_id}/cover` — remove a capa
- `POST /journeys/{journey_id}/start` — `draft -> active`
- `POST /journeys/{journey_id}/pause` — `active -> paused`
- `POST /journeys/{journey_id}/resume` — `paused -> active`
- `POST /journeys/{journey_id}/finish` — `active|paused -> finished`
- `GET /journeys/{journey_id}/memories` — lista as memorias da jornada
- `POST /journeys/{journey_id}/memories` — cria uma memoria ja vinculada
- `POST /journeys/{journey_id}/points` — vincula uma memoria existente (um ponto em uma jornada so)
- `PATCH /journeys/{journey_id}/points/reorder` — reordena os pontos
- `DELETE /journeys/{journey_id}/points/{memory_id}` — desvincula sem apagar a memoria

Transicao invalida ou segunda jornada ativa retornam **409**.

### Percurso real (GPS)

Cada jornada pode ter um **percurso real** (rastro GPS), distinto da linha
**simbolica** que liga as memorias na ordem. Bearer token; tudo filtrado por dono
(dado de localizacao nunca vaza entre usuarios).

- `POST /journeys/{journey_id}/tracks/start` — abre um trecho de gravacao (409 se ja houver um aberto)
- `POST /journeys/{journey_id}/tracks/{track_id}/points` — envia pontos GPS em lote (ate 1000/lote)
- `POST /journeys/{journey_id}/tracks/{track_id}/finish` — finaliza o trecho
- `GET /journeys/{journey_id}/tracks` — lista os trechos (com contagem + distancia)
- `DELETE /journeys/{journey_id}/tracks/{track_id}` — remove o percurso (nao apaga as memorias)
- `GET /journeys/{journey_id}/map` — GeoJSON da jornada: percurso real (`tracks`) + memorias + `symbolic_route`

Pausar/retomar gera varios trechos; a visualizacao une todos como uma experiencia.

### Map

Mapa principal (global) do usuario (pins soltos + jornadas com rastro). Bearer token.
Visao macro: mostra so a linha **simbolica** — nao expoe pontos de GPS brutos.

- `GET /map` — tudo do usuario: `loose_points` (memorias sem jornada) + `journeys` (pontos + `route`)
- `GET /map?bbox=min_lng,min_lat,max_lng,max_lat` — recorta pela viewport (mundo/pais/regiao/cidade)
- `GET /map?journey_id={id}` — foca uma jornada especifica

### Perfil

Identidade do viajante. Um unico endpoint agregado, com as contagens feitas em
SQL — o cliente nunca baixa memorias para conta-las. Bearer token.

- `GET /me/profile` — identidade, estatisticas, passaporte, jornada atual e atividade
- `PATCH /me/profile` — edita nome, `@username` e bio
- `POST /me/avatar` — envia o avatar (Supabase Storage)
- `DELETE /me/avatar` — remove o avatar

---

## Status atual

- [x] Estrutura backend + Docker/PostGIS
- [x] Health check e readiness com checagem de banco
- [x] Configuracao por variaveis de ambiente
- [x] Autenticacao com cadastro, login, JWT e `/auth/me`
- [x] Rate limit simples para auth (por conta e por IP)
- [x] CRUD de memorias com ownership por usuario
- [x] Jornadas com ciclo de vida (draft/active/paused/finished), pontos, reordenacao e desvinculo
- [x] Edicao de jornada (`PATCH`), capa, `mood` e `is_private`
- [x] Endpoint de mapa (`/map`) com pins soltos, jornadas com rastro e filtros por bbox/jornada
- [x] Percurso real por GPS (tracks + pontos) e mapa da jornada em GeoJSON; captura em primeiro plano no app
- [x] Upload/storage de imagens — ate 5 fotos por memoria no Supabase Storage, com URL assinada
- [x] Recuperacao real de senha (token com validade, envio por SMTP opcional) e troca de senha
- [x] Lugar da memoria persistido por geocoding reverso + script de backfill
- [x] Fuso horario (`timezone`) resolvido offline pelas coordenadas, sem chamada de rede extra
- [x] Perfil agregado (`GET /me/profile`) com passaporte, `@username`, avatar e bio
- [x] Paginacao keyset em `/memories` e `/journeys`
- [x] Migracoes versionadas (Alembic, 0001..0010)
- [x] Musica da memoria de ponta a ponta — busca no iTunes, ate 5 faixas por memoria e contagem no Perfil
- [x] Testes automatizados — 235 no backend (pytest) e 110 no app (flutter test)
- [x] Integracao continua no GitHub Actions (testes, analyze e migrations)
- [x] Mapa interativo do atlas no app Flutter, consumindo `/map`
- [ ] Paridade do app Expo com o Flutter (falta Perfil e Configuracoes)
- [ ] Tracking em segundo plano (exige dev build)
- [ ] Mapa Mapbox ou provedor nativo

---

## Integracao continua

O GitHub Actions roda a cada push na `main` e em todo pull request
(`.github/workflows/ci.yml`), em dois trabalhos paralelos:

- **Backend** — `pytest` contra um servico `postgis/postgis:16-3.4` na porta
  5433, a mesma imagem e a mesma porta do `infra/docker-compose.yml`. Depois,
  `alembic upgrade head`, `downgrade base` e `upgrade head` num banco limpo, que
  e o unico jeito de pegar uma migration quebrada antes do deploy (o boot em
  producao roda `upgrade head`).
- **App Flutter** — `flutter analyze --fatal-infos` e `flutter test`, na versao
  3.38.10 (Dart 3.10.9), a mesma do desenvolvimento.

A suite nao precisa de `.env`: o `conftest.py` define `DATABASE_URL`,
`JWT_SECRET_KEY` e `APP_ENV=test` antes de importar o app, cria o banco de teste
e habilita o PostGIS.

O E2E (Playwright) **nao** entra no CI: ele sobe o app Expo, que e o cliente
secundario, e depende do backend no ar — custo e instabilidade altos para o que
cobre.

---

## Divergencias conhecidas

Pontos em que codigo e documentacao (ou intencao de produto) ainda nao batem.
Registrados aqui de proposito — a alternativa e descobri-los de novo daqui a
seis meses.

| Divergencia | Situacao |
| --- | --- |
| Titulo da memoria e obrigatorio; texto e opcional | O produto pede o contrario: o texto e o nucleo da memoria e o titulo deveria ser opcional. Hoje `MemoryCreate` exige `title` e aceita `text` vazio. Ver `01-regras-negocio.md`. |
| Uma memoria por jornada | Limite do MVP, garantido por indice unico parcial em `journey_memories.memory_id`. A modelagem ja suporta varias jornadas — basta trocar a constraint. |
| `memories.image_path` | Coluna legada da epoca de uma foto so; as fotos atuais vivem em `memory_images`. |
| Mapa em Mapbox | Planejado. Hoje o Flutter usa `flutter_map` com tiles OSM/CartoDB e o backend entrega pins e rastros independente do provedor visual. |

---

## Seguranca

- Senhas sempre como hash; `password_hash` nunca retorna pela API.
- Trocar a senha invalida os tokens emitidos antes (`password_changed_at`).
- Tokens de reset de senha ficam no banco como hash, com validade e uso unico.
- Secrets (`JWT_SECRET_KEY`, credenciais de banco, service key do Supabase) ficam em variaveis de ambiente.
- UUID nativo do PostgreSQL evita IDs sequenciais previsiveis.
- Cada usuario acessa somente os proprios dados.
- IDs inexistentes e IDs de outro usuario retornam o mesmo 404 nas rotas protegidas.
- Bucket de imagens privado: a API devolve URL assinada e temporaria.
- Middleware rejeita corpos acima de `MAX_JSON_BODY_BYTES` com 413.
- Senhas, tokens e dados sensiveis nao devem ir para logs.

---

## Convencao de commits

Use Conventional Commits: `tipo(escopo): mensagem no imperativo`.

Tipos sugeridos: `feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `style`, `infra`, `security`.

Exemplos:

- `feat(auth): add user model`
- `chore(deps): pin dependency versions`
- `docs(readme): update local setup guide`
