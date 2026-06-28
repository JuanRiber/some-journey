# Fluxos de Usuário

Fluxos principais do MVP. No web o mapa é interativo (Leaflet); no nativo, o local vem por
busca/GPS e a visualização é por lista (ver [`04-decisoes-tecnicas.md`](04-decisoes-tecnicas.md)).

## Fluxo 1 — Criar ponto solto
1. Usuário abre o app e vai criar uma memória.
2. Escolhe o local: toca no mapa (web), busca pelo nome ou usa a localização atual (GPS).
3. Sistema captura `latitude`/`longitude`.
4. Usuário escreve o texto (núcleo) e, opcionalmente, título.
5. Usuário define a data do acontecimento.
6. Opcional: anexa uma foto.
7. Sistema salva a memória (e sobe a foto, se houver).
8. O ponto aparece como **pin** no mapa e na timeline.

## Fluxo 2 — Iniciar jornada
1. Usuário cria uma jornada (título + descrição opcional). Ela nasce `draft`.
2. Usuário **inicia** a jornada → status `active`.
3. Com a jornada ativa, registra pontos (memórias novas já entram vinculadas).
4. Cada ponto entra na **sequência** da jornada.
5. O mapa desenha o **rastro** conectando os pontos na ordem.
6. Usuário pode **pausar** (libera o slot ativo) ou **finalizar** a jornada.

## Fluxo 3 — Conectar pontos antigos
1. Usuário já tem pontos soltos no mapa.
2. Cria ou abre uma jornada existente.
3. Vincula memórias soltas à jornada (lista de pontos soltos disponíveis).
4. Define/ajusta a **ordem** dos pontos (reordenar).
5. Sistema cria os vínculos em `journey_memories` (sem recriar as memórias).
6. O mapa passa a desenhar o rastro.

## Fluxo 4 — Visualizar mapa
1. Usuário abre o Atlas.
2. Sistema exibe pins de memórias (soltas e de jornada) e os rastros.
3. Cores distinguem pontos soltos de pontos de jornada.
4. Usuário pode focar uma jornada específica (`?journey_id`).
5. Sistema destaca os pontos e a linha daquela jornada.
6. Tocar num pin abre o detalhe da memória.

## Fluxo 5 — Upload de foto
1. Usuário seleciona uma imagem (galeria).
2. Sistema valida que a memória pertence ao usuário.
3. Backend envia o arquivo ao Supabase Storage (bucket privado) e guarda `image_path`.
4. A resposta traz a memória com uma `image_url` **assinada** e temporária.
5. O detalhe da memória exibe a foto.
