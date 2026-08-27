# Changelog

Registro das mudanças de **documentação** (`/docs`). Mudanças de código ficam no histórico do Git.

## 2026-06-28

### Documentação
- Criada a estrutura inicial da pasta `/docs`.
- Registrada a visão do produto Some Journey.
- Registradas as regras de negócio iniciais.
- Registrada a modelagem inicial de usuários, memórias, jornadas e pontos de jornada.
- Registrada a decisão de armazenar imagens no Supabase Storage.
- Registrada a decisão de manter apenas a referência da imagem no PostgreSQL/PostGIS.
- Registrada a regra de que memórias podem existir sem jornada.
- Registrada a regra de que jornadas conectam memórias em sequência.
- Registrada a possibilidade de conectar pontos soltos a jornadas posteriormente.
- Registrados os fluxos principais de usuário.
- Registrado o roadmap inicial do produto.

> Nota: a documentação foi escrita **alinhada ao código atual**, marcando o que já está
> implementado e o que é planejado. Divergências conhecidas frente à especificação original:
> a tabela de vínculo se chama `journey_memories` (conceito "journey_points"); existe o status
> `draft` e a transição `resume`; o mapa usa Leaflet/OSM hoje (Mapbox planejado); `PATCH /journeys/{id}`
> e `DELETE /memories/{id}/image` ainda não existem; o título da memória hoje é obrigatório.

## 2026-07-08

### Documentação
- Registrada a distinção entre **linha simbólica** (liga memórias na ordem) e
  **percurso real por GPS** (`Real Journey Track`).
- Documentados os endpoints de percurso (`/journeys/{id}/tracks/...`) e o mapa da
  jornada em GeoJSON (`GET /journeys/{id}/map`) no README.
- Roadmap: percurso real por GPS marcado como feito no MVP; tracking em segundo
  plano registrado como evolução (exige `expo-task-manager` + dev build).

## 2026-08-25

### Documentação
- **Reconciliação geral com o código.** A documentação tinha ficado para trás do
  HEAD; o levantamento foi feito contra o schema real do banco e o OpenAPI da API
  em execução, não por leitura de código.
- README: passou a descrever os **dois clientes** (`app_flutter/`, onde a evolução
  acontece, e `mobile/`), além de `docs/`, `e2e/` e `render.yaml`, que não
  apareciam na árvore do projeto.
- README: removida a afirmação de que as tabelas são criadas no startup — o
  `create_all` saiu na adoção do Alembic e o próprio README já dizia o contrário
  mais abaixo.
- README: seção de API completada com recuperação de senha, `/me/profile`,
  `/me/avatar`, `PATCH /journeys/{id}`, capa da jornada, fotos no plural,
  `GET /journeys/{id}/memories`, `/health/ready` e o contrato de paginação.
- README: "Status atual" corrigido — upload de imagens, recuperação de senha e o
  mapa do atlas estavam marcados como pendentes, mas já existem.
- README: nova seção **Divergências conhecidas**, registrando o que ainda não bate
  entre código, documentação e intenção de produto.
- [`02-modelagem.md`](02-modelagem.md): acrescentadas as tabelas que faltavam
  (`memory_images`, `journey_tracks`, `journey_track_points`,
  `password_reset_tokens`), os campos de lugar em `memories`, `mood`/`is_private`
  em `journeys` e `username`/`avatar_path`/`bio`/`password_changed_at` em `users`.
- [`03-api-planejada.md`](03-api-planejada.md): `PATCH /journeys/{id}` e o delete
  de imagem deixaram de ser 🔜 (existem); documentados perfil, avatar, capa,
  paginação (cursor no header `X-Next-Cursor`) e saúde.
- [`01-regras-negocio.md`](01-regras-negocio.md): registrada a divergência de que
  **`text` virou opcional** na API, o inverso da regra "texto é o núcleo".
- [`06-roadmap.md`](06-roadmap.md): "múltiplas fotos por memória" (V2) foi
  entregue no MVP com teto de 5; mapa interativo marcado como feito.
- [`10-localizacao.md`](10-localizacao.md): registrado que o `timezone` passou a
  ser resolvido por `geocoding.resolve_timezone` com `tzfpy` (4,5 MB), preferido
  ao `timezonefinder` (53 MB) pelo peso da imagem no free tier.

### Código
- O `timezone` da memória **deixou de nascer nulo**: o `timezone_resolver` já era
  injetável e testado, mas nenhum resolvedor era ligado na composição. Agora
  `get_provider()` entrega o resolvedor offline, e o mesmo vale para o backfill.
  Guarda de regressão incluída — inclusive contra inverter latitude e longitude,
  já que a biblioteca recebe `(lng, lat)` e o contrato interno é `(lat, lng)`.

> Divergência que **permanece** (registrada de propósito, não resolvida): o título
> da memória continua obrigatório enquanto o texto é opcional, ao contrário do que
> o produto pede. Inverter isso muda o contrato da API e afeta os dois clientes —
> é decisão de produto, não limpeza de documentação.
