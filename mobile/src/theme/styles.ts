import { StyleSheet } from "react-native";

import { colors, mono, serif } from "./colors";

// Estilos compartilhados pelas telas de autenticação — a linguagem da landing:
// navy profundo, títulos em serifa creme, overlines/botões em mono, dourado
// como cor de ação.
export const ui = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.paper },

  body: {
    flex: 1,
    backgroundColor: colors.paper,
    paddingHorizontal: 28,
    paddingTop: 26,
  },

  brandRow: { flexDirection: "row", alignItems: "center", gap: 10 },
  pin: { width: 10, height: 10, borderRadius: 5, backgroundColor: colors.coral },
  // O wordmark da landing: serifa itálica dourada.
  wordmark: { fontFamily: serif, fontStyle: "italic", fontSize: 32, color: colors.gold },
  tagline: { fontFamily: serif, fontStyle: "italic", fontSize: 15, color: colors.inkSoft, marginTop: 6 },

  title: { fontFamily: serif, fontSize: 28, color: colors.ink },
  subtitle: { fontFamily: serif, fontStyle: "italic", color: colors.inkSoft, fontSize: 14.5, marginTop: 6, lineHeight: 21 },

  // Overline mono dourada, como o "03 / OS MOMENTOS" da landing.
  label: { fontFamily: mono, fontSize: 11, letterSpacing: 1.6, color: colors.bloom, marginTop: 20, marginBottom: 7 },
  input: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: "rgba(242,234,216,0.16)",
    borderRadius: 8,
    paddingHorizontal: 15,
    paddingVertical: 13,
    fontSize: 15,
    color: colors.ink,
  },
  hint: { fontSize: 12, color: colors.inkSoft, marginTop: 6 },

  forgotWrap: { alignSelf: "flex-end", marginTop: 12 },
  forgot: { color: colors.mint, fontSize: 13, fontWeight: "600" },

  // Botão da landing: dourado, texto navy em mono caixa alta.
  button: {
    backgroundColor: colors.gold,
    borderRadius: 8,
    paddingVertical: 15,
    alignItems: "center",
    marginTop: 26,
  },
  buttonPressed: { backgroundColor: colors.goldDeep },
  buttonText: {
    fontFamily: mono,
    color: colors.pageBg,
    fontSize: 13,
    fontWeight: "700",
    letterSpacing: 1.6,
    textTransform: "uppercase",
  },

  footerRow: { flexDirection: "row", justifyContent: "center", marginTop: 26 },
  footerText: { color: colors.inkSoft, fontSize: 14 },
  footerLink: { color: colors.gold, fontSize: 14, fontWeight: "700" },

  backWrap: { marginTop: 26, alignItems: "center" },
  back: { color: colors.ink, fontSize: 14, fontWeight: "500" },
});
