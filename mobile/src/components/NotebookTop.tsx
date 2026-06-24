import { StyleSheet, View } from "react-native";

import { colors } from "../theme/colors";

// Chrome de "caderno de viagem": a faixa de espiral no topo da página.
// Desenhada só com Views (sem SVG) — confiável no web e no nativo.
// Reaproveitada por Timeline e Nova memória.
export default function NotebookTop() {
  return (
    <View style={s.wrap}>
      {Array.from({ length: 8 }).map((_, i) => (
        <View key={i} style={s.ring} />
      ))}
    </View>
  );
}

const s = StyleSheet.create({
  wrap: {
    flexDirection: "row",
    justifyContent: "space-around",
    alignItems: "center",
    height: 30,
    paddingTop: 16,
    paddingHorizontal: 22,
    backgroundColor: colors.pageBg,
  },
  ring: {
    width: 16,
    height: 16,
    borderRadius: 8,
    borderWidth: 2,
    borderColor: "rgba(35,39,47,0.32)",
    backgroundColor: "transparent",
  },
});
