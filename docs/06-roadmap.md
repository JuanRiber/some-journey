# Roadmap

Legenda: ✅ feito · 🟡 parcial · ⬜ a fazer. (Progresso detalhado no [`changelog.md`](changelog.md).)

## MVP
- ✅ Login / cadastro (JWT).
- ✅ Mapa interativo — o app Flutter desenha o atlas com `flutter_map` (tiles OSM/CartoDB)
  consumindo `GET /map`; o app Expo usa Leaflet no web. Mapbox segue planejado para V2.
- ✅ Criar memória geolocalizada.
- ✅ Visualizar pins (`GET /map`).
- ✅ Timeline simples.
- ✅ Criar jornada simples (com ciclo `draft/active/paused/finished`).
- ✅ Associar pontos a jornadas (existentes e novos) + reordenar.
- ✅ Desenhar rastro no mapa (LineString).
- ✅ **Percurso real por GPS** — `JourneyTrack`/`JourneyTrackPoint`, `GET /journeys/{id}/map` (GeoJSON), captura em **primeiro plano** no app e alternância "Percurso real ↔ Conectar memórias". Distinto da linha simbólica; o mapa global segue simbólico. Tracking em **segundo plano** é evolução (exige `expo-task-manager` + dev build).
- ✅ Upload de fotos — **até 5 por memória** no Supabase Storage (upload, URL assinada e
  delete validados de ponta a ponta). Antecipou o item "múltiplas fotos" da V2.
- ✅ Recuperação de senha real — token com validade e uso único, envio por SMTP opcional,
  mais troca de senha autenticada que invalida os tokens antigos.
- ✅ Lugar da memória persistido (geocoding reverso) + script de backfill, **incluindo o fuso**
  resolvido offline pelas coordenadas.
- ✅ Perfil agregado (`GET /me/profile`) com passaporte, `@username`, avatar e bio.
- ✅ Paginação keyset em `/memories` e `/journeys`.

## V2
- ✅ Múltiplas fotos por memória (entregue no MVP, teto de 5).
- Fases da vida.
- Filtros avançados no mapa.
- Estilos visuais de jornadas.
- Exportação simples de jornada.
- Mapa em **Mapbox** ou provedor nativo (o consumo de `GET /map` já está feito).
- Paridade do app Expo com o Flutter (falta Perfil e Configurações).

## V3
- Jornadas compartilhadas.
- Marcar pessoas / conexões humanas.
- Música associada à memória.
- Áudio ambiente.

## V4
- Exportação PDF premium.
- Atlas digital e impressão física.
- Pôsteres de jornada.

## V5
- IA para organizar memórias.
- IA para sugerir títulos.
- IA para gerar narrativa da jornada.
- Documentários visuais automáticos.

## Fora do escopo agora
Feed social, likes, comentários, algoritmo de recomendação, monetização, marketplace e
realtime complexo.
