import { useCallback, useState } from "react";
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { router, useFocusEffect } from "expo-router";

import * as api from "../../lib/api";
import { STATUS_COLOR, STATUS_LABEL } from "../../lib/journeyStatus";
import { colors, serif } from "../../theme/colors";

// Lista das jornadas do usuário. Toque abre o detalhe; botão cria uma nova.
export default function JourneysScreen() {
  const [journeys, setJourneys] = useState<api.Journey[] | null>(null);
  const [error, setError] = useState("");

  useFocusEffect(
    useCallback(() => {
      let active = true;
      setError("");
      api
        .listJourneys()
        .then((data) => {
          if (active) setJourneys(data);
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

  return (
    <ScrollView style={s.screen} contentContainerStyle={{ paddingBottom: 40 }}>
      <View style={{ paddingTop: 50, paddingHorizontal: 24 }}>
        <Pressable
          onPress={() => (router.canGoBack() ? router.back() : router.replace("/atlas"))}
          accessibilityRole="button"
          accessibilityLabel="Voltar"
        >
          <Text style={s.back}>← Voltar</Text>
        </Pressable>

        <View style={s.headerRow}>
          <Text style={s.title}>Jornadas</Text>
          <Pressable
            style={({ pressed }) => [s.newBtn, pressed && { opacity: 0.9 }]}
            onPress={() => router.push("/journey-new")}
            accessibilityRole="button"
            accessibilityLabel="Nova jornada"
          >
            <Text style={s.newBtnText}>+ Nova</Text>
          </Pressable>
        </View>
        <Text style={s.sub}>Fases e trajetórias que conectam suas memórias.</Text>

        {error ? (
          <Text style={s.error}>{error}</Text>
        ) : journeys === null ? (
          <ActivityIndicator color={colors.terra} style={{ marginTop: 40 }} />
        ) : journeys.length === 0 ? (
          <View style={s.empty}>
            <Text style={s.emptyText}>Nenhuma jornada ainda.</Text>
            <Text style={s.emptyHint}>Crie uma para agrupar memórias em uma trajetória no mapa.</Text>
          </View>
        ) : (
          <View style={{ marginTop: 18, gap: 12 }}>
            {journeys.map((j) => (
              <Pressable
                key={j.id}
                style={({ pressed }) => [s.card, pressed && { opacity: 0.92 }]}
                onPress={() => router.push(`/journeys/${j.id}`)}
                accessibilityRole="button"
                accessibilityLabel={`Abrir jornada: ${j.title}`}
              >
                <View style={s.cardHead}>
                  <Text style={s.cardTitle} numberOfLines={1}>
                    {j.title}
                  </Text>
                  <View style={[s.badge, { backgroundColor: STATUS_COLOR[j.status] }]}>
                    <Text style={s.badgeText}>{STATUS_LABEL[j.status]}</Text>
                  </View>
                </View>
                {j.description ? (
                  <Text style={s.cardDesc} numberOfLines={2}>
                    {j.description}
                  </Text>
                ) : null}
                <Text style={s.cardMeta}>
                  {j.points_count} {j.points_count === 1 ? "ponto" : "pontos"}
                </Text>
              </Pressable>
            ))}
          </View>
        )}
      </View>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.paper },
  back: { color: colors.ink, fontSize: 14, fontWeight: "500" },
  headerRow: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", marginTop: 14 },
  title: { fontFamily: serif, fontSize: 30, color: colors.ink },
  sub: { color: colors.inkSoft, fontSize: 14, marginTop: 2 },
  newBtn: { backgroundColor: colors.terra, borderRadius: 10, paddingVertical: 9, paddingHorizontal: 16 },
  newBtnText: { color: "#FBF6E8", fontSize: 14, fontWeight: "600" },
  error: { color: colors.danger, textAlign: "center", marginTop: 32 },
  empty: { marginTop: 44, alignItems: "center" },
  emptyText: { fontFamily: serif, fontSize: 18, color: colors.ink, textAlign: "center" },
  emptyHint: { color: colors.inkSoft, fontSize: 14, textAlign: "center", marginTop: 8, lineHeight: 20 },
  card: { backgroundColor: colors.card, borderWidth: 1, borderColor: colors.line, borderRadius: 16, padding: 16 },
  cardHead: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 10 },
  cardTitle: { fontFamily: serif, fontSize: 19, color: colors.ink, flex: 1 },
  badge: { borderRadius: 20, paddingVertical: 3, paddingHorizontal: 10 },
  badgeText: { color: "#FBF6E8", fontSize: 11, fontWeight: "700", letterSpacing: 0.3 },
  cardDesc: { color: colors.inkSoft, fontSize: 13, lineHeight: 19, marginTop: 6 },
  cardMeta: { color: colors.terraDeep, fontSize: 12, fontWeight: "600", marginTop: 8 },
});
