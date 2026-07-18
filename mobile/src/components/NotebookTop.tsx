import { StyleSheet, View } from "react-native";

import { colors } from "../theme/colors";

// Régua editorial do topo: uma linha creme suave sobre uma faixa dourada,
// como as réguas da landing. Reaproveitada por Timeline e Nova memória.
export default function NotebookTop() {
  return (
    <View style={s.wrap}>
      <View style={s.rule} />
      <View style={s.gold} />
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { paddingTop: 54, backgroundColor: colors.paper },
  rule: { height: 1.5, backgroundColor: "rgba(242,234,216,0.30)", marginHorizontal: 24 },
  gold: { height: 5, backgroundColor: colors.gold, marginHorizontal: 24, marginTop: 3 },
});
