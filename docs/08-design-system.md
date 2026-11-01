# Design System — Some Journey

> "Sua vida contada através dos lugares." Um caderno de viagens elegante, não um CRUD.
> Fontes de verdade em CÓDIGO: `app_flutter/lib/design/tokens.dart` e
> do app Flutter. Este doc é a referência de
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
manual persistido em Configurações › Aparência). Nada saturado — tudo orgânico.

**Como o esquema chega na tela.** `themeMode` sozinho troca só o Material por
baixo. As telas leem `SJTheme.of(context)`, que cai num fallback CLARO quando
ninguém provê o esquema — e o app continuaria creme dentro de um tema escuro,
sem erro nenhum. Quem provê é o `builder` do `MaterialApp` (embrulha o
Navigator, então toda rota nasce certa, inclusive as translúcidas), com o
`schemeFor` do `SjThemeController`. Nunca pinte a partir de `sjLight`/`sjDark`
importados direto numa tela: a única exceção do app é texto sobre a foto de
marca no login.

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

**Cerimônia (900ms)** é o único degrau acima dessa escala, e tem regra própria:
as outras durações são de TRANSIÇÃO — o tempo é custo e o alvo é não ser
notado. Cerimônia é o contrário: a animação que o usuário deve ver acontecer,
porque ela é parte do que o produto está dizendo. Hoje tem um só dono, a
abertura do livro de cadastro. Não use para navegar.

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
- **Carimbo** (`SJSeal`) e **herbário** (`SJSprig`): os dois ornamentos de
  papel — selo de passaporte com ondas de cancelamento e legenda em arco, e o
  raminho prensado. Nascem em opacidade baixa, `ExcludeSemantics`, e SANGRANDO
  para fora da borda: ornamento que respeita a margem deixa de ser marca
  d'água e vira ilustração. São desenhados (não imagem) porque trocam de cor
  com o modo e quase sempre aparecem pela metade — um PNG precisaria de uma
  versão por recorte.
- **Livro** (`SJBook`): capa de couro com filete dourado e rosa dos ventos, e
  duas páginas em `surface` com o vinco da lombada. Anatomia: **a folha** — uma
  primitiva com frente, verso e dobra, que serve tanto à capa que abre quanto à
  página que vira. Telas ≥720pt mostram a folha dupla; abaixo disso, uma página
  por vez (duas páginas num celular dariam ~170pt cada, e campo nenhum cabe
  ali). O aberto tem teto de proporção **1,35:1** e a página solta **0,70:1** —
  sem teto, numa janela alta o livro vira um quadrado, e um quadrado lê como
  dois painéis, não como livro. Margem maior junto da lombada, como em livro
  impresso. Em repouso a folha não carrega matriz nenhuma — é o estado em que
  se digita, e perspectiva é transformação não afim: sob ela o `ensureVisible`
  que o foco do teclado dispara não converge. Primeiro uso: **criar conta** —
  obrigatórios à esquerda, opcionais à direita.

## 6. Ilustrações
Line-art minimalista (traço fino), tema: bússola, montanhas, trilha, sol/lua,
árvores. Estados: vazio, sem internet, sem memórias, primeira jornada, erro,
carregando. Coerentes com a paleta do modo ativo.

## 7. A porta (login) — composição de referência
Duas composições na mesma tela, e o corte é **900pt**:
- **Pôster** (≥900): a arte de marca sangra na tela inteira, um véu desce da
  esquerda (`shadow`, não `bgDeep` — creme sobre creme não escurece nada), a
  promessa fica sobre a foto e o formulário pousa à direita como um **cartão de
  papel** de largura fixa (430) com carimbo e herbário nos cantos. Sobre foto, a
  tinta é sempre a clara (`sjDark.ink`): é o único lugar do app onde a cor não
  vem do esquema ativo.
- **Coluna** (<900): a foto vira faixa no topo com o nome por cima, e o
  formulário desce no papel da própria página — sem cartão dentro de cartão. A
  barra fica compacta (só identidade).

O que o desenho pede e o produto ainda não tem aparece **desenhado e desligado**,
com "em breve" escrito (hoje: entrar com Google — o backend não tem OAuth). O
que não existe mesmo não aparece: link morto na primeira tela é promessa
quebrada no primeiro toque.

## 8. Checklist por tela (herda das regras de negócio)
Por que existe? · o que o usuário sente? · ação principal (máx 2–3)? · reduz
atrito? · surpreende? · foto protagonista? · estado vazio/erro/loading? ·
acessível (contraste, toque, leitor de tela, haptics)? · 60 FPS? · consistente
com o design system? · parece Apple/Airbnb?
