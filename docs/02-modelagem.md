# Modelagem

Modelagem **atual** do domínio (PostgreSQL + PostGIS). IDs são `UUID` gerados pelo banco;
timestamps são `TIMESTAMPTZ`. Gerida por migrations Alembic (ver [`04-decisoes-tecnicas.md`](04-decisoes-tecnicas.md)).

## Diagrama
```
User
 ├── Memories            (pontos no mapa; podem ser soltos)
 └── Journeys            (trajetórias)
        └── JourneyMemories   (vínculo ordenado jornada ↔ memória)
                └── Memory
```

## users
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID | PK |
| name | varchar(120) | |
| email | varchar(255) | único |
| password_hash | text | nunca exposto pela API |
| created_at / updated_at | timestamptz | |
| is_active | bool | soft-disable da conta |

Usuário é o **dono** das memórias e jornadas.

## memories
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID | PK |
| user_id | UUID | FK → users (ON DELETE CASCADE) |
| title | varchar(120) | hoje obrigatório (ver regras) |
| text | text | núcleo da memória |
| location | `GEOGRAPHY(POINT, 4326)` | PostGIS; guarda `POINT(longitude, latitude)` |
| image_path | text \| null | caminho no Storage (não URL pública) |
| occurred_at | timestamptz | quando aconteceu |
| created_at / updated_at | timestamptz | |
| deleted_at | timestamptz \| null | soft delete |

> A API fala `latitude`/`longitude`; a conversão para/de `POINT` acontece no backend.
> Índice espacial GiST em `location`; índice parcial por usuário ativo.

Memória é um **ponto geográfico com significado**. Existe sozinha ou conectada a uma jornada.

## journeys
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID | PK |
| user_id | UUID | FK → users (CASCADE) |
| title | varchar(120) | |
| description | text \| null | |
| status | varchar(20) | `draft` / `active` / `paused` / `finished` |
| cover_image_path | text \| null | reservado (capa) — ainda não usado pela API |
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
