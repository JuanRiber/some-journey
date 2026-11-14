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
| App | Flutter (Dart >= 3.12.2), `flutter_map` — movel e web |
| Mapa | `flutter_map` com tiles OSM/CartoDB; Mapbox planejado |
| Imagens | Supabase Storage (bucket privado, URL assinada) |
| Infra | Docker Compose para PostgreSQL/PostGIS; Render para a API; Cloudflare Pages para o app web |

Ha **um cliente**: o Flutter (`app_flutter/`), que atende movel e web pelo mesmo
codigo. Ate outubro de 2026 existia tambem um app Expo em `mobile/`, removido por
nao ter nenhuma tela que o Flutter ja nao tivesse e por cobrar trabalho dobrado a
cada mudanca de contrato da API.

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
|   |-- tests/                 # pytest (387 testes)
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
|-- .github/workflows/
|   |-- ci.yml                 # integracao continua (backend + app)
|   `-- deploy-web.yml         # publica o app web no Cloudflare Pages
|-- docs/                      # visao, regras, modelagem, API, design system, perfil, deploy
|-- infra/
|   `-- docker-compose.yml
|-- render.yaml                # blueprint de deploy da API
|-- .env.example
`-- README.md
```

---

## Pre-requisitos

- Python 3.11+ (producao roda 3.12; o codigo usa sintaxe 3.10+)
- Docker + Docker Compose (para o PostgreSQL/PostGIS)
- Flutter SDK com Dart >= 3.12.2 (para o app principal)
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

#### Fotos (Supabase Storage)

Sem estas duas chaves o upload de imagem responde **503** e o app diz, na tela,
que as fotos estao indisponiveis. Todo o resto funciona. Para ligar:

1. Crie um projeto em <https://supabase.com> (o plano gratuito atende).
2. Em **Storage → New bucket**, crie um bucket chamado `memories` e deixe-o
   **privado** (nao marque Public). O backend gera URLs assinadas de curta
   duracao; bucket publico exporia a foto de todo mundo por URL adivinhavel.
3. Em **Project Settings → API**, copie:
   - **Project URL** (`https://<ref>.supabase.co`) para `SUPABASE_URL`;
   - a chave **service_role** para `SUPABASE_SERVICE_KEY`.
4. Reinicie a API.

A chave `service_role` ignora as policies do Supabase e **nunca** pode ir para
o cliente: ela vive so no `.env` do backend ou no cofre de segredos do host. O
isolamento entre usuarios e feito pelo caminho do objeto
(`{user_id}/{memory_id}/{uuid}.{ext}`), imposto no servidor — e por isso que o
bucket precisa ser privado.

Para conferir que ligou: anexar uma foto a uma memoria deve responder **201**
em vez de 503.

#### Entrar com o Google

Sem `GOOGLE_CLIENT_ID` a rota `POST /auth/google` responde **503** e o botao no
app fica desligado, com "em breve" escrito. Todo o resto funciona. Para ligar:

1. No <https://console.cloud.google.com>, crie um projeto.
2. **APIs e servicos → Tela de permissao OAuth**: configure o consentimento
   (tipo Externo, nome do app e e-mail de contato).
3. **Credenciais → Criar credenciais → ID do cliente OAuth**. Crie um por
   plataforma que for usar: *Aplicativo da Web* (informando a origem
   autorizada), *Android* (com o nome do pacote e a impressao digital SHA-1 da
   chave de assinatura) e *iOS* (com o bundle id).
4. Coloque os client ids em `GOOGLE_CLIENT_ID`, **separados por virgula**. O
   `aud` de cada id_token e o client id da plataforma que pediu — com um valor
   so, o login da web funciona e o do celular e recusado como token invalido.
5. Reinicie a API.

No APP o mesmo client id entra por `--dart-define`, igual ao `API_URL`:

```bash
flutter run --dart-define=GOOGLE_CLIENT_ID=<o-client-id-da-plataforma>
```

Sem ele o botao fica desenhado e DESLIGADO, com "em breve" escrito — e isso e
proposital: um botao ligado sem credencial seria um botao que nao faz nada.
Use o client id da plataforma que esta construindo (o da Web para `-d chrome`,
o de Android para Android, o de iOS para iOS); no backend va todos, separados
por virgula.

Na web o botao e o renderizado pelo PROPRIO Google, nao um nosso: o Google nao
autoriza o fluxo a sair de um botao de terceiro, e a resposta chega por evento
em vez de pelo retorno da chamada. Fora da web o fluxo e direto e o botao e o
nosso, no design system.

O backend nao guarda segredo do Google: so o client id, que e publico por
natureza. Nao ha `client_secret` aqui porque o fluxo e de id_token — quem fala
com o Google e o cliente; o backend apenas **verifica a assinatura** do token
contra as chaves publicas do Google e confere `aud`, `iss`, `exp` e
`email_verified`.

Vinculo de conta: o primeiro login cria o cadastro; se o e-mail ja existir, a
conta Google e **vinculada a ela** em vez de criar uma segunda. O vinculo e
pelo `sub` do Google, nunca pelo e-mail, porque o e-mail de uma conta Google
pode mudar.

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

Build para a web:

```bash
flutter build web --no-web-resources-cdn
```

O `--no-web-resources-cdn` **nao e opcional**. Sem ele o Flutter copia o
CanvasKit para dentro do build e mesmo assim o busca em `www.gstatic.com` a
cada carga da pagina. Medido neste projeto, no mesmo navegador e no mesmo
recurso: `canvaskit.wasm` passou de **3.088ms para 232ms**, e o `load` da
pagina, de **3.136ms para 144ms**. Com o flag o app tambem abre sem internet.

Nao use `--no-tree-shake-icons`: sem ele as fontes de icone caem de 1,9MB para
13KB, e o build so passa quando todo `IconData` e const — ou seja, ele proprio
verifica que nenhum icone some.

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

- `POST /memories` — aceita `life_phase_id` opcional (uma fase ativa do proprio usuario)
- `GET /memories` — paginacao keyset (`?limit=&cursor=`); `?life_phase_id=` recorta pela fase
- `GET /memories/{memory_id}`
- `PATCH /memories/{memory_id}` — em `life_phase_id`, e so nele, `null` solta a memoria da fase
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

- `POST /journeys` — cria (nasce `draft`; aceita `mood`, `is_private` e `life_phase_id`)
- `GET /journeys` — lista as do usuario, paginacao keyset (`?limit=&cursor=`); `?life_phase_id=` recorta pela fase
- `GET /journeys/{journey_id}` — detalhe com pontos ordenados + `route` (LineString; `null` se < 2 pontos)
- `PATCH /journeys/{journey_id}` — edita titulo, descricao, `mood`, `is_private`, datas e `life_phase_id` (`null` solta da fase)
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
- `GET /map?life_phase_id={id}` — a lente de uma fase da vida (regra abaixo)

### Fases da vida

Os capitulos que a pessoa reconhece na propria historia. Nao ha lista
predefinida, so o nome e obrigatorio, o periodo pode ficar aberto dos dois lados
e fases podem se sobrepor. Bearer token; fase de outra pessoa responde igual a
inexistente.

- `GET /life-phases` — as fases do usuario, na ordem em que a vida aconteceu
- `POST /life-phases` — cria (`name`, e opcionalmente `description`, `color`, `started_at`, `ended_at`)
- `GET /life-phases/{phase_id}`
- `PATCH /life-phases/{phase_id}` — parcial, e aqui `null` LIMPA (para reabrir uma fase encerrada)
- `DELETE /life-phases/{phase_id}` — apaga a fase e solta o que apontava para ela; nenhuma memoria se perde

`color` e um papel da paleta (`primary`, `secondary`, `accent`, `moss`,
`highlight`), nunca um hexadecimal: cor livre quebraria o contraste num dos dois
modos do app.

A **lente** (`?life_phase_id=` em `/memories`, `/journeys` e `/map`): a memoria
esta na fase quando foi marcada nela **ou** quando esta numa jornada marcada
nela; a jornada esta na fase quando foi marcada nela ou quando alguma memoria
dela foi, e no mapa vem inteira, com o rastro. A fase nao e deduzida das datas.
Fase alheia ou apagada no filtro responde **404**; no corpo de um POST/PATCH de
memoria ou jornada, **422**.

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
- [x] Rate limit simples para auth (por conta, por IP e por e-mail)
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
- [x] Fases da vida de ponta a ponta — criar e editar no app, marcar memorias e jornadas, e reler a timeline e o atlas por fase
- [x] Testes automatizados — 387 no backend (pytest) e 453 no app (flutter test)
- [x] Integracao continua no GitHub Actions (testes, analyze e migrations)
- [x] Mapa interativo do atlas no app Flutter, consumindo `/map`
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

---

## Deploy para testers

Tudo no plano gratuito: API no **Render** (`render.yaml`), banco e fotos no
**Supabase**, app web no **Cloudflare Pages** (`.github/workflows/deploy-web.yml`)
e um ping no **UptimeRobot** para a API nao dormir. Um push na `main` so e
publicado depois do CI verde, nos dois lados. O passo a passo, na ordem, esta em
[`docs/12-deploy.md`](docs/12-deploy.md).

---

## Divergencias conhecidas

Pontos em que codigo e documentacao (ou intencao de produto) ainda nao batem.
Registrados aqui de proposito — a alternativa e descobri-los de novo daqui a
seis meses.

| Divergencia | Situacao |
| --- | --- |
| Texto da memoria e opcional | O produto pede que o texto seja o nucleo da memoria. O titulo ja deixou de ser obrigatorio; exigir o texto quebraria os dois clientes e o acervo ja gravado, entao segue em aberto. Ver `01-regras-negocio.md`. |
| Uma memoria por jornada | Limite do MVP, garantido por indice unico parcial em `journey_memories.memory_id`. A modelagem ja suporta varias jornadas — basta trocar a constraint. |
| Mapa em Mapbox | Planejado. Hoje o Flutter usa `flutter_map` com tiles OSM/CartoDB e o backend entrega pins e rastros independente do provedor visual. |

---

## Seguranca

- Senhas sempre como hash; `password_hash` nunca retorna pela API.
- Trocar a senha invalida os tokens emitidos antes (`password_changed_at`), inclusive quando a troca cai no mesmo segundo da senha anterior.
- Tokens de reset de senha ficam no banco como hash, com validade e uso unico.
- Secrets (`JWT_SECRET_KEY`, credenciais de banco, service key do Supabase) ficam em variaveis de ambiente.
- UUID nativo do PostgreSQL evita IDs sequenciais previsiveis.
- Cada usuario acessa somente os proprios dados.
- IDs inexistentes e IDs de outro usuario retornam o mesmo 404 nas rotas protegidas.
- Bucket de imagens privado: a API devolve URL assinada e temporaria.
- Middleware rejeita corpos acima de `MAX_JSON_BODY_BYTES` com 413 (uploads de foto, capa e avatar tem o teto de imagem).
- Login e recuperacao de senha tem um teto por e-mail (`AUTH_RATE_LIMIT_EMAIL_ATTEMPTS`), que nao depende de IP: um `X-Forwarded-For` forjado nao o contorna.
- STARTTLS do SMTP confere o certificado e o nome do servidor.
- Um e-mail ja ligado a uma conta Google nao e religado a outra (`409`): e-mail de dominio que troca de dono nao herda as memorias de ninguem.
- Senhas, tokens e dados sensiveis nao devem ir para logs.
- Entrada que o banco nao guarda (caractere NUL no texto) ou que nao cabe em JSON (`NaN`, `Infinity`) responde 422, nunca 500.
- Datas de entrada ficam entre os anos 1000 e 2999: fora disso, a leitura de volta quebrava a conta inteira.

---

## Convencao de commits

Use Conventional Commits: `tipo(escopo): mensagem no imperativo`.

Tipos sugeridos: `feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `style`, `infra`, `security`.

Exemplos:

- `feat(auth): add user model`
- `chore(deps): pin dependency versions`
- `docs(readme): update local setup guide`
