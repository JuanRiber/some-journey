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
