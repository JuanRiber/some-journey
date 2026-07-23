# Design System — Some Journey

> "Sua vida contada através dos lugares." Um caderno de viagens elegante, não um CRUD.
> Fontes de verdade em CÓDIGO: `app_flutter/lib/design/tokens.dart` e
> `mobile/src/theme/tokens.ts` (valores idênticos). Este doc é a referência de
> **papéis, anatomia e princípios** — nunca escreva cor/tamanho solto numa tela.

## 1. Dois modos, uma linguagem

| | Claro — "papel quente" (PADRÃO) | Escuro — "atlas noturno" |
| --- | --- | --- |
| Sensação | diário de papel envelhecido, luz de dia | mapa noturno, luz de vela |
| Fundo (`bg`) | `#F5F0E6` creme | `#0D1524` navy |
| Tinta (`ink`) | `#2B2724` marrom quente | `#F3ECDC` creme |
| Ação (`primary`) | `#6E2C3A` vinho | `#B7314F` vinho vivo |
| Link (`secondary`) | `#2E6C7E` azul-lago | `#4FB3C7` ciano |
| Selo/overline (`accent`) | `#7A5A2E` couro | `#E3B04B` ouro |
| Natureza (`moss`) | `#3E5A47` | `#6BA583` |
| Era/quente (`highlight`) | `#B4762E` mostarda | `#D9A94E` |

O modo claro é o padrão; o escuro é uma alternância (respeita o sistema + toggle
manual persistido). Nada saturado — tudo orgânico.

## 2. Tipografia
- **Serifa** (Georgia → Fraunces quando embutir): display/h1/h2/títulos, conteúdo
  de memória, itálicos afetivos (tagline, datas, atmosfera).
- **Sans** (Inter/Manrope): interface — corpo, botões-não-mono, labels de campo.
- **Mono** (Menlo): overlines/selos/numerais em CAIXA ALTA com tracking 1.6 — o
  motivo "01 / OS MOMENTOS" da landing.
- Escala: display 34/40 · h1 28/34 · h2 22/28 · title 18/24 · body 16/24 ·
  bodySm 14/20 · caption 13/18 · overline 11/16. Muito contraste título↔corpo.

## 3. Grid, forma, profundidade
- Espaçamento base **4pt** (`space.x1..x16`); margem de tela `space.screenX = 24`.
- Raios: sm 6 · md 10 · lg 14 (cards) · xl 20 (sheets) · pill.
- Elevação: **sombras extremamente suaves** (`e1` card, `e2` flutuante). O app respira.

## 4. Movimento (com propósito)
Durações 120/220/360/420ms; curva padrão `cubic(.2,0,0,1)`. Cada animação
explica uma transição: foto que cresce, pin que cai (mola), linha que conecta,
hero na abertura da memória. Nunca enfeite. Sem confete.

## 5. Componentes (anatomia)
Todos derivam dos tokens; nenhum usa Material/genérico "cru".
- **Botões**: `primary` (preenchido vinho, texto `onPrimary`, label mono caixa
  alta), `secondary` (tonal/contorno), `text` (link). Toque ≥ 44pt.
- **Input**: preenchido `surfaceAlt`, hairline `line`, foco = `secondary` 1.5px,
  label overline mono `accent`. Sem borda dura.
- **Card = página de diário**: `surface`, raio lg, `e1`, muito respiro. Variante
  foto-protagonista: imagem sangra no topo, texto só complementa embaixo.
- **Chip**: fundo tonal do acento (16%), label sans/mono. **Badge**: fundo do
  acento + texto contrastante, mono caixa alta.
- **Bottom sheet**: `surface`, topo raio xl, grabber, `e2`. **FAB**: `primary`, `e2`.
- **Overline**: mono caixa alta `accent` — "01 / TÍTULO".
- **Empty state**: ilustração + título serifa + corpo suave + 1 ação primária.
  NUNCA "Nenhum resultado" — sempre ensina o próximo passo.

## 6. Ilustrações
Line-art minimalista (traço fino), tema: bússola, montanhas, trilha, sol/lua,
árvores. Estados: vazio, sem internet, sem memórias, primeira jornada, erro,
carregando. Coerentes com a paleta do modo ativo.

## 7. Checklist por tela (herda das regras de negócio)
Por que existe? · o que o usuário sente? · ação principal (máx 2–3)? · reduz
atrito? · surpreende? · foto protagonista? · estado vazio/erro/loading? ·
acessível (contraste, toque, leitor de tela, haptics)? · 60 FPS? · consistente
com o design system? · parece Apple/Airbnb?
