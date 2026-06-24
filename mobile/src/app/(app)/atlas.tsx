import { useCallback, useState } from "react";
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { router, useFocusEffect } from "expo-router";

import JourneyHeader from "../../components/JourneyHeader";
import * as api from "../../lib/api";
import { clearToken } from "../../lib/auth";
import { colors, serif } from "../../theme/colors";

// Atlas (aba padrão pós-login). Placeholder honesto enquanto o mapa real
// (Mapbox) não chega: cena + contagem + a memória mais recente como destaque.
export default function AtlasScreen() {
  const [memories, setMemories] = useState<api.Memory[] | null>(null);
  const [error, setError] = useState("");

  useFocusEffect(
    useCallback(() => {
      let active = true;
      setError("");
      api
        .listMemories()
        .then((data) => {
          if (active) setMemories(data);
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

  const count = memories?.length ?? 0;
  const featured = memories && memories.length > 0 ? memories[0] : null;

  return (
    <ScrollView style={s.screen} contentContainerStyle={{ paddingBottom: 24 }}>
      <JourneyHeader />

      <View style={s.body}>
        <View style={s.headerRow}>
          <View style={{ flex: 1 }}>
            <Text style={s.title}>Seu atlas</Text>
            <Text style={s.sub}>
              {count} {count === 1 ? "memória registrada" : "memórias registradas"}
            </Text>
          </View>
          <Pressable onPress={onLogout} hitSlop={8} accessibilityRole="button" accessibilityLabel="Sair da conta">
            <Text style={s.sair}>Sair</Text>
          </Pressable>
        </View>

        <View style={s.note}>
          <Text style={s.noteTitle}>Mapa interativo a caminho</Text>
          <Text style={s.noteText}>
            O mapa real — tocar para marcar, sua localização e os pins — entra no próximo bloco.
            Por enquanto, sua memória mais recente aparece aqui.
          </Text>
        </View>

        {memories === null && !error ? (
          <ActivityIndicator color={colors.terra} style={{ marginTop: 32 }} />
        ) : error ? (
          <Text style={s.error}>{error}</Text>
        ) : featured ? (
          <View>
            <Text style={s.featuredLabel}>MAIS RECENTE</Text>
            <Pressable
              style={({ pressed }) => [s.card, pressed && { opacity: 0.92 }]}
              onPress={() => router.push({ pathname: "/memory/[id]", params: { id: featured.id } })}
              accessibilityRole="button"
              accessibilityLabel={`Ver memória: ${featured.title}`}
            >
              <View style={s.thumb} />
              <View style={{ flex: 1 }}>
                <Text style={s.cardTitle} numberOfLines={1}>
                  {featured.title}
                </Text>
                <View style={s.coordRow}>
                  <View style={s.pin} />
                  <Text style={s.coords}>
                    {featured.latitude.toFixed(3)}, {featured.longitude.toFixed(3)}
                  </Text>
                </View>
                <Text style={s.cardText} numberOfLines={2}>
                  {featured.text}
                </Text>
                <Text style={s.open}>Ver memória →</Text>
              </View>
            </Pressable>
          </View>
        ) : (
          <View style={s.empty}>
            <Text style={s.emptyText}>Seu atlas está em branco.</Text>
            <Text style={s.emptyHint}>Toque no botão central para registrar a primeira memória.</Text>
          </View>
        )}
      </View>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.sky },
  body: {
    backgroundColor: colors.paper,
    marginTop: -22,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    paddingHorizontal: 24,
    paddingTop: 24,
    minHeight: 460,
  },
  headerRow: { flexDirection: "row", alignItems: "flex-start", justifyContent: "space-between", gap: 12 },
  title: { fontFamily: serif, fontSize: 30, color: colors.ink },
  sub: { color: colors.inkSoft, fontSize: 14, marginTop: 2 },
  sair: { color: colors.teal, fontSize: 14, fontWeight: "500", marginTop: 6 },
  note: {
    backgroundColor: "rgba(61,138,152,0.10)",
    borderRadius: 14,
    padding: 14,
    marginTop: 18,
  },
  noteTitle: { fontFamily: serif, fontSize: 15, color: colors.teal },
  noteText: { color: colors.inkSoft, fontSize: 13, lineHeight: 19, marginTop: 4 },
  error: { color: colors.danger, textAlign: "center", marginTop: 32 },
  featuredLabel: { fontSize: 11, letterSpacing: 1.2, color: colors.inkSoft, marginTop: 20, marginBottom: 8 },
  card: {
    flexDirection: "row",
    gap: 12,
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.line,
    borderRadius: 16,
    padding: 14,
  },
  thumb: { width: 64, height: 64, borderRadius: 12, backgroundColor: colors.sky, borderWidth: 1, borderColor: colors.line },
  cardTitle: { fontFamily: serif, fontSize: 18, color: colors.ink },
  coordRow: { flexDirection: "row", alignItems: "center", gap: 6, marginTop: 4 },
  pin: { width: 8, height: 8, borderRadius: 4, backgroundColor: colors.terra },
  coords: { color: colors.inkSoft, fontSize: 12 },
  cardText: { color: colors.inkSoft, fontSize: 13, lineHeight: 19, marginTop: 6 },
  open: { color: colors.terraDeep, fontWeight: "600", fontSize: 13, marginTop: 8 },
  empty: { marginTop: 40, alignItems: "center" },
  emptyText: { fontFamily: serif, fontSize: 18, color: colors.ink, textAlign: "center" },
  emptyHint: { color: colors.inkSoft, fontSize: 14, textAlign: "center", marginTop: 8, lineHeight: 20 },
});
