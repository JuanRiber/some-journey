import { StyleSheet, View } from "react-native";

import { colors } from "../theme/colors";

// Cena ligne claire feita só com Views (sem react-native-svg, que tem bug no
// build web): céu, sol com brilho, nuvens, colinas em camadas, ciprestes e um
// pin de lugar. Confiável em web e nativo.
export default function JourneyHeader() {
  return (
    <View style={s.sky}>
      <View style={[s.cloud, { top: 34, left: 30, width: 56, height: 15 }]} />
      <View style={[s.cloud, { top: 56, left: 56, width: 34, height: 11 }]} />
      <View style={[s.cloud, { top: 44, right: 98, width: 44, height: 13 }]} />

      <View style={s.sunRing} />
      <View style={s.sun} />

      <View style={s.hillBack} />
      <View style={s.hillFront} />

      <View style={[s.cypress, { left: 40, height: 44, bottom: 78 }]} />
      <View style={[s.cypress, { left: 62, height: 58, bottom: 74 }]} />
      <View style={[s.cypress, { left: 84, height: 38, bottom: 80 }]} />

      <View style={s.trail} />

      <View style={s.marker}>
        <View style={s.markerDot} />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  sky: { height: 220, backgroundColor: colors.sky, overflow: "hidden" },
  cloud: { position: "absolute", backgroundColor: "rgba(251,246,232,0.75)", borderRadius: 20 },
  sunRing: {
    position: "absolute", top: 30, right: 46, width: 62, height: 62,
    borderRadius: 31, backgroundColor: "rgba(224,169,58,0.30)",
  },
  sun: {
    position: "absolute", top: 41, right: 56, width: 40, height: 40,
    borderRadius: 20, backgroundColor: colors.ochre,
  },
  hillBack: {
    position: "absolute", bottom: -30, left: -30, right: -30, height: 120,
    backgroundColor: "#8C9A5A", borderTopLeftRadius: 140, borderTopRightRadius: 110,
  },
  hillFront: {
    position: "absolute", bottom: -52, left: -20, right: -40, height: 130,
    backgroundColor: colors.sage, borderTopLeftRadius: 120, borderTopRightRadius: 150,
  },
  cypress: {
    position: "absolute", width: 12, backgroundColor: "#566A30",
    borderTopLeftRadius: 6, borderTopRightRadius: 6,
    borderBottomLeftRadius: 4, borderBottomRightRadius: 4,
  },
  // trilha tracejada (borda dashed do CSS/RN), levando ao pin.
  trail: {
    position: "absolute", bottom: 60, right: 78, width: 140,
    borderTopWidth: 3, borderColor: "rgba(35,39,47,0.5)", borderStyle: "dashed",
    transform: [{ rotate: "-22deg" }],
  },
  marker: {
    position: "absolute", right: 66, bottom: 92, width: 22, height: 22, borderRadius: 11,
    backgroundColor: colors.terra, borderWidth: 1.5, borderColor: "#7A3517",
    alignItems: "center", justifyContent: "center",
  },
  markerDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: colors.card },
});
