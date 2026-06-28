# Decisões Técnicas

Registro curto das decisões já tomadas. Formato: **Decisão / Motivo / Consequência**.

## Stack principal
**Decisão.** Mobile: React Native + Expo + TypeScript. Backend: Python + FastAPI + SQLAlchemy +
Pydantic. Banco: PostgreSQL + PostGIS. Storage de imagens: Supabase Storage. Auth: JWT no backend.
**Motivo.** Stack produtiva, tipada e adequada a dados geográficos.
**Consequência.** Camadas separadas no backend (models / schemas / repositories / services / routes).

## Banco geográfico (PostGIS)
**Decisão.** PostgreSQL com PostGIS; localização como `GEOGRAPHY(POINT, 4326)`.
**Motivo.** O sistema depende de pontos, mapas, recortes por área e rastros.
**Consequência.** Índice espacial GiST; consultas de mapa (ex.: bbox) feitas no banco.

## Migrations versionadas (Alembic)
**Decisão.** O schema é gerido por **Alembic**; o `create_all` no startup foi removido.
**Motivo.** `create_all` nunca altera tabelas existentes — mascarava drift de schema.
**Consequência.** Rodar `alembic upgrade head` antes de subir a API. Migrations em `backend/alembic/`.

## Imagens fora do banco
**Decisão.** Arquivo no Supabase Storage (bucket **privado**); banco guarda só `image_path`;
a API devolve `image_url` **assinada** e temporária (assinatura em lote na listagem).
**Motivo.** Banco leve, backup simples, separação de arquivos e dados; preparado p/ múltiplas fotos.
**Consequência.** O service key fica só no backend; sem credenciais o upload responde 503.

## Memória pode existir sem jornada
**Decisão.** Uma memória existe sozinha.
**Motivo.** O usuário pode marcar pontos aleatórios sem estar numa trajetória.
**Consequência.** Jornada é opcional; pontos soltos são cidadãos de primeira classe.

## Jornada é camada de organização
**Decisão.** Jornada conecta memórias via tabela de vínculo (`journey_memories`); não as substitui.
**Motivo.** Permite criar pontos soltos e conectá-los depois, e reordenar.
**Consequência.** Excluir/desvincular a jornada não apaga memórias.

## Uma memória por jornada (MVP)
**Decisão.** Uma memória pertence a no máximo uma jornada ativa (índice único parcial em `memory_id`).
**Motivo.** Simplifica o MVP.
**Consequência.** Trocar a constraint no futuro habilita memória em várias jornadas, sem migração de dados.

## Data do acontecimento separada
**Decisão.** `occurred_at` distinto de `created_at`.
**Motivo.** A memória pode ser registrada depois do fato.
**Consequência.** A timeline ordena por `occurred_at`.

## Soft delete
**Decisão.** Usar `deleted_at` em memórias, jornadas e vínculos.
**Motivo.** Memórias têm valor emocional; reduz perda acidental e permite recuperação futura.
**Consequência.** Toda consulta filtra `deleted_at IS NULL`.

## Ownership + 404 uniforme
**Decisão.** Tudo é filtrado por `user_id`; recurso de outro usuário responde 404 igual a inexistente.
**Motivo.** Privacidade e anti-enumeração.
**Consequência.** Nenhuma rota confia em `user_id` vindo do cliente — sempre do token.

## Mapa: Leaflet/OSM agora, Mapbox planejado
**Decisão.** Hoje o mapa (web) usa **Leaflet + OpenStreetMap** (sem API key); o seletor de local
não pede lat/long manual.
**Motivo.** Tirar o mapa do papel sem depender de chave/conta. No nativo, fallback por busca/lista.
**Consequência.** **Mapbox** (ou provedor nativo) fica planejado para o atlas nativo/futuro;
o backend (`GET /map`) já entrega pins + rastros independente do provedor visual.
