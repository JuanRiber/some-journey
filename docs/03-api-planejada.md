# API

Contrato atual + itens planejados. Tudo sob `/` na mesma API FastAPI. Rotas privadas exigem
header `Authorization: Bearer <token>`. ✅ = implementado · 🔜 = planejado.

> O contrato executável fica em `/docs` (Swagger) com a API rodando. Em
> `APP_ENV=production` o `/docs`, o `/redoc` e o `/openapi.json` ficam desligados.

## Saúde
- ✅ `GET /health` — vivo
- ✅ `GET /health/ready` — vivo **e** com o banco respondendo (503 se não)

## Autenticação
- ✅ `POST /auth/register` — `{name, email, password}` → 201 `{id, name, email, created_at}`.
  Em produção o cadastro é **fechado** por padrão (contas via `scripts/seed_users`).
- ✅ `POST /auth/login` — `{email, password}` → `{access_token, token_type, expires_in}`
- ✅ `GET /auth/me` — usuário autenticado
- ✅ `POST /auth/change-password` — troca a senha; os tokens emitidos antes deixam de valer
- ✅ `POST /auth/forgot-password` — gera o token de reset (enviado por e-mail se houver SMTP;
  fora de produção e sem SMTP, o link é logado). Responde igual para e-mail existente ou não.
- ✅ `POST /auth/reset-password` — redefine a senha com o token (validade + uso único)

## Memórias  (privadas)
- ✅ `POST /memories` — cria ponto/memória solta; `life_phase_id` opcional
- ✅ `GET /memories` — lista as do usuário (mais recentes primeiro), **paginação keyset**
  (`?limit=&cursor=`); `?life_phase_id=` aplica a lente da fase (ver **Fases da vida**)
- ✅ `GET /memories/{id}` — busca uma
- ✅ `PATCH /memories/{id}` — edição parcial (lat/long sempre juntas). Em `life_phase_id`,
  e só nele, `null` **solta** a memória da fase — um id não tem string vazia que o substitua
- ✅ `DELETE /memories/{id}` — soft delete (204)

IDs inexistentes ou de outro usuário → **404** uniforme.

**Contrato de paginação** (idêntico em todas as listagens): o corpo continua sendo um
**array JSON puro**; quando há próxima página, o cursor volta no header
`X-Next-Cursor` (sem o header, acabou). `limit` tem default 30 e teto 100. O cursor é
opaco (base64url de `<iso8601>|<uuid>`); malformado responde **400**, nunca 500.

O **lugar** da memória (cidade, país, continente, geohash…) é resolvido por geocoding
reverso e persistido — ver [`10-localizacao.md`](10-localizacao.md). Memórias com
`geocoded_at IS NULL` são reprocessadas por `python -m scripts.backfill_geocoding`.

## Fotos da memória  (privadas)
- ✅ `POST /memories/{id}/images` — upload `multipart/form-data` (campo `file`). Vai para o
  Supabase Storage; o banco guarda só `image_path`; a resposta traz `image_url` assinada.
  **Até 5 fotos por memória.**
- ✅ `DELETE /memories/{id}/images/{image_id}` — remove uma foto.

Foto é opcional; usuário só envia para memória própria. Sem Supabase configurado, o upload
responde **503** e a `image_url` volta nula.

## Música da memória  (privadas)
- ✅ `POST /memories/{id}/music` — anexa a canção que estava tocando (201)
- ✅ `DELETE /memories/{id}/music/{music_id}` — remove uma faixa

O corpo é o **snapshot** da faixa que o app obteve do catálogo: a API não
consulta provedor nenhum. Buscar exige rede e é do provedor; guardar é nosso —
separar os dois deixa o app trocar de catálogo sem que a API precise saber.

A mesma faixa não entra duas vezes na mesma memória (**409**); o teto é de 5 por
memória (**409**). As faixas viajam junto da memória em `GET /memories` e
`GET /memories/{id}`, no campo `music`.

## Jornadas  (privadas)
- ✅ `POST /journeys` — `{title, description?, mood?, is_private?, started_at?, ended_at?, life_phase_id?}` → 201 (nasce `draft`)
- ✅ `GET /journeys` — lista (com `points_count`), **paginação keyset** (`?limit=&cursor=`);
  `?life_phase_id=` aplica a lente da fase
- ✅ `GET /journeys/{id}` — detalhe com `points[]` ordenados + `route` (LineString GeoJSON, ou `null` se < 2 pontos)
- ✅ `PATCH /journeys/{id}` — edita título, descrição, `mood`, `is_private`, datas e
  `life_phase_id` (aqui `null` solta a jornada da fase)
- ✅ `DELETE /journeys/{id}` — soft delete (não apaga memórias)

## Capa da jornada  (privadas)
- ✅ `POST /journeys/{id}/cover` — define a capa (Supabase Storage; grava `cover_image_path`)
- ✅ `DELETE /journeys/{id}/cover` — remove a capa

## Controle de jornada  (privadas)
- ✅ `POST /journeys/{id}/start` — `draft → active`
- ✅ `POST /journeys/{id}/pause` — `active → paused`
- ✅ `POST /journeys/{id}/resume` — `paused → active`
- ✅ `POST /journeys/{id}/finish` — `active|paused → finished`

Transição inválida ou segunda jornada ativa → **409**.

## Pontos de jornada  (privadas)
- ✅ `GET /journeys/{id}/memories` — lista as memórias da jornada, na ordem
- ✅ `POST /journeys/{id}/points` — `{memory_id}` **associa uma memória existente** (ponto solto) à jornada
- ✅ `POST /journeys/{id}/memories` — **cria uma memória nova já vinculada** (modo jornada)
- ✅ `PATCH /journeys/{id}/points/reorder` — `{memory_ids: [...]}` define a ordem completa
- ✅ `DELETE /journeys/{id}/points/{memory_id}` — remove o ponto da jornada **sem excluir a memória**

Permitem montar e reordenar o rastro; o detalhe da jornada já devolve os pontos ordenados + a linha.

## Percurso real por GPS  (privadas)
Distinto da linha **simbólica** que liga as memórias na ordem.

- ✅ `POST /journeys/{id}/tracks/start` — abre um trecho (409 se já houver um aberto)
- ✅ `POST /journeys/{id}/tracks/{track_id}/points` — envia pontos em lote (até 1000)
- ✅ `POST /journeys/{id}/tracks/{track_id}/finish` — fecha o trecho
- ✅ `GET /journeys/{id}/tracks` — lista os trechos (contagem + distância)
- ✅ `DELETE /journeys/{id}/tracks/{track_id}` — remove o percurso (não apaga memórias)
- ✅ `GET /journeys/{id}/map` — GeoJSON: `tracks` + memórias + `symbolic_route`

## Mapa  (privada)
- ✅ `GET /map` — `{loose_points[], journeys[]}` para desenhar o atlas (pins soltos + jornadas com pontos e rastro).
  Filtros: `?bbox=min_lng,min_lat,max_lng,max_lat`, `?journey_id={id}` e
  `?life_phase_id={id}` (a lente de uma fase; com `journey_id`, o foco na jornada vence).

A visão macro mostra só a linha simbólica — pontos de GPS brutos nunca saem por aqui.

## Fases da vida  (privadas)
- ✅ `GET /life-phases` — as fases do usuário, na ordem em que a vida aconteceu (sem início vão para o fim)
- ✅ `POST /life-phases` — `{name, description?, color?, started_at?, ended_at?}` → 201
- ✅ `GET /life-phases/{id}`
- ✅ `PATCH /life-phases/{id}` — parcial; aqui `null` **limpa** (uma fase encerrada por engano volta a ser a fase em curso)
- ✅ `DELETE /life-phases/{id}` — soft delete que **solta** memórias e jornadas da fase (204)

`color` é um papel da paleta (`primary`, `secondary`, `accent`, `moss`, `highlight`). Fase de
outra pessoa ou inexistente → **404** uniforme.

**A lente** (`?life_phase_id=` em `/memories`, `/journeys` e `/map`):

- a memória está na fase quando foi marcada nela **ou** quando está numa jornada (ativa,
  com vínculo ativo) marcada nela;
- a jornada está na fase quando foi marcada nela **ou** quando alguma memória dela foi; no
  mapa ela vem inteira, com o rastro;
- a herança desce da jornada para a memória e para aí: uma memória marcada não puxa as
  irmãs. E a leitura da memória devolve só a marca **própria** em `life_phase_id`;
- a fase não é deduzida das datas.

Fase alheia ou apagada no filtro → **404** (e não lista vazia, que esconderia o id errado).
No corpo de um POST/PATCH de memória ou jornada → **422**: o recurso da URL existe, quem não
serve é um valor do corpo.

## Perfil  (privadas)
Um **único** endpoint agregado, com as contagens em SQL — o cliente jamais baixa memórias
para contá-las. Ver [`09-perfil.md`](09-perfil.md).

- ✅ `GET /me/profile` — identidade, estatísticas, passaporte, jornada atual e atividade recente
- ✅ `PATCH /me/profile` — edita `name`, `username` e `bio`
- ✅ `POST /me/avatar` — envia o avatar (Supabase Storage)
- ✅ `DELETE /me/avatar` — remove o avatar

## Exemplos de payload

Criar memória (`title` e `text` são opcionais; obrigatórios mesmo são local e
`occurred_at` — ver [`01-regras-negocio.md`](01-regras-negocio.md)):
```json
{
  "title": "Lugar que encontrei caminhando",
  "text": "Passei por aqui e achei esse canto bonito.",
  "latitude": -3.7327,
  "longitude": -38.5270,
  "occurred_at": "2026-06-28T15:30:00Z"
}
```

Criar jornada:
```json
{ "title": "Viagem pelos EUA", "description": "Lugares que passei durante a viagem." }
```

Associar memória existente à jornada (entra ao fim; ordene depois com `.../points/reorder`):
```json
{ "memory_id": "uuid-da-memoria" }
```

Reordenar pontos:
```json
{ "memory_ids": ["uuid-3", "uuid-1", "uuid-2"] }
```
