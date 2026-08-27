# Modelagem

Modelagem **atual** do domínio (PostgreSQL + PostGIS). IDs são `UUID` gerados pelo banco;
timestamps são `TIMESTAMPTZ`. Gerida por migrations Alembic (`0001`..`0010`, ver
[`04-decisoes-tecnicas.md`](04-decisoes-tecnicas.md)).

## Diagrama
```
User
 ├── Memories            (pontos no mapa; podem ser soltos)
 │      └── MemoryImages      (até 5 fotos por memória)
 ├── Journeys            (trajetórias)
 │      ├── JourneyMemories   (vínculo ordenado jornada ↔ memória)
 │      │      └── Memory
 │      └── JourneyTracks     (percurso real por GPS)
 │             └── JourneyTrackPoints
 └── PasswordResetTokens (recuperação de senha)
```

## users
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID | PK |
| name | varchar(120) | |
| email | varchar(255) | único |
| password_hash | text | nunca exposto pela API |
| password_changed_at | timestamptz | JWTs emitidos antes desta data são recusados |
| username | varchar(30) \| null | `@username` público, único; reservados são recusados |
| avatar_path | text \| null | caminho no Storage (não URL pública) |
| bio | varchar(160) \| null | frase pessoal do Perfil |
| created_at / updated_at | timestamptz | |
| is_active | bool | soft-disable da conta |

Usuário é o **dono** das memórias e jornadas.

## memories
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID | PK |
| user_id | UUID | FK → users (ON DELETE CASCADE) |
| title | varchar(120) | hoje obrigatório (ver regras) |
| text | text | opcional na API (default `""`), `NOT NULL` no banco |
| location | `GEOGRAPHY(POINT, 4326)` | PostGIS; guarda `POINT(longitude, latitude)` |
| image_path | text \| null | **legado** de quando era uma foto só; ver `memory_images` |
| occurred_at | timestamptz | quando aconteceu |
| created_at / updated_at | timestamptz | |
| deleted_at | timestamptz \| null | soft delete |

Campos do **lugar** (migração `0009`, todos nullable — ver [`10-localizacao.md`](10-localizacao.md)):

| Campo | Tipo | Notas |
|---|---|---|
| place_name | text \| null | nome do ponto ("Praia de Iracema") |
| place_label | text \| null | rótulo curto exibido ao usuário |
| city | text \| null | agregado no Perfil; indexado |
| state_province | text \| null | estado/província |
| country | text \| null | nome por extenso |
| country_code | char(2) \| null | ISO-3166-1 alpha-2; indexado |
| continent | text \| null | **derivado** de `country_code` |
| formatted_address | text \| null | endereço completo do provedor |
| timezone | text \| null | IANA (ex.: `America/Fortaleza`), resolvido offline pelas coordenadas |
| geohash | varchar(12) \| null | indexado, para vizinhança/clustering |
| geocoded_at | timestamptz \| null | `NULL` = fila do backfill |

> A API fala `latitude`/`longitude`; a conversão para/de `POINT` acontece no backend.
> Índice espacial GiST em `location`; índices parciais por usuário ativo e para a
> paginação keyset (migração `0008`).

Memória é um **ponto geográfico com significado**. Existe sozinha ou conectada a uma jornada.

## memory_images
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID | PK |
| memory_id | UUID | FK → memories (CASCADE) |
| image_path | text | caminho no Supabase Storage |
| position | int | ordem da foto |
| created_at | timestamptz | |
| deleted_at | timestamptz \| null | soft delete |

> **Até 5 fotos por memória** (teto em `memory_service._MAX_IMAGES`). A API devolve
> `image_url` assinada e temporária para cada uma.

## journeys
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID | PK |
| user_id | UUID | FK → users (CASCADE) |
| title | varchar(120) | |
| description | text \| null | |
| status | varchar(20) | `draft` / `active` / `paused` / `finished` |
| mood | text \| null | atmosfera da jornada |
| is_private | bool | privacidade da jornada |
| cover_image_path | text \| null | capa; definida por `POST /journeys/{id}/cover` |
| started_at / ended_at | timestamptz \| null | |
| created_at / updated_at | timestamptz | |
| deleted_at | timestamptz \| null | soft delete |

> Índice único parcial garante **uma jornada `active` por usuário**.

Jornada é uma **trajetória** formada por pontos/memórias em sequência.

## journey_memories  (a tabela de vínculo — o conceito de "journey_points")
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID | PK |
| journey_id | UUID | FK → journeys (CASCADE) |
| memory_id | UUID | FK → memories (CASCADE) |
| position | int | ordem do ponto no rastro (= `order_index`) |
| created_at | timestamptz | quando foi vinculado (= `added_at`) |
| deleted_at | timestamptz \| null | desvincular = soft delete do vínculo |

> Esta tabela conecta memórias a jornadas e permite vincular uma memória solta depois.
> **MVP:** índice único parcial em `memory_id` (onde `deleted_at IS NULL`) garante que uma
> memória esteja em **no máximo uma jornada** por vez. A estrutura já está pronta para,
> no futuro, suportar uma memória em várias jornadas (basta trocar a constraint).

## journey_tracks  (percurso real por GPS)
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID | PK |
| user_id | UUID | FK → users (CASCADE) |
| journey_id | UUID | FK → journeys (CASCADE) |
| source | varchar(20) | origem da captura |
| started_at | timestamptz | |
| ended_at | timestamptz \| null | `NULL` = trecho ainda aberto |
| created_at / updated_at | timestamptz | |
| deleted_at | timestamptz \| null | soft delete |

> Um trecho aberto por jornada de cada vez. Pausar/retomar gera vários trechos;
> a visualização une todos.

## journey_track_points
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID | PK |
| track_id | UUID | FK → journey_tracks (CASCADE) |
| user_id / journey_id | UUID | desnormalizados para filtrar por dono sem join |
| location | `GEOGRAPHY(POINT, 4326)` | ponto GPS bruto |
| accuracy / altitude / speed / heading | double \| null | metadados do GPS |
| recorded_at | timestamptz | quando o ponto foi capturado |
| created_at | timestamptz | |

> Enviados em lote (até 1000 por requisição). **Nunca** expostos no mapa global —
> a visão macro mostra só a linha simbólica.

## password_reset_tokens
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID | PK |
| user_id | UUID | FK → users (CASCADE) |
| token_hash | varchar(64) | só o **hash** vai para o banco |
| expires_at | timestamptz | validade (`PASSWORD_RESET_TOKEN_TTL_MINUTES`) |
| used_at | timestamptz \| null | uso único |
| created_at | timestamptz | |
