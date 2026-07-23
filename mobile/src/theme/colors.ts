import { fonts, sjDark } from "./tokens";

/**
 * COMPATIBILIDADE — não use em código novo.
 *
 * Este módulo existia antes do design system tokenizado (`tokens.ts` +
 * `ThemeProvider`). As telas legadas importam `{ colors, serif, mono }` daqui,
 * então mantemos a superfície pública intacta para nada quebrar durante a
 * migração. A DIFERENÇA: `colors` deixou de ser uma paleta escrita à mão e
 * passou a ser DERIVADA do `sjDark` (o "atlas noturno" — que já era, valor a
 * valor, a paleta que estas telas usavam). Assim existe uma só fonte de verdade;
 * quando a última tela migrar para `useTheme()`/`tokens`, este arquivo some.
 *
 * ➜ CÓDIGO NOVO: use `useTheme()` (claro/escuro reativo) e os tokens de
 *   `tokens.ts`, nunca estas constantes fixas no modo escuro.
 */
export const colors = {
  // Neutros — mapeados 1:1 nos papéis semânticos do esquema escuro.
  pageBg: sjDark.bgDeep, // navy mais fundo (atrás de tudo, barras)
  paper: sjDark.bg, // navy da landing: superfície principal
  card: sjDark.surface, // superfície elevada dos cards
  ink: sjDark.ink, // creme quente: texto principal
  inkSoft: sjDark.inkSoft,
  frame: sjDark.frame, // moldura dourada envelhecida
  // Acentos.
  gold: sjDark.accent, // ouro: molduras, overlines, numerais
  // Tons profundos SEM equivalente no esquema (gravuras/estados premidos);
  // ficam como literais até virarem tokens próprios, se necessário.
  goldDeep: "#B88930",
  wine: sjDark.primary, // vinho: ação, jornadas, rastros
  wineDeep: "#8A2740",
  cyan: sjDark.secondary, // ciano: links, pontos soltos (o secundário)
  cyanDeep: "#12707E",
  bloom: sjDark.highlight, // ouro suave dos itálicos afetivos
  // Campos noturnos (placeholders de mapa/foto, capas sem imagem).
  sand: sjDark.surface,
  placeholder: sjDark.inkFaint,
  line: sjDark.line,
  danger: sjDark.danger,
  cover: sjDark.surface,
  // Fundo dos chips (atmosfera, período): vinho muito leve, derivado do
  // `primary` (#B7314F) a 16%.
  chip: "rgba(183,49,79,0.16)",
};

// Serifa editorial da landing (títulos, memórias, itálicos) e mono das
// overlines/botões — reexportadas dos tokens para manter um só ponto de troca.
export const serif = fonts.serif;
export const mono = fonts.mono;
