# Regras de Negócio

> Notas marcadas com **(impl.)** já estão no código; **(planejado)** ainda não.

## Usuários
- Todo usuário tem suas próprias memórias e jornadas. **(impl.)**
- Um usuário só pode ver, editar, excluir e conectar os próprios dados. **(impl.)**
- Dados de um usuário nunca são expostos a outro. IDs de terceiros e IDs inexistentes
  retornam o **mesmo 404** (anti-enumeração). **(impl.)**
- Rotas privadas são protegidas por autenticação (Bearer/JWT). **(impl.)**

## Memórias
- Uma memória é **um ponto no mapa** e pertence a um usuário. **(impl.)**
- Pode existir **sozinha**, sem jornada. **(impl.)**
- Precisa de **localização** (latitude/longitude). **(impl.)**
- Precisa de **data do acontecimento** (`occurred_at`), separada de `created_at`. **(impl.)**
- **Texto** é o núcleo da memória. **(impl.)**
- **Foto** é opcional. **(impl.)**
- **Título**: a intenção do produto é ser opcional; **hoje a API exige título não vazio**
  (1–120 chars). Reavaliar quando for o caso. **(impl. — divergência)**
- Pode ser vinculada a uma jornada **depois** de criada. **(impl.)**
- Excluir uma jornada **não apaga** as memórias. **(impl.)**
- Exclusão é **soft delete** (`deleted_at`). **(impl.)**

## Jornadas
- Uma jornada é uma **trajetória** que conecta vários pontos/memórias, e pertence a um usuário. **(impl.)**
- Status: `draft` (criada, não iniciada), `active`, `paused`, `finished`.
  O produto pediu `active/paused/finished`; mantivemos `draft` para "criada mas não iniciada". **(impl.)**
- Só pode haver **uma jornada `active` por usuário** por vez; pausar libera o slot. **(impl.)**
- Enquanto `active`, novos pontos entram em sequência. **(impl.)**
- Iniciar / pausar / retomar / finalizar são transições controladas; `finished` é terminal. **(impl.)**
- Pontos soltos podem ser conectados depois. **(impl.)**
- O **rastro** é formado pela **ordem** dos pontos; o usuário pode **reordenar**. **(impl.)**
- A jornada **organiza** memórias — não as substitui. **(impl.)**

## Pontos soltos
- O usuário pode criar pontos individuais sem iniciar jornada. **(impl.)**
- Podem permanecer soltos indefinidamente. **(impl.)**
- Podem ser conectados depois a uma jornada, **sem apagar nem recriar** a memória. **(impl.)**
- **MVP:** uma memória pertence a **no máximo uma** jornada por vez (índice único parcial). Desvincular libera a memória. **(impl.)**

## Imagens
- Opcionais. **(impl.)**
- O **arquivo não fica no PostgreSQL**. **(impl.)**
- Armazenadas no **Supabase Storage** (bucket privado). **(impl.)**
- O banco guarda só a referência (`image_path`); a API devolve uma `image_url` **assinada** e temporária. **(impl.)**
- Um usuário só anexa imagem às próprias memórias. **(impl.)**

## Mapa
- O mapa é o centro da experiência. **(impl. no web; nativo em evolução)**
- Mostra pins de memórias e rastros de jornadas. **(impl.)**
- Diferencia pontos soltos de pontos de jornada (cores distintas). **(impl.)**
- Suporta recorte por área (bbox) e por jornada; visão mundo/país/região/cidade vem do zoom. **(impl. via `GET /map`)**

## Restrições do MVP (não implementar agora)
Feed social, likes, comentários, gamificação, IA, grupos complexos, realtime avançado,
monetização, impressão física e exportação premium.
