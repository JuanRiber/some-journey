# Roadmap

Legenda: ✅ feito · 🟡 parcial · ⬜ a fazer. (Progresso detalhado no [`changelog.md`](changelog.md).)

## MVP
- ✅ Login / cadastro (JWT).
- 🟡 Mapa nativo interativo — Leaflet/OSM no **web** (pronto); no **nativo**, implementado via WebView + Leaflet, aguardando validação em device (Expo Go).
- ✅ Criar memória geolocalizada.
- ✅ Visualizar pins (`GET /map`).
- ✅ Timeline simples.
- ✅ Criar jornada simples (com ciclo `draft/active/paused/finished`).
- ✅ Associar pontos a jornadas (existentes e novos) + reordenar.
- ✅ Desenhar rastro no mapa (LineString).
- ✅ Upload de uma foto por memória — funcional com Supabase Storage (upload, URL assinada e delete validados de ponta a ponta).

## V2
- Múltiplas fotos por memória.
- Fases da vida.
- Filtros avançados no mapa.
- Estilos visuais de jornadas.
- Exportação simples de jornada.
- Mapa nativo (Mapbox ou provedor nativo) consumindo `GET /map`.

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
