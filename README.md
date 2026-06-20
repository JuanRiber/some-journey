# Some Journey

> Uma plataforma de **cartografia humana** — transforma deslocamentos, memórias e conexões em **jornadas visuais vivas**.

A vida deixa rastros. O Some Journey registra esses rastros e une **lugar, tempo, atmosfera, pessoas, música, memória e narrativa** numa experiência visual coerente, baseada em mapa.

**É:** um atlas pessoal, um sistema de memória, uma forma de preservar jornadas reais.
**Não é:** rede social, app de viagem comum, diário simples, feed de likes.

---

## 🧱 Stack

| Camada | Tecnologias |
|---|---|
| **Backend** | Python · FastAPI · SQLAlchemy · Pydantic · JWT |
| **Banco** | PostgreSQL + PostGIS |
| **Mobile** *(futuro)* | React Native · Expo · TypeScript · Mapbox |
| **Storage** *(futuro)* | Supabase Storage |
| **Infra** | Docker Compose (apenas PostgreSQL no início) |

Decisões técnicas iniciais: SQLAlchemy **síncrono** (sem async no MVP), UUID **nativo** do PostgreSQL, imagens **fora** do banco (apenas o caminho é guardado), secrets via **variáveis de ambiente**.

---

## 📁 Estrutura

```
some-journey/
├── backend/
│   ├── app/
│   │   ├── main.py            # cria a app FastAPI e registra rotas
│   │   ├── core/
│   │   │   ├── config.py      # lê/valida variáveis de ambiente
│   │   │   └── security.py    # (futuro) hash de senha, JWT
│   │   ├── db/
│   │   │   ├── session.py     # engine + SessionLocal + get_db
│   │   │   └── base.py        # base declarativa dos models
│   │   ├── models/            # (futuro) models ORM (User, Memory...)
│   │   ├── schemas/           # (futuro) schemas Pydantic (entrada/saída)
│   │   ├── repositories/      # (futuro) acesso a dados
│   │   ├── services/          # (futuro) regras de negócio
│   │   ├── api/routes/        # (futuro) endpoints
│   │   └── dependencies/      # (futuro) dependencies (ex.: get_current_user)
│   ├── requirements.txt
│   └── .env                   # NÃO versionado — crie a partir do .env.example
├── mobile/                    # (futuro) app React Native / Expo
├── infra/
│   └── docker-compose.yml     # PostgreSQL + PostGIS
├── .env.example
├── .gitignore
└── README.md
```

> Pastas marcadas como *(futuro)* podem ainda não existir no repositório — o Git não versiona pastas vazias; elas surgem conforme cada etapa avança.

---

## ✅ Pré-requisitos

- **Python 3.11+** (o ambiente de desenvolvimento usa 3.14)
- **Docker** + Docker Compose
- **Git**

---

## 🚀 Setup local

### 1. Clonar
```bash
git clone https://github.com/JuanRiber/some-journey.git
cd some-journey
```

### 2. Subir o banco (PostgreSQL + PostGIS)
```bash
docker compose -f infra/docker-compose.yml up -d
docker ps   # confirme que o container some_journey_db está "Up"
```
O banco fica exposto em `localhost:5433`.

### 3. Criar o ambiente virtual e instalar dependências
```bash
cd backend
python -m venv .venv
```
Ativar:
- **Windows (PowerShell):** `.\.venv\Scripts\Activate.ps1`
  - Se aparecer erro de política de execução: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` e ative novamente.
- **Git Bash / Linux / macOS:** `source .venv/Scripts/activate` (ou `.venv/bin/activate`)

```bash
pip install -r requirements.txt
```

### 4. Criar o `.env`
Copie o exemplo para `backend/.env` (este caminho exato — o backend lê o `.env` da pasta `backend/`):
```bash
# a partir de backend/
cp ../.env.example .env
```
> O `.env` real **nunca** é versionado. Em produção, as variáveis vêm do ambiente do servidor, não de um arquivo.

### 5. Rodar a API
A partir de `backend/` (com o venv ativo):
```bash
uvicorn app.main:app --reload
```

---

## 🧪 Testar

Com a API rodando:
- Health check: <http://127.0.0.1:8000/health> → `{"status": "ok"}`
- Documentação interativa (Swagger): <http://127.0.0.1:8000/docs>

---

## 📌 Status atual

Fundação do backend concluída:

- [x] Estrutura do projeto + Docker (PostgreSQL/PostGIS)
- [x] Health check (`/health`)
- [x] Configuração via variáveis de ambiente (`core/config.py`)
- [x] Conexão com o banco (`db/session.py`)
- [x] Base declarativa do ORM (`db/base.py`)
- [ ] **Autenticação** (model User, schemas, repository, security, service, rotas) ← próximo
- [ ] Memórias + pins no mapa
- [ ] Timeline
- [ ] App mobile (Expo)

---

## 🎯 Escopo do MVP

**Entra:** login (e-mail/senha + JWT), mapa interativo, criação de memórias, pins no mapa, timeline simples.

**Fica para depois:** feed social, likes, comentários, IA, realtime, gamificação, refresh token, confirmação de e-mail, admin, impressão física, exportação premium.

---

## 🔒 Segurança (princípios do projeto)

- Senha sempre como **hash** (nunca em texto puro); `password_hash` **nunca** é retornado pela API.
- Secrets (`JWT_SECRET_KEY`, credenciais de banco) **apenas** em variáveis de ambiente — nunca no código nem no Git.
- UUID **nativo** do PostgreSQL (sem IDs sequenciais previsíveis).
- Imagens **fora** do banco (apenas o caminho é armazenado).
- Cada usuário acessa **somente** os próprios dados (ownership validado).
- Senha, token e dados sensíveis **nunca** em logs.

---

## 📝 Convenção de commits

[Conventional Commits](https://www.conventionalcommits.org/): `tipo(escopo): mensagem no imperativo`.

Tipos: `feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `style`, `infra`, `security`.

Exemplos: `feat(auth): add user model` · `chore(deps): pin dependency versions` · `docs(readme): add local setup guide`.
