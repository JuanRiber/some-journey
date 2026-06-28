# API

Contrato atual + itens planejados. Tudo sob `/` na mesma API FastAPI. Rotas privadas exigem
header `Authorization: Bearer <token>`. ✅ = implementado · 🔜 = planejado.

## Autenticação
- ✅ `POST /auth/register` — `{name, email, password}` → 201 `{id, name, email, created_at}`
- ✅ `POST /auth/login` — `{email, password}` → `{access_token, token_type, expires_in}`
- ✅ `GET /auth/me` — usuário autenticado

## Memórias  (privadas)
- ✅ `POST /memories` — cria ponto/memória solta
- ✅ `GET /memories` — lista as do usuário (mais recentes primeiro)
- ✅ `GET /memories/{id}` — busca uma
- ✅ `PATCH /memories/{id}` — edição parcial (lat/long sempre juntas)
- ✅ `DELETE /memories/{id}` — soft delete (204)

IDs inexistentes ou de outro usuário → **404** uniforme.

## Imagem da memória  (privadas)
- ✅ `POST /memories/{id}/image` — upload `multipart/form-data` (campo `file`). Vai para o
  Supabase Storage; o banco guarda só `image_path`; a resposta traz `image_url` assinada.
- 🔜 `DELETE /memories/{id}/image` — remover a imagem.

Imagem é opcional; usuário só envia para memória própria. Sem Supabase configurado, o upload
responde **503**.

## Jornadas  (privadas)
- ✅ `POST /journeys` — `{title, description?, started_at?}` → 201 (nasce `draft`)
- ✅ `GET /journeys` — lista (com `points_count`)
- ✅ `GET /journeys/{id}` — detalhe com `points[]` ordenados + `route` (LineString GeoJSON, ou `null` se < 2 pontos)
- ✅ `DELETE /journeys/{id}` — soft delete (não apaga memórias)
- 🔜 `PATCH /journeys/{id}` — editar título/descrição

## Controle de jornada  (privadas)
- ✅ `POST /journeys/{id}/start` — `draft → active`
- ✅ `POST /journeys/{id}/pause` — `active → paused`
- ✅ `POST /journeys/{id}/resume` — `paused → active`
- ✅ `POST /journeys/{id}/finish` — `active|paused → finished`

Transição inválida ou segunda jornada ativa → **409**.

## Pontos de jornada  (privadas)
- ✅ `POST /journeys/{id}/points` — `{memory_id}` **associa uma memória existente** (ponto solto) à jornada
- ✅ `POST /journeys/{id}/memories` — **cria uma memória nova já vinculada** (modo jornada)
- ✅ `PATCH /journeys/{id}/points/reorder` — `{memory_ids: [...]}` define a ordem completa
- ✅ `DELETE /journeys/{id}/points/{memory_id}` — remove o ponto da jornada **sem excluir a memória**

Permitem montar e reordenar o rastro; o detalhe da jornada já devolve os pontos ordenados + a linha.

## Mapa  (privada)
- ✅ `GET /map` — `{loose_points[], journeys[]}` para desenhar o atlas (pins soltos + jornadas com pontos e rastro).
  Filtros: `?bbox=min_lng,min_lat,max_lng,max_lat` e `?journey_id={id}`.

## Exemplos de payload

Criar memória:
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
