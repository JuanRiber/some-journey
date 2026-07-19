import { useCallback, useState } from "react";
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { router, useFocusEffect } from "expo-router";

import MemoryCover from "../../components/MemoryCover";
import NotebookTop from "../../components/NotebookTop";
import * as api from "../../lib/api";
import { colors, mono, serif } from "../../theme/colors";

const MESES = ["JAN", "FEV", "MAR", "ABR", "MAI", "JUN", "JUL", "AGO", "SET", "OUT", "NOV", "DEZ"];

// occurred_at é canonicamente o DIA em UTC (gravado ao meio-dia UTC). Formatamos a
// partir das partes UTC para o dia/ano não "vazarem" para outro valor conforme o
// fuso do aparelho — inclusive em fusos a leste de UTC+12.
function dayMonth(iso: string): string {
  const d = new Date(iso);
  return `${String(d.getUTCDate()).padStart(2, "0")} ${MESES[d.getUTCMonth()]}`;
}
function yearOf(iso: string): number {
  return new Date(iso).getUTCFullYear();
}

type Group = { year: number; items: api.Memory[] };

// A lista já vem ordenada por occurred_at desc do backend; só agrupamos por ano
// preservando essa ordem.
function groupByYear(items: api.Memory[]): Group[] {
  const groups: Group[] = [];
  for (const m of items) {
    const year = yearOf(m.occurred_at);
    const last = groups[groups.length - 1];
    if (last && last.year === year) last.items.push(m);
    else groups.push({ year, items: [m] });
  }
  return groups;
}

// Achata grupos + itens numa sequência única de linhas, para o trilho (a "espinha"
// vertical) correr de forma contínua e atravessar os cabeçalhos de ano.
type Row = { kind: "year"; year: number; first: boolean } | { kind: "item"; m: api.Memory };
function toRows(groups: Group[]): Row[] {
  const rows: Row[] = [];
  groups.forEach((g, gi) => {
    rows.push({ kind: "year", year: g.year, first: gi === 0 });
    g.items.forEach((m) => rows.push({ kind: "item", m }));
  });
  return rows;
}

export default function TimelineScreen() {
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

  const rows = memories ? toRows(groupByYear(memories)) : [];

  return (
    <View style={s.screen}>
      <NotebookTop />
      <ScrollView
        style={s.scroll}
        contentContainerStyle={{ paddingHorizontal: 24, paddingTop: 24, paddingBottom: 40 }}
      >
        <Text style={s.title}>Timeline</Text>
        <Text style={s.subtitle}>As memórias do seu atlas em ordem viva.</Text>

        {memories === null && !error ? (
          <ActivityIndicator color={colors.cyan} style={{ marginTop: 48 }} />
        ) : error ? (
          <Text style={s.error}>{error}</Text>
        ) : memories!.length === 0 ? (
          <View style={s.empty}>
            <Text style={s.emptyText}>Seu atlas ainda não tem memórias.</Text>
            <Text style={s.emptyHint}>Toque no botão central para registrar a primeira.</Text>
          </View>
        ) : (
          rows.map((row, i) => {
            const isLast = i === rows.length - 1;
            // Espinha: contínua no meio, recuada no topo (primeira linha) e cortada
            // logo após o último ponto (sem sobrar linha apontando para o nada).
            const spineStyle = i === 0 ? s.spineFirst : isLast ? s.spineLast : s.spineFull;

            if (row.kind === "year") {
              return (
                <View key={`y${row.year}`} style={s.entry}>
                  <View style={s.rail}>
                    <View style={spineStyle} />
                  </View>
                  <View style={s.yearRow}>
                    <Text style={s.year}>{row.year}</Text>
                    {row.first ? <Text style={s.yearNote}>atlas pessoal</Text> : null}
                  </View>
                </View>
              );
            }

            const m = row.m;
            return (
              <View key={m.id} style={s.entry}>
                <View style={s.rail}>
                  <View style={spineStyle} />
                  <View style={s.railDot} />
                </View>
                <View style={s.cardWrap}>
                  <Text style={s.date}>{dayMonth(m.occurred_at)}</Text>
                  <View style={s.card}>
                    <MemoryCover url={m.image_url} size={54} />
                    <View style={{ flex: 1 }}>
                      <Text style={s.cardTitle} numberOfLines={1}>
                        {m.title}
                      </Text>
                      <View style={s.coordRow}>
                        <View style={s.pin} />
                        <Text style={s.coords}>
                          {m.latitude.toFixed(3)}, {m.longitude.toFixed(3)}
                        </Text>
                      </View>
                      <Pressable
                        onPress={() => router.push({ pathname: "/memory/[id]", params: { id: m.id } })}
                        hitSlop={6}
                        accessibilityRole="button"
                        accessibilityLabel={`Abrir memória: ${m.title}`}
                      >
                        <Text style={s.open}>Abrir memória →</Text>
                      </Pressable>
                    </View>
                  </View>
                </View>
              </View>
            );
          })
        )}
      </ScrollView>
    </View>
  );
}

const LINE = "rgba(242,234,216,0.16)";

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.paper },
  scroll: { flex: 1, backgroundColor: colors.paper },
  title: { fontFamily: serif, fontSize: 32, color: colors.ink },
  subtitle: { fontFamily: serif, fontStyle: "italic", color: colors.inkSoft, fontSize: 14.5, marginTop: 5 },
  error: { color: colors.danger, textAlign: "center", marginTop: 48 },
  empty: { marginTop: 56, alignItems: "center" },
  emptyText: { fontFamily: serif, fontSize: 18, color: colors.ink, textAlign: "center" },
  emptyHint: { color: colors.inkSoft, fontSize: 14, textAlign: "center", marginTop: 8, lineHeight: 20, paddingHorizontal: 24 },
  entry: { flexDirection: "row" },
  rail: { width: 28, alignItems: "center", position: "relative" },
  // Variantes da espinha vertical (posição absoluta, centrada na coluna do trilho).
  spineFull: { position: "absolute", left: 13, top: 0, bottom: 0, width: 2, backgroundColor: LINE },
  spineFirst: { position: "absolute", left: 13, top: 26, bottom: 0, width: 2, backgroundColor: LINE },
  spineLast: { position: "absolute", left: 13, top: 0, height: 34, width: 2, backgroundColor: LINE },
  railDot: { width: 12, height: 12, borderRadius: 6, backgroundColor: colors.wine, marginTop: 22, zIndex: 1 },
  yearRow: { flexDirection: "row", alignItems: "flex-end", gap: 12, marginTop: 22, marginBottom: 4 },
  // O ano como numeral mono dourado, ecoando o "01 / 02 / 03" da landing.
  year: { fontFamily: mono, fontSize: 36, color: colors.gold, letterSpacing: 2 },
  yearNote: { fontFamily: serif, fontStyle: "italic", fontSize: 14, color: colors.inkSoft, marginBottom: 8 },
  cardWrap: { flex: 1, marginBottom: 16 },
  date: { fontFamily: mono, color: colors.bloom, fontSize: 11, letterSpacing: 1.2, textTransform: "uppercase", marginTop: 16, marginBottom: 6 },
  card: { flexDirection: "row", gap: 12, backgroundColor: colors.card, borderWidth: 1, borderColor: colors.line, borderRadius: 8, padding: 12 },
  thumb: { width: 54, height: 54, borderRadius: 10, backgroundColor: colors.sand, borderWidth: 1, borderColor: colors.line },
  cardTitle: { fontFamily: serif, fontSize: 17, color: colors.ink },
  coordRow: { flexDirection: "row", alignItems: "center", gap: 6, marginTop: 4 },
  pin: { width: 8, height: 8, borderRadius: 4, backgroundColor: colors.wine },
  coords: { color: colors.inkSoft, fontSize: 12 },
  open: { color: colors.cyan, fontWeight: "600", fontSize: 13, marginTop: 8 },
});
