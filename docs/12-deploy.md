# Deploy para testers (plano gratuito)

Como deixar o Some Journey no ar, a qualquer hora, para um grupo pequeno de testers — sem
pagar nada. É um ambiente **fechado**: o cadastro público fica desligado em produção e as contas
são criadas por script.

## Visão geral

| Parte | Onde | Plano grátis — o que importa |
|---|---|---|
| API (FastAPI, Docker) | **Render** — `render.yaml` | Dorme após **15 min** sem tráfego e leva ~1 min para acordar. 750 h/mês: dá para um serviço o mês inteiro. |
| Banco (Postgres + PostGIS) e fotos | **Supabase** | 500 MB de banco, 1 GB de arquivos. O projeto é **pausado após 7 dias** sem atividade. |
| App (Flutter web) | **Cloudflare Pages** — `.github/workflows/deploy-web.yml` | Estático, sem limite prático. |
| Manter acordado | **UptimeRobot** (ou cron-job.org) | Ping a cada 5 min, grátis. |

O fluxo depois de configurado: **push na `main` → CI → (se verde) Render publica a API e o
GitHub Actions publica o app web.** Nenhum dos dois publica um commit que a suíte reprovou.

A ordem abaixo importa: cada passo usa um valor que o anterior gerou.

---

## 1. Supabase — banco e fotos

1. Em <https://supabase.com>, crie um projeto. Região: **South America (São Paulo)**.
   Na senha do banco, use **só letras e números** — caractere especial teria de ir
   percent-encoded na URL, e é a causa mais comum de "senha errada" que não está errada.
   Guarde a senha.
2. **Storage → New bucket**: nome `memories`, **privado** (não marque Public). O motivo está
   em "Fotos (Supabase Storage)" no README.
3. **Project Settings → API Keys**: copie a **Project URL** (`https://<ref>.supabase.co`) e a
   chave **service_role** (aba *Legacy API keys*). A service_role ignora as policies e nunca
   sai do backend.
4. Botão **Connect** (topo do painel) → **Session pooler** → copie a connection string. Ela vem
   assim:

   ```
   postgresql://postgres.<ref>:[YOUR-PASSWORD]@aws-0-sa-east-1.pooler.supabase.com:5432/postgres
   ```

   Monte a `DATABASE_URL` trocando **o prefixo** e a senha, e exigindo TLS:

   ```
   postgresql+psycopg://postgres.<ref>:<senha>@aws-0-sa-east-1.pooler.supabase.com:5432/postgres?sslmode=require
   ```

   - `+psycopg` é obrigatório: sem ele o SQLAlchemy procura o driver `psycopg2`, que não está
     instalado, e a API não sobe.
   - Use o **Session pooler**, não a *Direct connection*: a direta é só IPv6 e o Render não a
     alcança. O *Transaction pooler* (porta 6543) também não serve — ele quebra prepared
     statements.

O PostGIS é criado pela primeira migration (`0001_baseline`), no primeiro boot da API. Se o log
do Render mostrar erro de permissão em `CREATE EXTENSION postgis`, habilite-o à mão em
**Database → Extensions → postgis**, schema `public`, e faça *Manual Deploy* de novo.

## 2. Render — a API

1. Em <https://render.com>, entre com o GitHub e vá em **New → Blueprint**. Escolha o
   repositório: o Render lê o `render.yaml` e cria o serviço `some-journey-api` no plano free.
2. Ele pede as variáveis marcadas `sync: false`:

   | Variável | Valor |
   |---|---|
   | `DATABASE_URL` | a do passo 1.4 |
   | `JWT_SECRET_KEY` | uma **nova**: `python3 -c "import secrets; print(secrets.token_urlsafe(48))"` |
   | `SUPABASE_URL` | a Project URL (sem `/rest/v1`) |
   | `SUPABASE_SERVICE_KEY` | a service_role |
   | `CORS_ALLOWED_ORIGINS` | `https://some-journey.pages.dev` (o nome do passo 3; ajuste se mudar) |
   | `TRUSTED_HOSTS` | `some-journey-api.onrender.com` (o host que o Render mostrar) |
   | `GOOGLE_CLIENT_ID`, `SMTP_*` | deixe vazias por enquanto — o resto funciona sem elas |

3. O primeiro deploy constrói a imagem e roda `scripts/start.sh`, que aplica as migrations (com
   retry) antes de subir o uvicorn. Para conferir:

   ```bash
   curl https://some-journey-api.onrender.com/health/ready
   ```

   `{"status":"ok"}` quer dizer API no ar **e** banco respondendo.

O blueprint usa `autoDeployTrigger: checksPass`: os próximos deploys só acontecem quando o CI do
commit passa.

## 3. Cloudflare Pages — o app web

O Pages não tem Flutter na imagem de build, então quem compila é o GitHub Actions, que só envia a
pasta pronta.

1. Em <https://dash.cloudflare.com>, crie a conta (grátis). Na página inicial, copie o
   **Account ID** (menu ⋯ ao lado do nome da conta, ou a barra lateral de *Workers & Pages*).
2. **My Profile → API Tokens → Create Token → Custom token**, com a permissão
   **Account · Cloudflare Pages · Edit**. Copie o token (ele aparece uma vez só).
3. No GitHub, **Settings → Secrets and variables → Actions**:
   - aba *Secrets*: `CLOUDFLARE_API_TOKEN` e `CLOUDFLARE_ACCOUNT_ID`;
   - aba *Variables*: `API_URL` = `https://some-journey-api.onrender.com`.
     Opcionais: `GOOGLE_CLIENT_ID` (o client id **web**) e `CF_PAGES_PROJECT`, se o nome
     `some-journey` já estiver tomado no Pages.
4. **Actions → Deploy web → Run workflow**. Na primeira execução ele cria o projeto no Pages; o
   app fica em `https://some-journey.pages.dev`.

Daqui em diante, todo push na `main` com CI verde republica o app. Enquanto os secrets não
existem, o workflow termina verde com um aviso, em vez de falhar.

> Se o Pages der outro endereço (nome tomado), atualize `CORS_ALLOWED_ORIGINS` no Render — senão o
> navegador bloqueia todas as chamadas e o login parece "não fazer nada".

## 4. UptimeRobot — manter acordado

Em <https://uptimerobot.com> (plano free): **New monitor → HTTP(s)**, URL
`https://some-journey-api.onrender.com/health/ready`, intervalo de **5 minutos**.

Esse único monitor resolve dois problemas: o Render não dorme (o limite é 15 min) e o Supabase
recebe uma consulta (`SELECT 1`) a cada ping, então não conta como projeto parado. De brinde, você
recebe um e-mail se a API cair. É por isso que o alvo é o `/health/ready`, e não o `/health` — este
último não toca o banco de propósito.

## 5. Contas dos testers

O cadastro está fechado em produção (`REGISTRATION_OPEN=false`). Crie as contas pela sua
máquina, apontando o script para o banco do Supabase:

```bash
cd backend
DATABASE_URL='postgresql+psycopg://postgres.<ref>:<senha>@aws-0-sa-east-1.pooler.supabase.com:5432/postgres?sslmode=require' \
  .venv/bin/python -m scripts.seed_users tester@exemplo.com
```

A senha gerada aparece **uma vez**; mande-a ao tester por um canal privado. Para trocar a senha
de uma conta que já existe, `scripts.reset_password` (mesmo formato). Sem SMTP configurado, a
recuperação de senha pelo app não envia e-mail em produção — o caminho é esse script.

## O que o tester recebe

- O endereço `https://some-journey.pages.dev`, que funciona no navegador do computador e do
  celular (no celular, *Adicionar à tela inicial* abre como app).
- O e-mail e a senha do passo 5.

App nativo, se um dia fizer falta: no Android, o **Firebase App Distribution** distribui APK de
graça; no iOS, o TestFlight exige a conta Apple Developer (US$ 99/ano).

## Problemas comuns

| Sintoma | Causa provável |
|---|---|
| Login "não faz nada"; no console do navegador, erro de CORS | `CORS_ALLOWED_ORIGINS` diferente da URL real do Pages (com `https://`, sem barra no fim). |
| Resposta `400 Invalid host header` | `TRUSTED_HOSTS` sem o host do Render. Se o log mostrar o health check do próprio Render sendo recusado, acrescente o host que aparece no log. |
| Deploy falha em `alembic upgrade head` | `DATABASE_URL` errada (prefixo sem `+psycopg`, senha, ou *Direct connection* em vez do pooler), ou o projeto Supabase pausado — restaure no painel. |
| Foto responde 503 | `SUPABASE_URL`/`SUPABASE_SERVICE_KEY` vazias ou bucket com nome diferente de `memories`. |
| Primeira abertura do dia demora ~1 min | O ping não está rodando: confira o monitor no UptimeRobot. |
| App abre mas chama `127.0.0.1` | A variável `API_URL` não estava definida no build; o workflow hoje recusa esse caso. |

## Quando deixar de ser grátis

Se a espera para acordar, o limite de 500 MB ou o número de testers começar a atrapalhar, o
próximo degrau é o Render Starter (US$ 7/mês, não dorme) e, depois, o Supabase Pro.
