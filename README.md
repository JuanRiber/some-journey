# Some Journey

Uma plataforma de cartografia humana: transforma deslocamentos, memorias e conexoes em jornadas visuais vivas.

A vida deixa rastros. O Some Journey registra esses rastros e une lugar, tempo, atmosfera, pessoas, musica, memoria e narrativa em uma experiencia visual baseada em mapa.

**E:** um atlas pessoal, um sistema de memoria, uma forma de preservar jornadas reais.
**Nao e:** rede social, app de viagem comum, diario simples, feed de likes.

---

## Stack

| Camada | Tecnologias |
| --- | --- |
| Backend | Python, FastAPI, SQLAlchemy, Pydantic, JWT |
| Banco | PostgreSQL + PostGIS |
| Mobile | React Native, Expo, Expo Router, TypeScript |
| Mapa | Leaflet no web picker; Mapbox planejado para o atlas principal |
| Infra | Docker Compose para PostgreSQL/PostGIS |

Decisoes tecnicas atuais: SQLAlchemy sincrono, UUID nativo do PostgreSQL, tabelas criadas no startup no MVP, imagens fora do banco, secrets por variaveis de ambiente.

---

## Estrutura

```text
some-journey/
|-- backend/
|   |-- app/
|   |   |-- main.py
|   |   |-- api/routes/        # auth, memories, journeys
|   |   |-- core/              # config, security, rate limit
|   |   |-- db/                # engine, session, Base
|   |   |-- dependencies/      # autenticacao atual
|   |   |-- models/            # User, Memory, Journey
|   |   |-- repositories/      # acesso a dados
|   |   |-- schemas/           # contratos Pydantic
|   |   `-- services/          # regras de negocio
|   `-- requirements.txt
|-- mobile/
|   |-- src/app/               # rotas Expo Router
|   |-- src/components/
|   |-- src/lib/               # API, auth, geo, config
|   |-- src/theme/
|   `-- package.json
|-- infra/
|   `-- docker-compose.yml
|-- .env.example
`-- README.md
```

---

## Pre-requisitos

- Python 3.11+
- Node.js 20+
- Docker + Docker Compose
- Git

---

## Setup local

### 1. Banco

Na raiz do repositorio:

```bash
docker compose -f infra/docker-compose.yml up -d
```

O PostgreSQL/PostGIS fica exposto em `localhost:5433`.

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

Rodar a API:

```bash
uvicorn app.main:app --reload
```

Endpoints uteis:

- Health check: <http://127.0.0.1:8000/health>
- Swagger: <http://127.0.0.1:8000/docs>

### 3. Mobile

```bash
cd mobile
npm install
npm run web
```

Por padrao, o app usa:

- Android emulator: `http://10.0.2.2:8000`
- Web, iOS e outros: `http://127.0.0.1:8000`

Para apontar para outra API, ajuste `expo.extra.apiUrl` em `mobile/app.json`.

---

## API atual

### Auth

- `POST /auth/register`
- `POST /auth/login`
- `GET /auth/me`

### Memories

Todas as rotas exigem Bearer token.

- `POST /memories`
- `GET /memories`
- `GET /memories/{memory_id}`
- `PATCH /memories/{memory_id}`
- `DELETE /memories/{memory_id}`

### Journeys

Todas as rotas exigem Bearer token.

- `POST /journeys`
- `GET /journeys`
- `GET /journeys/{journey_id}`
- `POST /journeys/{journey_id}/start`
- `POST /journeys/{journey_id}/finish`
- `POST /journeys/{journey_id}/points`
- `POST /journeys/{journey_id}/memories`
- `PATCH /journeys/{journey_id}/points/reorder`
- `DELETE /journeys/{journey_id}`

---

## Status atual

- [x] Estrutura backend + Docker/PostGIS
- [x] Health check
- [x] Configuracao por variaveis de ambiente
- [x] Autenticacao com cadastro, login, JWT e `/auth/me`
- [x] Rate limit simples para auth
- [x] CRUD de memorias com ownership por usuario
- [x] Jornadas com inicio, fim, pontos e reordenacao
- [x] App Expo com login, cadastro, atlas inicial, timeline, detalhe e criacao de memoria
- [ ] Testes automatizados
- [ ] Migracoes versionadas
- [ ] Mapa interativo principal do atlas
- [ ] Upload/storage de imagens
- [ ] Recuperacao real de senha

---

## Seguranca

- Senhas sempre como hash; `password_hash` nunca retorna pela API.
- Secrets (`JWT_SECRET_KEY`, credenciais de banco) ficam em variaveis de ambiente.
- UUID nativo do PostgreSQL evita IDs sequenciais previsiveis.
- Cada usuario acessa somente os proprios dados.
- IDs inexistentes e IDs de outro usuario retornam o mesmo 404 nas rotas protegidas.
- Senhas, tokens e dados sensiveis nao devem ir para logs.

---

## Convencao de commits

Use Conventional Commits: `tipo(escopo): mensagem no imperativo`.

Tipos sugeridos: `feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `style`, `infra`, `security`.

Exemplos:

- `feat(auth): add user model`
- `chore(deps): pin dependency versions`
- `docs(readme): update local setup guide`
