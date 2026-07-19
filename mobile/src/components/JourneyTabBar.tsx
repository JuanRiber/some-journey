import { Pressable, StyleSheet, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
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
  const insets = useSafeAreaInsets();
  const onTimeline = path.startsWith("/timeline");
  const onAtlas = path.startsWith("/atlas");

  return (
    <View style={[s.bar, { paddingBottom: 12 + insets.bottom }]}>
      <Pressable
        style={s.tab}
        onPress={() => router.navigate("/timeline")}
        hitSlop={8}
        accessibilityRole="button"
        accessibilityLabel="Tempo"
        accessibilityState={{ selected: onTimeline }}
      >
        <ClockIcon color={onTimeline ? colors.wine : colors.inkSoft} />
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
        <TargetIcon color={onAtlas ? colors.wine : colors.inkSoft} />
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
    paddingHorizontal: 24,
  },
  tab: { alignItems: "center", gap: 4, minWidth: 64 },
  label: { fontSize: 10, color: colors.inkSoft, letterSpacing: 1.2, fontWeight: "600", textTransform: "uppercase" },
  labelActive: { color: colors.cyan, fontWeight: "800" },
  criar: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: colors.wine,
    borderWidth: 2,
    borderColor: colors.wineDeep,
    alignItems: "center",
    justifyContent: "center",
    marginTop: -22,
  },
  plusV: { position: "absolute", width: 3, height: 20, borderRadius: 2, backgroundColor: colors.ink },
  plusH: { position: "absolute", width: 20, height: 3, borderRadius: 2, backgroundColor: colors.ink },
});

const ic = StyleSheet.create({
  ring: { width: 22, height: 22, borderRadius: 11, borderWidth: 2, alignItems: "center", justifyContent: "center" },
  handV: { position: "absolute", width: 2, height: 6, top: 3, left: 8, borderRadius: 1 },
  handH: { position: "absolute", width: 6, height: 2, top: 8, left: 9, borderRadius: 1 },
  inner: { width: 11, height: 11, borderRadius: 6, borderWidth: 2 },
  dot: { position: "absolute", width: 4, height: 4, borderRadius: 2 },
});
