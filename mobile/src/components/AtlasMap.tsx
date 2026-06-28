import { Pressable, StyleSheet, Text, View } from "react-native";

import type { MapResponse } from "../lib/api";
import { colors, serif } from "../theme/colors";

type Props = {
  data: MapResponse | null;
  onSelect: (memoryId: string) => void;
};

type Row = { memory_id: string; title: string; latitude: number; longitude: number; journey?: string };

// Fallback nativo do mapa: sem biblioteca de mapa no nativo (o mapa interativo
// roda no web, com Leaflet), aqui listamos os pontos de forma tocável para não
// perder o acesso aos dados. Mantém a filosofia de placeholder honesto.
export default function AtlasMap({ data, onSelect }: Props) {
  if (!data) return null;

  const rows: Row[] = [];
  for (const j of data.journeys) {
    for (const p of j.points) {
      rows.push({ memory_id: p.memory_id, title: p.title, latitude: p.latitude, longitude: p.longitude, journey: j.title });
    }
  }
  for (const m of data.loose_points) {
    rows.push({ memory_id: m.memory_id, title: m.title, latitude: m.latitude, longitude: m.longitude });
  }

  return (
    <View>
      <View style={s.note}>
        <Text style={s.noteTitle}>Mapa interativo no app web</Text>
        <Text style={s.noteText}>
          No celular, o mapa com pins e rastros chega com um provedor nativo. Por aqui, seus locais
          ficam tocáveis abaixo.
        </Text>
      </View>

      {rows.length === 0 ? (
        <Text style={s.empty}>Nenhum ponto no mapa ainda.</Text>
      ) : (
        <View style={{ gap: 8, marginTop: 12 }}>
          {rows.map((r) => (
            <Pressable
              key={r.memory_id}
              style={({ pressed }) => [s.row, pressed && { opacity: 0.9 }]}
              onPress={() => onSelect(r.memory_id)}
              accessibilityRole="button"
              accessibilityLabel={`Ver memória: ${r.title}`}
            >
              <View style={[s.pin, { backgroundColor: r.journey ? colors.terra : colors.teal }]} />
              <View style={{ flex: 1 }}>
                <Text style={s.rowTitle} numberOfLines={1}>
                  {r.title}
                </Text>
                <Text style={s.rowMeta}>
                  {r.latitude.toFixed(3)}, {r.longitude.toFixed(3)}
                  {r.journey ? ` • ${r.journey}` : ""}
                </Text>
              </View>
            </Pressable>
          ))}
        </View>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  note: { backgroundColor: "rgba(61,138,152,0.10)", borderRadius: 14, padding: 14 },
  noteTitle: { fontFamily: serif, fontSize: 15, color: colors.teal },
  noteText: { color: colors.inkSoft, fontSize: 13, lineHeight: 19, marginTop: 4 },
  empty: { color: colors.inkSoft, fontSize: 14, marginTop: 18, textAlign: "center" },
  row: { flexDirection: "row", alignItems: "center", gap: 10, backgroundColor: colors.card, borderWidth: 1, borderColor: colors.line, borderRadius: 12, padding: 12 },
  pin: { width: 10, height: 10, borderRadius: 5 },
  rowTitle: { fontFamily: serif, fontSize: 16, color: colors.ink },
  rowMeta: { color: colors.inkSoft, fontSize: 12, marginTop: 2 },
});
