import { StyleSheet } from "react-native";

import { colors, serif } from "./colors";

// Estilos compartilhados pelas telas de autenticação.
export const ui = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.paper },
  header: { height: 200, backgroundColor: colors.sky, overflow: "hidden" },
  sun: {
    position: "absolute", top: 42, right: 46,
    width: 46, height: 46, borderRadius: 23, backgroundColor: colors.ochre,
  },
  hill: {
    position: "absolute", bottom: -44, left: -24, right: -24, height: 116,
    backgroundColor: colors.sage, borderTopLeftRadius: 130, borderTopRightRadius: 90,
  },
  body: { flex: 1, paddingHorizontal: 28, paddingTop: 24 },
  brandRow: { flexDirection: "row", alignItems: "center", gap: 9 },
  pin: { width: 13, height: 13, borderRadius: 7, backgroundColor: colors.terra },
  wordmark: { fontFamily: serif, fontSize: 27, color: colors.ink, letterSpacing: 0.4 },
  tagline: { fontFamily: serif, fontStyle: "italic", fontSize: 14, color: colors.inkSoft, marginTop: 6 },
  title: { fontFamily: serif, fontSize: 26, color: colors.ink },
  subtitle: { color: colors.inkSoft, fontSize: 14, marginTop: 4, lineHeight: 20 },
  label: { fontSize: 11, letterSpacing: 1, color: colors.inkSoft, marginTop: 18, marginBottom: 7 },
  input: {
    backgroundColor: colors.card, borderWidth: 1.5, borderColor: colors.ink,
    borderRadius: 11, paddingHorizontal: 14, paddingVertical: 12, fontSize: 15, color: colors.ink,
  },
  hint: { fontSize: 12, color: colors.inkSoft, marginTop: 6 },
  forgotWrap: { alignSelf: "flex-end", marginTop: 11 },
  forgot: { color: colors.teal, fontSize: 13, fontWeight: "500" },
  button: {
    backgroundColor: colors.terra, borderWidth: 1.5, borderColor: colors.terraDeep,
    borderRadius: 11, paddingVertical: 14, alignItems: "center", marginTop: 22,
  },
  buttonPressed: { opacity: 0.85 },
  buttonText: { color: colors.card, fontSize: 16, fontWeight: "500", letterSpacing: 0.3 },
  footerRow: { flexDirection: "row", justifyContent: "center", marginTop: 22 },
  footerText: { color: colors.inkSoft, fontSize: 14 },
  footerLink: { color: colors.terra, fontSize: 14, fontWeight: "500" },
  backWrap: { marginTop: 24, alignItems: "center" },
  back: { color: colors.ink, fontSize: 14, fontWeight: "500" },
});
