import { useCallback, useEffect, useRef, useState } from "react";
import { ActivityIndicator, Pressable, StyleSheet, Text, TextInput, View } from "react-native";
import "leaflet/dist/leaflet.css";

import { reverseGeocode, searchPlaces, type GeoResult } from "../lib/geo";
import { colors } from "../theme/colors";

type Props = {
  latitude: number | null;
  longitude: number | null;
  label?: string;
  onChange: (latitude: number, longitude: number, label?: string) => void;
};

const DEFAULT_CENTER: [number, number] = [-14.235, -51.925]; // Brasil (visão ampla)
const DEFAULT_ZOOM = 4;
const PICK_ZOOM = 15;

// "div" cru: este arquivo é .web.tsx (só web), então evitamos atritos de JSX
// intrínseco no resto da árvore react-native.
const MapDiv: any = "div";

export default function LocationPicker({ latitude, longitude, label, onChange }: Props) {
  const divRef = useRef<any>(null);
  const mapRef = useRef<any>(null);
  const markerRef = useRef<any>(null);
  const leafletRef = useRef<any>(null);
  const pinRef = useRef<any>(null);
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;
  const mountedRef = useRef(true);

  const [query, setQuery] = useState("");
  const [results, setResults] = useState<GeoResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [searched, setSearched] = useState(false);
  const [searchError, setSearchError] = useState(false);
  const [placeLabel, setPlaceLabel] = useState(label ?? "");
  const [locating, setLocating] = useState(false);
  const [geoError, setGeoError] = useState("");
  const [mapReady, setMapReady] = useState(false);
  const [mapError, setMapError] = useState(false);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  // Coloca/move o pino e (opcionalmente) descobre o nome do lugar por reverse.
  const place = useCallback(
    (lat: number, lng: number, opts?: { zoom?: number; reverse?: boolean; label?: string }) => {
      const map = mapRef.current;
      const L = leafletRef.current;
      if (!map || !L) return;
      if (!markerRef.current) {
        markerRef.current = L.marker([lat, lng], { icon: pinRef.current, draggable: true }).addTo(map);
        markerRef.current.on("dragend", () => {
          const p = markerRef.current.getLatLng();
          onChangeRef.current(p.lat, p.lng);
          setPlaceLabel("");
          reverseGeocode(p.lat, p.lng).then((nm) => {
            if (mountedRef.current && nm) setPlaceLabel(nm);
          });
        });
      } else {
        markerRef.current.setLatLng([lat, lng]);
      }
      map.setView([lat, lng], opts?.zoom ?? map.getZoom());
      if (opts?.label !== undefined) setPlaceLabel(opts.label);
      else if (opts?.reverse) {
        setPlaceLabel("");
        reverseGeocode(lat, lng).then((nm) => {
          if (mountedRef.current && nm) setPlaceLabel(nm);
        });
      }
    },
    [],
  );

  // Inicializa o mapa uma única vez — SÓ no cliente. O JS do Leaflet toca em
  // `window` na carga do módulo, então é importado dinamicamente aqui (effects
  // não rodam no SSR estático do Expo); o CSS, esse sim, pode ficar no topo.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const mod: any = await import("leaflet");
        if (cancelled) return;
        const L = mod.default ?? mod;
        leafletRef.current = L;
        pinRef.current = L.divIcon({
          className: "sj-pin",
          html:
            `<div style="width:24px;height:24px;border-radius:50%;background:${colors.terra};` +
            `border:2px solid ${colors.terraDeep};box-shadow:0 2px 6px rgba(0,0,0,.45);` +
            `display:flex;align-items:center;justify-content:center">` +
            `<div style="width:8px;height:8px;border-radius:50%;background:#FBF6E8"></div></div>`,
          iconSize: [24, 24],
          iconAnchor: [12, 12],
        });

        if (!divRef.current || mapRef.current) return;
        const hasPoint = latitude != null && longitude != null;
        const map = L.map(divRef.current, {
          center: hasPoint ? [latitude as number, longitude as number] : DEFAULT_CENTER,
          zoom: hasPoint ? PICK_ZOOM : DEFAULT_ZOOM,
          // Zoom por scroll só DEPOIS que o usuário engaja o mapa — senão o mapa
          // "rouba" o scroll da página (clássico mapa-dentro-de-scroll). Os
          // botões +/- continuam sempre disponíveis.
          scrollWheelZoom: false,
        });
        map.on("focus", () => map.scrollWheelZoom.enable());
        map.on("blur", () => map.scrollWheelZoom.disable());
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
          maxZoom: 19,
          attribution: "© OpenStreetMap",
        }).addTo(map);
        map.on("click", (e: any) => {
          place(e.latlng.lat, e.latlng.lng, { reverse: true });
          onChangeRef.current(e.latlng.lat, e.latlng.lng);
        });
        mapRef.current = map;
        setMapReady(true);
        if (hasPoint) place(latitude as number, longitude as number, { zoom: PICK_ZOOM });
        // Leaflet renderiza tiles cinzas se mediu o container antes do layout.
        setTimeout(() => map.invalidateSize(), 60);
      } catch {
        // Falha ao baixar o chunk do Leaflet (offline, etc.): a busca e o GPS
        // continuam funcionando, então só sinalizamos e tiramos o spinner.
        if (!cancelled) setMapError(true);
      }
    })();
    return () => {
      cancelled = true;
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
        markerRef.current = null;
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Busca com debounce (respeita a política do Nominatim). O spinner só acende
  // quando a requisição realmente dispara (não durante a janela do debounce).
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
    place(r.latitude, r.longitude, { zoom: PICK_ZOOM, label: r.label });
    onChangeRef.current(r.latitude, r.longitude, r.label);
  }

  function useMyLocation() {
    setGeoError("");
    if (typeof navigator === "undefined" || !navigator.geolocation) {
      setGeoError("Geolocalização indisponível neste navegador.");
      return;
    }
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        if (!mountedRef.current) return;
        setLocating(false);
        place(pos.coords.latitude, pos.coords.longitude, { zoom: PICK_ZOOM, reverse: true });
        onChangeRef.current(pos.coords.latitude, pos.coords.longitude);
      },
      (err) => {
        if (!mountedRef.current) return;
        setLocating(false);
        setGeoError(
          err && err.code === 1
            ? "Permissão de localização negada."
            : "Não foi possível obter sua localização. Tente de novo.",
        );
      },
      { enableHighAccuracy: true, timeout: 8000 },
    );
  }

  const q = query.trim();
  const showNoResults = searched && !searching && !searchError && results.length === 0 && q.length >= 3;
  const hasPoint = latitude != null && longitude != null;

  return (
    <View>
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
        <Text style={s.searchNote}>Busca indisponível agora. Tente de novo ou toque no mapa.</Text>
      ) : showNoResults ? (
        <Text style={s.searchNote}>Nenhum lugar encontrado. Tente outro nome ou toque no mapa.</Text>
      ) : null}

      <View style={s.mapShell}>
        {/* Absoluto (fora do fluxo): o tamanho vem do mapShell, sem o ciclo de
            largura do flexbox que zerava o container do Leaflet. */}
        <MapDiv ref={divRef} style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0 }} />
        {mapError ? (
          <View style={s.mapLoading}>
            <Text style={s.mapErrorText}>Não foi possível carregar o mapa.</Text>
            <Text style={s.mapLoadingText}>Use a busca ou “minha localização” acima.</Text>
          </View>
        ) : !mapReady ? (
          <View style={s.mapLoading}>
            <ActivityIndicator color={colors.terra} />
            <Text style={s.mapLoadingText}>Carregando mapa…</Text>
          </View>
        ) : (
          <View pointerEvents="none" style={s.mapHint}>
            <Text style={s.mapHintText}>Toque para interagir · arraste o pino</Text>
          </View>
        )}
      </View>

      <Pressable
        style={({ pressed }) => [s.locBtn, pressed && { opacity: 0.9 }]}
        onPress={useMyLocation}
        disabled={locating}
        accessibilityRole="button"
        accessibilityLabel="Usar minha localização atual"
      >
        <View style={s.locDot} />
        <Text style={s.locText}>{locating ? "Localizando…" : "Usar minha localização"}</Text>
      </Pressable>

      {geoError ? <Text style={s.geoError}>{geoError}</Text> : null}

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
        <Text style={s.empty}>Nenhum local escolhido ainda.</Text>
      )}

      <Text style={s.privacy}>A busca e o nome do lugar usam o OpenStreetMap.</Text>
    </View>
  );
}

const s = StyleSheet.create({
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
  mapShell: {
    position: "relative",
    width: "100%",
    height: 240,
    borderRadius: 14,
    overflow: "hidden",
    borderWidth: 1,
    borderColor: colors.line,
    marginTop: 10,
    backgroundColor: colors.sky,
  },
  mapHint: {
    position: "absolute",
    top: 8,
    alignSelf: "center",
    backgroundColor: "rgba(35,39,47,0.62)",
    borderRadius: 20,
    paddingHorizontal: 12,
    paddingVertical: 5,
  },
  mapHintText: { color: "#FBF6E8", fontSize: 11, fontWeight: "500" },
  mapLoading: { position: "absolute", inset: 0, alignItems: "center", justifyContent: "center", gap: 6, paddingHorizontal: 16 } as any,
  mapLoadingText: { color: colors.inkSoft, fontSize: 13, textAlign: "center" },
  mapErrorText: { color: colors.danger, fontSize: 14, fontWeight: "600", textAlign: "center" },
  locBtn: {
    flexDirection: "row",
    alignItems: "center",
    gap: 9,
    alignSelf: "flex-start",
    backgroundColor: "rgba(61,138,152,0.12)",
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 10,
    marginTop: 12,
  },
  locDot: { width: 12, height: 12, borderRadius: 6, backgroundColor: colors.teal, borderWidth: 2, borderColor: "#FBF6E8" },
  locText: { color: colors.teal, fontSize: 14, fontWeight: "600" },
  geoError: { color: colors.danger, fontSize: 12, marginTop: 8 },
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
