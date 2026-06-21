import { StyleSheet } from "react-native";

import { colors, serif } from "./colors";

// Estilos compartilhados pelas telas de autenticação.
export const ui = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.paper },

  // "Folha" de papel que sobe por cima da cena (cantos arredondados + sombra).
  body: {
    flex: 1,
    backgroundColor: colors.paper,
    marginTop: -26,
    borderTopLeftRadius: 28,
    borderTopRightRadius: 28,
    paddingHorizontal: 28,
    paddingTop: 30,
    shadowColor: "#3A2A12",
    shadowOffset: { width: 0, height: -4 },
    shadowOpacity: 0.12,
    shadowRadius: 10,
    elevation: 8,
  },

  brandRow: { flexDirection: "row", alignItems: "center", gap: 9 },
  pin: { width: 12, height: 12, borderRadius: 6, backgroundColor: colors.terra },
  wordmark: { fontFamily: serif, fontSize: 29, color: colors.ink, letterSpacing: 0.3 },
  tagline: { fontFamily: serif, fontStyle: "italic", fontSize: 14.5, color: colors.inkSoft, marginTop: 6 },

  title: { fontFamily: serif, fontSize: 27, color: colors.ink },
  subtitle: { color: colors.inkSoft, fontSize: 14, marginTop: 5, lineHeight: 21 },

  label: { fontSize: 11, letterSpacing: 1.2, color: colors.inkSoft, marginTop: 18, marginBottom: 7 },
  input: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: "rgba(35,39,47,0.18)",
    borderRadius: 12,
    paddingHorizontal: 15,
    paddingVertical: 13,
    fontSize: 15,
    color: colors.ink,
  },
  hint: { fontSize: 12, color: colors.inkSoft, marginTop: 6 },

  forgotWrap: { alignSelf: "flex-end", marginTop: 12 },
  forgot: { color: colors.teal, fontSize: 13, fontWeight: "500" },

  button: {
    backgroundColor: colors.terra,
    borderRadius: 12,
    paddingVertical: 15,
    alignItems: "center",
    marginTop: 24,
    shadowColor: colors.terraDeep,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 4,
  },
  buttonPressed: { opacity: 0.9, transform: [{ scale: 0.99 }] },
  buttonText: { color: "#FBF6E8", fontSize: 16, fontWeight: "600", letterSpacing: 0.4 },

  footerRow: { flexDirection: "row", justifyContent: "center", marginTop: 24 },
  footerText: { color: colors.inkSoft, fontSize: 14 },
  footerLink: { color: colors.terra, fontSize: 14, fontWeight: "600" },

  backWrap: { marginTop: 26, alignItems: "center" },
  back: { color: colors.ink, fontSize: 14, fontWeight: "500" },
});
