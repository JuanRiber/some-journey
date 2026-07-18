import { useCallback, useState } from "react";
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { router, useFocusEffect } from "expo-router";

import * as api from "../../lib/api";
import { STATUS_COLOR, STATUS_LABEL } from "../../lib/journeyStatus";
import { colors, mono, serif } from "../../theme/colors";

// Mês/ano por extenso a partir das partes UTC (a data não "vaza" para outro dia
// conforme o fuso do aparelho).
function monthYear(iso: string): string {
  return new Date(iso).toLocaleDateString("pt-BR", { month: "long", year: "numeric", timeZone: "UTC" });
}

// Período editorial da jornada: usa o intervalo definido; senão o mês de criação.
function periodLabel(j: api.Journey): string {
  if (j.started_at && j.ended_at) {
    const a = monthYear(j.started_at);
    const b = monthYear(j.ended_at);
    return a === b ? a : `${a} — ${b}`;
  }
  if (j.started_at) return `desde ${monthYear(j.started_at)}`;
  return monthYear(j.created_at);
}

function countLabel(n: number): string {
  return `${n} ${n === 1 ? "memória" : "memórias"}`;
}

// Faixa de "capa": um mapa desbotado (trilha tracejada + pin) enquanto não há
// imagem de capa própria. O selo de status fica sobre ela, no canto.
function CoverBand({ status }: { status: api.JourneyStatus }) {
  return (
    <View style={s.cover}>
      <View style={[s.coverArc, { top: -46, right: -30, width: 120, height: 120, borderRadius: 60 }]} />
      <View style={[s.coverArc, { top: -28, right: -12, width: 84, height: 84, borderRadius: 42 }]} />
      <View style={[s.coverArc, { top: -12, right: 4, width: 52, height: 52, borderRadius: 26 }]} />
      <View style={s.coverTrail} />
      <View style={s.coverPin} />
      <View style={[s.badge, s.coverBadge, { backgroundColor: STATUS_COLOR[status] }]}>
        <Text style={s.badgeText}>{STATUS_LABEL[status]}</Text>
      </View>
    </View>
  );
}

// Lista das jornadas do usuário — cada card é uma entrada de atlas.
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
    <ScrollView style={s.screen} contentContainerStyle={{ paddingBottom: 48 }}>
      <View style={{ paddingTop: 52, paddingHorizontal: 24 }}>
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
        <Text style={s.sub}>Capítulos da sua vida, reunidos em mapas vivos.</Text>

        {error ? (
          <Text style={s.error}>{error}</Text>
        ) : journeys === null ? (
          <ActivityIndicator color={colors.coral} style={{ marginTop: 48 }} />
        ) : journeys.length === 0 ? (
          <View style={s.empty}>
            <Text style={s.emptyText}>Você ainda não criou nenhuma jornada.</Text>
            <Text style={s.emptyHint}>
              Uma jornada reúne memórias, lugares e momentos em um mapa vivo.
            </Text>
            <Pressable
              style={({ pressed }) => [s.emptyCta, pressed && { opacity: 0.9 }]}
              onPress={() => router.push("/journey-new")}
              accessibilityRole="button"
              accessibilityLabel="Criar primeira jornada"
            >
              <Text style={s.emptyCtaText}>Criar primeira jornada</Text>
            </Pressable>
          </View>
        ) : (
          <View style={{ marginTop: 20, gap: 18 }}>
            {journeys.map((j) => (
              <Pressable
                key={j.id}
                style={({ pressed }) => [s.card, pressed && { opacity: 0.94 }]}
                onPress={() => router.push(`/journeys/${j.id}`)}
                accessibilityRole="button"
                accessibilityLabel={`Abrir jornada: ${j.title}`}
              >
                <CoverBand status={j.status} />
                <View style={s.body}>
                  <Text style={s.cardTitle} numberOfLines={1}>
                    {j.title}
                  </Text>
                  {j.description ? (
                    <Text style={s.cardDesc} numberOfLines={2}>
                      {j.description}
                    </Text>
                  ) : null}
                  <Text style={s.cardMeta}>
                    {countLabel(j.points_count)} · {periodLabel(j)}
                  </Text>
                  {(j.mood || !j.is_private) ? (
                    <View style={s.chipRow}>
                      {j.mood ? (
                        <View style={s.chip}>
                          <Text style={s.chipText} numberOfLines={1}>
                            {j.mood}
                          </Text>
                        </View>
                      ) : null}
                      {!j.is_private ? (
                        <View style={[s.chip, s.chipPublic]}>
                          <Text style={[s.chipText, { color: colors.mint }]}>pública</Text>

                        </View>
                      ) : null}
                    </View>
                  ) : null}
                </View>
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
  headerRow: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", marginTop: 16 },
  title: { fontFamily: serif, fontSize: 32, color: colors.ink },
  sub: { fontFamily: serif, fontStyle: "italic", color: colors.inkSoft, fontSize: 14.5, marginTop: 4 },
  newBtn: { backgroundColor: colors.gold, borderRadius: 8, paddingVertical: 10, paddingHorizontal: 16 },
  newBtnText: { fontFamily: mono, color: colors.pageBg, fontSize: 12, fontWeight: "700", letterSpacing: 1, textTransform: "uppercase" },
  error: { color: colors.danger, textAlign: "center", marginTop: 40 },

  empty: { marginTop: 60, alignItems: "center", paddingHorizontal: 12 },
  emptyText: { fontFamily: serif, fontSize: 20, color: colors.ink, textAlign: "center", lineHeight: 27 },
  emptyHint: { color: colors.inkSoft, fontSize: 14.5, textAlign: "center", marginTop: 10, lineHeight: 22 },
  emptyCta: { marginTop: 24, backgroundColor: colors.gold, borderRadius: 8, paddingVertical: 14, paddingHorizontal: 26 },
  emptyCtaText: { fontFamily: mono, color: colors.pageBg, fontSize: 13, fontWeight: "700", letterSpacing: 1.2, textTransform: "uppercase" },

  // Card = capa de disco em miniatura: plano, moldura fina, capa dourada no topo.
  card: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.line,
    borderRadius: 10,
    overflow: "hidden",
  },
  cover: { height: 86, backgroundColor: colors.cover, overflow: "hidden" },
  // Espirais gravadas sobre o ouro, ecoando a arte do topo.
  coverArc: {
    position: "absolute",
    borderWidth: 1.5,
    borderColor: "rgba(227,176,75,0.35)",
    backgroundColor: "transparent",
  },
  coverTrail: {
    position: "absolute", bottom: 26, left: 22, width: 150,
    borderTopWidth: 2, borderColor: "rgba(227,176,75,0.55)", borderStyle: "dashed",
    transform: [{ rotate: "-14deg" }],
  },
  coverPin: {
    position: "absolute", bottom: 22, left: 168, width: 14, height: 14, borderRadius: 7,
    backgroundColor: colors.coral, borderWidth: 1.5, borderColor: colors.coralDeep,
  },
  coverBadge: { position: "absolute", top: 12, right: 12 },
  badge: { borderRadius: 3, paddingVertical: 4, paddingHorizontal: 9 },
  badgeText: { fontFamily: mono, color: colors.pageBg, fontSize: 10, fontWeight: "700", letterSpacing: 1, textTransform: "uppercase" },

  body: { padding: 16 },
  cardTitle: { fontFamily: serif, fontSize: 21, color: colors.ink },
  cardDesc: { color: colors.inkSoft, fontSize: 13.5, lineHeight: 20, marginTop: 6 },
  cardMeta: { fontFamily: mono, color: colors.bloom, fontSize: 11, letterSpacing: 1, textTransform: "uppercase", marginTop: 10 },
  chipRow: { flexDirection: "row", flexWrap: "wrap", gap: 8, marginTop: 12 },
  chip: { backgroundColor: colors.chip, borderRadius: 4, paddingVertical: 5, paddingHorizontal: 10, maxWidth: "100%" },
  chipPublic: { backgroundColor: "rgba(55,195,162,0.12)" },
  chipText: { color: colors.coral, fontSize: 12, fontWeight: "500" },
});
