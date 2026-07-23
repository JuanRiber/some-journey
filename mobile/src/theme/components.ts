import { StyleSheet } from "react-native";

import {
  elevation,
  fonts,
  radius,
  space,
  type,
  type SJScheme,
} from "./tokens";

/**
 * Some Journey — fábricas de estilo dos componentes (Expo).
 *
 * Espelha os componentes do design system em Flutter (button primary/secondary/
 * text, input, card + photo card, chip, badge, sheet, fab, overline,
 * sectionHeader, emptyState). Cada bloco DERIVA dos tokens (`tokens.ts`) e do
 * esquema ATIVO (claro "papel quente" ou escuro "atlas noturno"), nunca de cor
 * ou tamanho solto — trocar de modo repinta tudo automaticamente.
 *
 * Por que uma FÁBRICA (e não um `StyleSheet.create` estático)? Porque as cores
 * dependem do modo. `makeComponentStyles(scheme)` recebe o esquema e devolve um
 * `StyleSheet.create` pronto. Como `sjLight`/`sjDark` são singletons `const`, um
 * cache por identidade evita recriar folhas a cada render (ver `componentStyles`).
 *
 * Regras de forma (do doc 08): botões/chips/badge/fab em pílula; card raio lg;
 * input raio md; sheet raio xl. Toque ≥ 44pt. Sombras extremamente suaves (e1/e2).
 */

/**
 * Converte um token hex (#RRGGBB) em rgba com alfa — usado para fundos TONAIS
 * (chip a 16% do acento) que os tokens não guardam prontos. Só recebe hex sólido
 * (accent/primary); tokens que já são rgba (ex.: `line`) não passam por aqui.
 */
function hexToRgba(hex: string, alpha: number): string {
  const h = hex.replace("#", "");
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

export function makeComponentStyles(s: SJScheme) {
  // Texto que fica SOBRE `accent` (badge). No claro o acento é couro escuro →
  // texto claro; no escuro o acento é ouro claro → texto escuro. Garante
  // contraste em ambos os modos sem escrever cor solta.
  const onAccent = s.brightness === "dark" ? s.bgDeep : s.surface;

  return StyleSheet.create({
    // ——— Superfícies de tela (conveniência) ———
    screen: { flex: 1, backgroundColor: s.bg },
    surface: { backgroundColor: s.surface },

    // ——— Botão PRIMÁRIO: preenchido vinho, label mono caixa alta ———
    buttonPrimary: {
      minHeight: 48, // toque confortável (> 44pt)
      backgroundColor: s.primary,
      borderRadius: radius.pill,
      paddingHorizontal: space.x6,
      paddingVertical: space.x3,
      flexDirection: "row",
      alignItems: "center",
      justifyContent: "center",
      gap: space.x2,
    },
    // Sem cor derivada em runtime: o "afundar" é uma leve perda de opacidade.
    buttonPrimaryPressed: { opacity: 0.88 },
    buttonPrimaryLabel: {
      fontFamily: fonts.mono,
      color: s.onPrimary,
      fontSize: type.overline.fontSize + 2, // 13: um pouco acima da overline
      fontWeight: "700",
      letterSpacing: type.overline.letterSpacing,
      textTransform: "uppercase",
    },

    // ——— Botão SECUNDÁRIO: contorno tonal, mesma tipografia mono ———
    buttonSecondary: {
      minHeight: 48,
      backgroundColor: "transparent",
      borderWidth: 1.5,
      borderColor: s.primary,
      borderRadius: radius.pill,
      paddingHorizontal: space.x6,
      paddingVertical: space.x3,
      flexDirection: "row",
      alignItems: "center",
      justifyContent: "center",
      gap: space.x2,
    },
    buttonSecondaryPressed: { backgroundColor: hexToRgba(s.primary, 0.1) },
    buttonSecondaryLabel: {
      fontFamily: fonts.mono,
      color: s.primary,
      fontSize: type.overline.fontSize + 2,
      fontWeight: "700",
      letterSpacing: type.overline.letterSpacing,
      textTransform: "uppercase",
    },

    // ——— Botão de TEXTO (link): sem caixa, cor do secundário ———
    buttonText: {
      minHeight: 44,
      paddingHorizontal: space.x2,
      alignItems: "center",
      justifyContent: "center",
    },
    buttonTextPressed: { opacity: 0.6 },
    buttonTextLabel: {
      fontFamily: fonts.sans,
      color: s.secondary,
      fontSize: type.body.fontSize,
      fontWeight: "600",
    },

    // ——— Input: preenchido surfaceAlt, hairline, foco = secondary ———
    inputLabel: {
      fontFamily: fonts.mono,
      fontSize: type.overline.fontSize,
      lineHeight: type.overline.lineHeight,
      letterSpacing: type.overline.letterSpacing,
      textTransform: "uppercase",
      color: s.accent, // overline mono do acento (couro/ouro)
      marginBottom: space.x2,
    },
    input: {
      minHeight: 48,
      backgroundColor: s.surfaceAlt,
      borderWidth: 1,
      borderColor: s.line, // hairline suave, sem borda dura
      borderRadius: radius.md,
      paddingHorizontal: space.x4,
      paddingVertical: space.x3,
      fontSize: type.body.fontSize,
      color: s.ink,
    },
    inputFocused: {
      borderColor: s.secondary,
      borderWidth: 1.5, // foco marcado sem "saltar" o layout muito
    },
    inputHint: {
      fontFamily: fonts.sans,
      fontSize: type.caption.fontSize,
      lineHeight: type.caption.lineHeight,
      color: s.inkSoft,
      marginTop: space.x2,
    },

    // ——— Card = página de diário: surface, raio lg, e1, muito respiro ———
    card: {
      backgroundColor: s.surface,
      borderRadius: radius.lg,
      padding: space.x5,
      ...elevation.e1(s),
    },
    // Variante foto-protagonista: imagem sangra no topo, texto complementa embaixo.
    photoCard: {
      backgroundColor: s.surface,
      borderRadius: radius.lg,
      overflow: "hidden", // recorta a foto nos cantos do card
      ...elevation.e1(s),
    },
    photoCardImage: {
      width: "100%",
      aspectRatio: 4 / 3,
      backgroundColor: s.surfaceAlt, // campo enquanto a foto carrega
    },
    photoCardBody: {
      padding: space.x4,
      gap: space.x2,
    },
    photoCardTitle: {
      fontFamily: fonts.serif,
      fontSize: type.title.fontSize,
      lineHeight: type.title.lineHeight,
      color: s.ink,
    },
    photoCardMeta: {
      fontFamily: fonts.sans,
      fontSize: type.bodySm.fontSize,
      lineHeight: type.bodySm.lineHeight,
      color: s.inkSoft,
    },

    // ——— Chip: fundo tonal do acento (16%), label sans ———
    chip: {
      alignSelf: "flex-start",
      flexDirection: "row",
      alignItems: "center",
      gap: space.x1,
      backgroundColor: hexToRgba(s.accent, 0.16),
      borderRadius: radius.pill,
      paddingHorizontal: space.x3,
      paddingVertical: space.x1,
    },
    chipLabel: {
      fontFamily: fonts.sans,
      fontSize: type.caption.fontSize,
      lineHeight: type.caption.lineHeight,
      color: s.accent,
      fontWeight: "600",
    },

    // ——— Badge: fundo do acento + texto contrastante, mono caixa alta ———
    badge: {
      alignSelf: "flex-start",
      backgroundColor: s.accent,
      borderRadius: radius.sm,
      paddingHorizontal: space.x2,
      paddingVertical: 2,
    },
    badgeLabel: {
      fontFamily: fonts.mono,
      fontSize: type.overline.fontSize,
      lineHeight: type.overline.lineHeight,
      letterSpacing: type.overline.letterSpacing,
      textTransform: "uppercase",
      color: onAccent,
      fontWeight: "700",
    },

    // ——— Bottom sheet: surface, topo raio xl, grabber, e2 ———
    sheet: {
      backgroundColor: s.surface,
      borderTopLeftRadius: radius.xl,
      borderTopRightRadius: radius.xl,
      paddingHorizontal: space.x6,
      paddingTop: space.x3,
      paddingBottom: space.x8,
      ...elevation.e2(s),
    },
    sheetGrabber: {
      width: 40,
      height: 4,
      borderRadius: radius.pill,
      backgroundColor: s.inkFaint,
      alignSelf: "center",
      marginBottom: space.x4,
    },

    // ——— FAB: primary, e2 (posicionamento fica a cargo da tela) ———
    fab: {
      width: 56,
      height: 56,
      borderRadius: radius.pill,
      backgroundColor: s.primary,
      alignItems: "center",
      justifyContent: "center",
      ...elevation.e2(s),
    },
    fabIcon: {
      color: s.onPrimary,
      fontSize: 26,
      lineHeight: 28,
      fontWeight: "600",
    },

    // ——— Overline: mono caixa alta do acento — "01 / TÍTULO" ———
    overline: {
      fontFamily: fonts.mono,
      fontSize: type.overline.fontSize,
      lineHeight: type.overline.lineHeight,
      letterSpacing: type.overline.letterSpacing,
      textTransform: "uppercase",
      color: s.accent,
    },

    // ——— Section header: overline + título serifa, com respiro ———
    sectionHeader: {
      gap: space.x1,
      marginBottom: space.x3,
    },
    sectionTitle: {
      fontFamily: fonts.serif,
      fontSize: type.h2.fontSize,
      lineHeight: type.h2.lineHeight,
      color: s.ink,
    },

    // ——— Empty state: ilustração + título serifa + corpo + 1 ação ———
    // NUNCA "Nenhum resultado" — ensina o próximo passo (a ação usa buttonPrimary).
    emptyState: {
      alignItems: "center",
      paddingHorizontal: space.x6,
      paddingVertical: space.x10,
      gap: space.x3,
    },
    emptyStateTitle: {
      fontFamily: fonts.serif,
      fontSize: type.h2.fontSize,
      lineHeight: type.h2.lineHeight,
      color: s.ink,
      textAlign: "center",
    },
    emptyStateBody: {
      fontFamily: fonts.sans,
      fontSize: type.body.fontSize,
      lineHeight: type.body.lineHeight,
      color: s.inkSoft,
      textAlign: "center",
    },
  });
}

export type ComponentStyles = ReturnType<typeof makeComponentStyles>;

// Cache por identidade do esquema: como `sjLight`/`sjDark` são singletons, a
// mesma folha é reaproveitada entre renders (evita `StyleSheet.create` repetido).
const cache = new Map<SJScheme, ComponentStyles>();

/** Folha de componentes do esquema, memoizada por identidade. */
export function componentStyles(scheme: SJScheme): ComponentStyles {
  const hit = cache.get(scheme);
  if (hit) return hit;
  const made = makeComponentStyles(scheme);
  cache.set(scheme, made);
  return made;
}
