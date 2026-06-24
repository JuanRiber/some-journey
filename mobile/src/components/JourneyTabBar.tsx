import { Pressable, StyleSheet, Text, View } from "react-native";
import { router, usePathname } from "expo-router";

import { colors } from "../theme/colors";

// Ícones desenhados com Views (sem SVG, por consistência com JourneyHeader).
function ClockIcon({ color }: { color: string }) {
  return (
    <View style={[ic.ring, { borderColor: color }]}>
      <View style={[ic.handV, { backgroundColor: color }]} />
      <View style={[ic.handH, { backgroundColor: color }]} />
    </View>
  );
}

function TargetIcon({ color }: { color: string }) {
  return (
    <View style={[ic.ring, { borderColor: color }]}>
      <View style={[ic.inner, { borderColor: color }]} />
      <View style={[ic.dot, { backgroundColor: color }]} />
    </View>
  );
}

// Barra inferior do app: Tempo (timeline) · Criar (ação central) · Atlas (mapa).
// "Criar" não é uma aba — é um atalho que empilha a tela de nova memória.
// usePathname() define a aba ativa (cada aba derivada do seu próprio prefixo, para
// nenhuma acender por engano numa rota futura). Troca de aba via router.navigate
// (idiomático no expo-router Tabs; dedupe na rota atual). Safe-area de aparelhos
// com notch fica para um refinamento futuro (web, alvo atual, não precisa).
export default function JourneyTabBar() {
  const path = usePathname();
  const onTimeline = path.startsWith("/timeline");
  const onAtlas = path.startsWith("/atlas");

  return (
    <View style={s.bar}>
      <Pressable
        style={s.tab}
        onPress={() => router.navigate("/timeline")}
        hitSlop={8}
        accessibilityRole="button"
        accessibilityLabel="Tempo"
        accessibilityState={{ selected: onTimeline }}
      >
        <ClockIcon color={onTimeline ? colors.terra : colors.inkSoft} />
        <Text style={[s.label, onTimeline && s.labelActive]}>Tempo</Text>
      </Pressable>

      <Pressable
        style={s.criar}
        onPress={() => router.push("/memory-new")}
        hitSlop={8}
        accessibilityRole="button"
        accessibilityLabel="Criar memória"
      >
        <View style={s.plusV} />
        <View style={s.plusH} />
      </Pressable>

      <Pressable
        style={s.tab}
        onPress={() => router.navigate("/atlas")}
        hitSlop={8}
        accessibilityRole="button"
        accessibilityLabel="Atlas"
        accessibilityState={{ selected: onAtlas }}
      >
        <TargetIcon color={onAtlas ? colors.terra : colors.inkSoft} />
        <Text style={[s.label, onAtlas && s.labelActive]}>Atlas</Text>
      </Pressable>
    </View>
  );
}

const s = StyleSheet.create({
  bar: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-around",
    backgroundColor: colors.card,
    borderTopWidth: 1,
    borderTopColor: colors.line,
    paddingTop: 10,
    paddingBottom: 16,
    paddingHorizontal: 24,
  },
  tab: { alignItems: "center", gap: 4, minWidth: 64 },
  label: { fontSize: 11, color: colors.inkSoft, letterSpacing: 0.3 },
  labelActive: { color: colors.terra, fontWeight: "600" },
  criar: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: colors.terra,
    alignItems: "center",
    justifyContent: "center",
    marginTop: -22,
    shadowColor: colors.terraDeep,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.35,
    shadowRadius: 8,
    elevation: 6,
  },
  plusV: { position: "absolute", width: 3, height: 20, borderRadius: 2, backgroundColor: colors.card },
  plusH: { position: "absolute", width: 20, height: 3, borderRadius: 2, backgroundColor: colors.card },
});

const ic = StyleSheet.create({
  ring: { width: 22, height: 22, borderRadius: 11, borderWidth: 2, alignItems: "center", justifyContent: "center" },
  handV: { position: "absolute", width: 2, height: 6, top: 3, left: 8, borderRadius: 1 },
  handH: { position: "absolute", width: 6, height: 2, top: 8, left: 9, borderRadius: 1 },
  inner: { width: 11, height: 11, borderRadius: 6, borderWidth: 2 },
  dot: { position: "absolute", width: 4, height: 4, borderRadius: 2 },
});
