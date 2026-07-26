import { fonts, sjLight } from "./tokens";

/**
 * COMPATIBILIDADE — não use em código novo.
 *
 * Este módulo existia antes do design system tokenizado (`tokens.ts` +
 * `ThemeProvider`). As telas legadas importam `{ colors, serif, mono }` daqui,
 * então mantemos a superfície pública intacta para nada quebrar durante a
 * migração — mas os VALORES agora vêm do `sjLight`, o "papel quente" que é o
 * modo PADRÃO do produto (o app Flutter fez o mesmo em lib/theme.dart). Assim os
 * dois front-ends respiram a mesma paleta sem reescrever cada tela, e existe uma
 * só fonte de verdade.
 *
 * ➜ CÓDIGO NOVO: use `useTheme()` (claro/escuro reativo) e os tokens de
 *   `tokens.ts`, nunca estas constantes fixas num único modo.
 */
export const colors = {
  // Neutros — mapeados 1:1 nos papéis semânticos do esquema claro.
  pageBg: sjLight.bgDeep, // creme recuado (atrás de tudo, barras)
  paper: sjLight.bg, // creme papel: superfície principal
  card: sjLight.surface, // off-white: superfície elevada dos cards
  ink: sjLight.ink, // marrom quente: texto principal
  inkSoft: sjLight.inkSoft,
  frame: sjLight.frame, // moldura couro claro
  // Acentos.
  gold: sjLight.accent, // couro: molduras, overlines, numerais
  goldDeep: "#5E4522", // couro escurecido (estados premidos/gravuras)
  wine: sjLight.primary, // vinho: ação, jornadas, rastros
  wineDeep: "#57222D",
  cyan: sjLight.secondary, // azul-lago: links, pontos soltos (o secundário)
  cyanDeep: "#224E5B",
  bloom: sjLight.highlight, // mostarda dos itálicos afetivos
  // Campos de papel (placeholders de mapa/foto, capas sem imagem).
  sand: sjLight.surfaceAlt,
  placeholder: sjLight.inkFaint,
  line: sjLight.line,
  danger: sjLight.danger,
  cover: sjLight.surfaceAlt,
  // Fundo dos chips (atmosfera, período): vinho muito leve, derivado do
  // `primary` (#6E2C3A) a ~12%.
  chip: "rgba(110,44,58,0.12)",
};

// Serifa editorial (títulos, memórias, itálicos) e mono das overlines/botões —
// reexportadas dos tokens para manter um só ponto de troca.
export const serif = fonts.serif;
export const mono = fonts.mono;
