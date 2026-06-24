import { useEffect, useRef, useState } from "react";
import { ActivityIndicator, Pressable, StyleSheet, Text, TextInput, View } from "react-native";

import { searchPlaces, type GeoResult } from "../lib/geo";
import { colors } from "../theme/colors";

type Props = {
  latitude: number | null;
  longitude: number | null;
  label?: string;
  onChange: (latitude: number, longitude: number, label?: string) => void;
};

// Fallback nativo (iOS/Android): busca de lugar por nome (Nominatim funciona via
// fetch também no nativo). O mapa interativo e o GPS ("minha localização" via
// expo-location) entram quando houver um build nativo — por ora o web é o alvo.
export default function LocationPicker({ latitude, longitude, label, onChange }: Props) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<GeoResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [searched, setSearched] = useState(false);
  const [searchError, setSearchError] = useState(false);
  const [placeLabel, setPlaceLabel] = useState(label ?? "");
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  useEffect(() => {
    const q = query.trim();
    if (q.length < 3) {
      setResults([]);
      setSearched(false);
      setSearchError(false);
      return;
    }
    const ctrl = new AbortController();
    const t = setTimeout(() => {
      setSearching(true);
      setSearchError(false);
      searchPlaces(q, ctrl.signal)
        .then((res) => {
          if (!mountedRef.current) return;
          setResults(res);
          setSearched(true);
        })
        .catch((e) => {
          if (!mountedRef.current || e?.name === "AbortError") return;
          setResults([]);
          setSearched(true);
          setSearchError(true);
        })
        .finally(() => {
          if (mountedRef.current) setSearching(false);
        });
    }, 600);
    return () => {
      ctrl.abort();
      clearTimeout(t);
    };
  }, [query]);

  function selectResult(r: GeoResult) {
    setResults([]);
    setSearched(false);
    setQuery("");
    setPlaceLabel(r.label);
    onChange(r.latitude, r.longitude, r.label);
  }

  const q = query.trim();
  const showNoResults = searched && !searching && !searchError && results.length === 0 && q.length >= 3;
  const hasPoint = latitude != null && longitude != null;

  return (
    <View>
      <Text style={s.hint}>Por aqui, encontre o lugar pelo nome (no app, dá pra tocar no mapa).</Text>

      <View style={s.searchWrap}>
        <TextInput
          style={s.search}
          value={query}
          onChangeText={setQuery}
          placeholder="Busque um lugar: cidade, praia, endereço…"
          placeholderTextColor={colors.placeholder}
          autoCorrect={false}
          accessibilityLabel="Buscar local por nome"
        />
        {searching ? <ActivityIndicator size="small" color={colors.terra} style={s.spin} /> : null}
      </View>

      {results.length > 0 ? (
        <View style={s.results}>
          {results.map((r, i) => (
            <Pressable
              key={`${r.latitude},${r.longitude},${i}`}
              style={({ pressed }) => [s.resultItem, pressed && s.resultItemPressed]}
              onPress={() => selectResult(r)}
              accessibilityRole="button"
              accessibilityLabel={r.label}
            >
              <Text style={s.resultText} numberOfLines={2}>
                {r.label}
              </Text>
            </Pressable>
          ))}
        </View>
      ) : null}

      {searchError ? (
        <Text style={s.searchNote}>Busca indisponível agora. Tente de novo.</Text>
      ) : showNoResults ? (
        <Text style={s.searchNote}>Nenhum lugar encontrado. Tente outro nome.</Text>
      ) : null}

      {hasPoint ? (
        <View style={s.readout}>
          <Text style={s.readoutLabel} numberOfLines={2}>
            {placeLabel || "Local selecionado"}
          </Text>
          <Text style={s.readoutCoords}>
            {(latitude as number).toFixed(5)}, {(longitude as number).toFixed(5)}
          </Text>
        </View>
      ) : (
        <Text style={s.empty}>Busque e selecione um local.</Text>
      )}

      <Text style={s.privacy}>A busca usa o OpenStreetMap.</Text>
    </View>
  );
}

const s = StyleSheet.create({
  hint: { color: colors.inkSoft, fontSize: 12, marginBottom: 8 },
  searchWrap: { justifyContent: "center" },
  search: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: "rgba(35,39,47,0.18)",
    borderRadius: 12,
    paddingHorizontal: 15,
    paddingVertical: 13,
    fontSize: 15,
    color: colors.ink,
  },
  spin: { position: "absolute", right: 14 },
  results: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.line,
    borderRadius: 12,
    marginTop: 6,
    overflow: "hidden",
  },
  resultItem: { paddingHorizontal: 14, paddingVertical: 11, borderBottomWidth: 1, borderBottomColor: colors.line },
  resultItemPressed: { backgroundColor: "rgba(206,90,44,0.08)" },
  resultText: { color: colors.ink, fontSize: 13, lineHeight: 18 },
  searchNote: { color: colors.inkSoft, fontSize: 12, marginTop: 8, fontStyle: "italic" },
  readout: {
    marginTop: 12,
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.line,
    borderRadius: 12,
    padding: 12,
  },
  readoutLabel: { color: colors.ink, fontSize: 13, lineHeight: 18 },
  readoutCoords: { color: colors.inkSoft, fontSize: 12, marginTop: 4 },
  empty: { color: colors.inkSoft, fontSize: 13, marginTop: 12, fontStyle: "italic" },
  privacy: { color: colors.placeholder, fontSize: 11, marginTop: 12 },
});
