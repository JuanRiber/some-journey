import { Platform } from "react-native";

/**
 * Some Journey — Design Tokens (fonte única da verdade, espelha
 * app_flutter/lib/design/tokens.dart valor a valor).
 *
 * Dois modos, uma linguagem:
 * - Claro = "papel quente" (PADRÃO): creme/off-white, tinta marrom quente,
 *   vinho como ação, azul-lago, couro/mostarda, musgo.
 * - Escuro = "atlas noturno": navy profundo, creme como tinta, vinho/ciano
 *   vivos, ouro nas molduras (a identidade da landing).
 *
 * Nada saturado; contraste de texto mirando WCAG AA (4.5:1 no corpo).
 */

export type SJScheme = {
  brightness: "light" | "dark";
  // Neutros
  bgDeep: string;
  bg: string;
  surface: string;
  surfaceAlt: string;
  ink: string;
  inkSoft: string;
  inkFaint: string;
  line: string;
  frame: string;
  // Acentos (papéis)
  primary: string;
  onPrimary: string;
  secondary: string;
  accent: string;
  moss: string;
  highlight: string;
  danger: string;
  shadow: string;
};

// Modo CLARO — "papel quente" (padrão).
export const sjLight: SJScheme = {
  brightness: "light",
  bgDeep: "#ECE3D2",
  bg: "#F5F0E6",
  surface: "#FBF8F1",
  surfaceAlt: "#EFE7D7",
  ink: "#2B2724",
  inkSoft: "#6E6353",
  inkFaint: "#9C917E",
  line: "rgba(43,39,36,0.10)",
  frame: "#C4AE86",
  primary: "#6E2C3A",
  onPrimary: "#F7F1E7",
  secondary: "#2E6C7E",
  accent: "#7A5A2E",
  moss: "#3E5A47",
  highlight: "#B4762E",
  danger: "#A6392C",
  shadow: "#2B2724",
};

// Modo ESCURO — "atlas noturno".
export const sjDark: SJScheme = {
  brightness: "dark",
  bgDeep: "#080D18",
  bg: "#0D1524",
  surface: "#16213A",
  surfaceAlt: "#1B2740",
  ink: "#F3ECDC",
  inkSoft: "#9AA3B8",
  inkFaint: "#6B7488",
  line: "rgba(243,236,220,0.12)",
  frame: "#8C7440",
  primary: "#B7314F",
  onPrimary: "#F3ECDC",
  secondary: "#4FB3C7",
  accent: "#E3B04B",
  moss: "#6BA583",
  highlight: "#D9A94E",
  danger: "#E4604E",
  shadow: "#000000",
};

export const schemes = { light: sjLight, dark: sjDark };

// Famílias tipográficas (fonte própria Inter/Fraunces entram como polimento;
// estes nomes são o ponto único de troca).
export const fonts = {
  serif: Platform.select({
    web: "Georgia, 'Times New Roman', serif",
    ios: "Georgia",
    default: "serif",
  }) as string,
  sans: Platform.select({
    web: "Inter, -apple-system, 'Segoe UI', Roboto, sans-serif",
    ios: "System",
    default: "sans-serif",
  }) as string,
  mono: Platform.select({
    web: "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",
    ios: "Menlo",
    default: "monospace",
  }) as string,
};

// Escala tipográfica (size / lineHeight).
export const type = {
  display: { fontSize: 34, lineHeight: 40 },
  h1: { fontSize: 28, lineHeight: 34 },
  h2: { fontSize: 22, lineHeight: 28 },
  title: { fontSize: 18, lineHeight: 24 },
  body: { fontSize: 16, lineHeight: 24 },
  bodySm: { fontSize: 14, lineHeight: 20 },
  caption: { fontSize: 13, lineHeight: 18 },
  overline: { fontSize: 11, lineHeight: 16, letterSpacing: 1.6 },
} as const;

// Espaçamento base 4pt.
export const space = {
  x1: 4, x2: 8, x3: 12, x4: 16, x5: 20, x6: 24, x8: 32, x10: 40, x12: 48, x16: 64,
  screenX: 24,
} as const;

// Escala de bordas.
export const radius = { sm: 6, md: 10, lg: 14, xl: 20, pill: 999 } as const;

// Movimento (ms + curvas Bézier).
export const motion = {
  fast: 120,
  base: 220,
  slow: 360,
  page: 420,
  standard: [0.2, 0, 0, 1] as const,
  enter: [0.05, 0.7, 0.1, 1] as const,
  exit: [0.3, 0, 0.8, 0.15] as const,
};

// Sombras extremamente suaves (RN shadow + web boxShadow ficam a cargo dos
// componentes; aqui vão os parâmetros por modo).
export const elevation = {
  e1: (s: SJScheme) => ({
    shadowColor: s.shadow,
    shadowOpacity: s.brightness === "dark" ? 0.4 : 0.06,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 4 },
    elevation: 2,
  }),
  e2: (s: SJScheme) => ({
    shadowColor: s.shadow,
    shadowOpacity: s.brightness === "dark" ? 0.52 : 0.1,
    shadowRadius: 30,
    shadowOffset: { width: 0, height: 12 },
    elevation: 8,
  }),
};
