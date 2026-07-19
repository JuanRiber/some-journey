import { useCallback, useState } from "react";
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { router, useFocusEffect, type Href } from "expo-router";

import AtlasMap from "../../components/AtlasMap";
import * as api from "../../lib/api";
import { clearToken } from "../../lib/auth";
import { colors, mono, serif } from "../../theme/colors";

// Atlas (aba padrão pós-login): o mapa vivo do usuário — pins soltos (teal),
// pins de jornada (terra) e os rastros. Dados de GET /map; tocar num pin abre
// o detalhe da memória.
export default function AtlasScreen() {
  const [map, setMap] = useState<api.MapResponse | null>(null);
  const [error, setError] = useState("");

  useFocusEffect(
    useCallback(() => {
      let active = true;
      setError("");
      api
        .getMap()
        .then((data) => {
          if (active) setMap(data);
        })
        .catch((e) => {
          if (!active) return;
          if (api.isUnauthorized(e)) {
            router.replace("/");
            return;
          }
          setError(e instanceof api.ApiError ? e.message : "Erro ao carregar.");
        });
      return () => {
        active = false;
      };
    }, []),
  );

  async function onLogout() {
    await clearToken();
    router.replace("/");
  }

  const count = map ? map.loose_points.length + map.journeys.reduce((n, j) => n + j.points.length, 0) : 0;

  return (
    <ScrollView style={s.screen} contentContainerStyle={{ paddingBottom: 24 }}>
      <View style={s.body}>
        <View style={s.headerRow}>
          <View style={{ flex: 1 }}>
            <Text style={s.overline}>Some Journey</Text>
            <Text style={s.title}>Seu atlas</Text>
            <Text style={s.sub}>
              {count} {count === 1 ? "memória registrada" : "memórias registradas"}
            </Text>
          </View>
          <View style={{ alignItems: "flex-end", gap: 8 }}>
            <Pressable onPress={() => router.push("/change-password" as unknown as Href)} hitSlop={8} accessibilityRole="button" accessibilityLabel="Alterar senha">
              <Text style={s.sair}>Alterar senha</Text>
            </Pressable>
            <Pressable onPress={onLogout} hitSlop={8} accessibilityRole="button" accessibilityLabel="Sair da conta">
              <Text style={s.sair}>Sair</Text>
            </Pressable>
          </View>
        </View>

        <Pressable
          style={({ pressed }) => [s.journeysLink, pressed && { opacity: 0.9 }]}
          onPress={() => router.push("/journeys")}
          accessibilityRole="button"
          accessibilityLabel="Ver minhas jornadas"
        >
          <Text style={s.journeysLinkText}>Minhas jornadas</Text>
          <Text style={s.journeysArrow}>→</Text>
        </Pressable>

        {map === null && !error ? (
          <ActivityIndicator color={colors.cyan} style={{ marginTop: 40 }} />
        ) : error ? (
          <Text style={s.error}>{error}</Text>
        ) : (
          <View style={{ marginTop: 16 }}>
            <AtlasMap data={map} onSelect={(id) => router.push(`/memory/${id}`)} />
            <View style={s.legend}>
              <View style={s.legendItem}>
                <View style={[s.dot, { backgroundColor: colors.cyan }]} />
                <Text style={s.legendText}>Pontos soltos</Text>
              </View>
              <View style={s.legendItem}>
                <View style={[s.dot, { backgroundColor: colors.wine }]} />
                <Text style={s.legendText}>Jornadas + rastros</Text>
              </View>
            </View>
            {count === 0 ? (
              <View style={s.empty}>
                <Text style={s.emptyText}>Seu atlas está em branco.</Text>
                <Text style={s.emptyHint}>Toque no botão central para registrar a primeira memória.</Text>
              </View>
            ) : null}
          </View>
        )}
      </View>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.paper },
  body: {
    backgroundColor: colors.paper,
    paddingHorizontal: 24,
    paddingTop: 64,
    minHeight: 460,
  },
  headerRow: { flexDirection: "row", alignItems: "flex-start", justifyContent: "space-between", gap: 12 },
  overline: { fontFamily: mono, fontSize: 11, letterSpacing: 2, color: colors.gold, textTransform: "uppercase" },
  title: { fontFamily: serif, fontSize: 32, color: colors.ink, marginTop: 6 },
  sub: { color: colors.inkSoft, fontSize: 14, marginTop: 4 },
  sair: { color: colors.cyan, fontSize: 14, fontWeight: "600", marginTop: 6 },
  journeysLink: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.line,
    borderRadius: 8,
    paddingVertical: 14,
    paddingHorizontal: 16,
    marginTop: 18,
  },
  journeysLinkText: { fontFamily: serif, fontSize: 17, color: colors.ink },
  journeysArrow: { fontSize: 18, color: colors.cyan, fontWeight: "700" },
  error: { color: colors.danger, textAlign: "center", marginTop: 32 },
  legend: { flexDirection: "row", gap: 18, marginTop: 12, paddingHorizontal: 4 },
  legendItem: { flexDirection: "row", alignItems: "center", gap: 6 },
  dot: { width: 10, height: 10, borderRadius: 5 },
  legendText: { fontFamily: mono, color: colors.inkSoft, fontSize: 11, letterSpacing: 1, textTransform: "uppercase" },
  empty: { marginTop: 28, alignItems: "center" },
  emptyText: { fontFamily: serif, fontSize: 18, color: colors.ink, textAlign: "center" },
  emptyHint: { color: colors.inkSoft, fontSize: 14, textAlign: "center", marginTop: 8, lineHeight: 20 },
});
