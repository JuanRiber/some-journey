import { useEffect, useRef, useState } from "react";
import { ActivityIndicator, StyleSheet, Text, View } from "react-native";
import "leaflet/dist/leaflet.css";

import type { MapResponse } from "../lib/api";
import { colors } from "../theme/colors";

type Props = {
  data: MapResponse | null;
  onSelect: (memoryId: string) => void;
  // Percursos reais (GPS): cada item é uma LineString em [lng, lat].
  tracks?: number[][][];
};

const DEFAULT_CENTER: [number, number] = [-14.235, -51.925]; // Brasil
const DEFAULT_ZOOM = 4;

const MapDiv: any = "div";

function pinIcon(L: any, color: string) {
  return L.divIcon({
    className: "sj-atlas-pin",
    html:
      `<div style="width:20px;height:20px;border-radius:50%;background:${color};` +
      `border:2px solid #FBF6E8;box-shadow:0 2px 5px rgba(0,0,0,.4)"></div>`,
    iconSize: [20, 20],
    iconAnchor: [10, 10],
  });
}

// Mapa principal do Atlas (web): desenha os pins soltos (teal), os pins das
// jornadas (terra) e os rastros (linhas) a partir de GET /map. Tocar num pin
// abre o detalhe da memória. Reusa Leaflet/OSM, como o LocationPicker.
export default function AtlasMap({ data, onSelect, tracks }: Props) {
  const divRef = useRef<any>(null);
  const mapRef = useRef<any>(null);
  const leafletRef = useRef<any>(null);
  const layerRef = useRef<any>(null);
  const onSelectRef = useRef(onSelect);
  onSelectRef.current = onSelect;

  const [ready, setReady] = useState(false);
  const [mapError, setMapError] = useState(false);

  // Inicializa o mapa uma vez (Leaflet toca em window → import dinâmico no client).
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const mod: any = await import("leaflet");
        if (cancelled) return;
        const L = mod.default ?? mod;
        leafletRef.current = L;
        if (!divRef.current || mapRef.current) return;
        const map = L.map(divRef.current, {
          center: DEFAULT_CENTER,
          zoom: DEFAULT_ZOOM,
          scrollWheelZoom: false,
        });
        map.on("focus", () => map.scrollWheelZoom.enable());
        map.on("blur", () => map.scrollWheelZoom.disable());
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
          maxZoom: 19,
          attribution: "© OpenStreetMap",
        }).addTo(map);
        layerRef.current = L.layerGroup().addTo(map);
        mapRef.current = map;
        setReady(true);
        setTimeout(() => map.invalidateSize(), 60);
      } catch {
        if (!cancelled) setMapError(true);
      }
    })();
    return () => {
      cancelled = true;
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
        layerRef.current = null;
      }
    };
  }, []);

  // Redesenha pins + rastros quando os dados mudam.
  useEffect(() => {
    const map = mapRef.current;
    const L = leafletRef.current;
    const layer = layerRef.current;
    if (!map || !L || !layer || !data) return;
    layer.clearLayers();
    const all: [number, number][] = [];

    const addPin = (lat: number, lng: number, title: string, memoryId: string, color: string) => {
      all.push([lat, lng]);
      const marker = L.marker([lat, lng], { icon: pinIcon(L, color), title });
      marker.on("click", () => onSelectRef.current(memoryId));
      marker.addTo(layer);
    };

    // Rastros e pins das jornadas (terra).
    for (const j of data.journeys) {
      if (j.route && j.route.coordinates.length >= 2) {
        // GeoJSON é [lng, lat]; Leaflet quer [lat, lng].
        const line = j.route.coordinates.map(([lng, lat]) => [lat, lng]) as [number, number][];
        L.polyline(line, { color: colors.terra, weight: 3, opacity: 0.75 }).addTo(layer);
      }
      for (const p of j.points) addPin(p.latitude, p.longitude, p.title, p.memory_id, colors.terra);
    }
    // Pins soltos (teal).
    for (const m of data.loose_points) addPin(m.latitude, m.longitude, m.title, m.memory_id, colors.teal);

    // Percursos reais (GPS): traço mais escuro e grosso que o rastro simbólico.
    for (const coords of tracks ?? []) {
      if (coords.length >= 2) {
        const line = coords.map(([lng, lat]) => [lat, lng]) as [number, number][];
        L.polyline(line, { color: colors.terraDeep, weight: 4, opacity: 0.9, lineCap: "round", lineJoin: "round" }).addTo(layer);
        for (const pt of line) all.push(pt);
      }
    }

    if (all.length === 1) map.setView(all[0], 13);
    else if (all.length > 1) map.fitBounds(all, { padding: [40, 40] });
  }, [data, tracks, ready]);

  return (
    <View style={s.shell}>
      <MapDiv ref={divRef} style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0 }} />
      {mapError ? (
        <View style={s.overlay}>
          <Text style={s.errText}>Não foi possível carregar o mapa.</Text>
          <Text style={s.hint}>Veja suas memórias pela aba Tempo.</Text>
        </View>
      ) : !ready ? (
        <View style={s.overlay}>
          <ActivityIndicator color={colors.terra} />
          <Text style={s.hint}>Carregando mapa…</Text>
        </View>
      ) : null}
    </View>
  );
}

const s = StyleSheet.create({
  shell: {
    position: "relative",
    width: "100%",
    height: 380,
    borderRadius: 18,
    overflow: "hidden",
    borderWidth: 1,
    borderColor: colors.line,
    backgroundColor: colors.sky,
  },
  overlay: { position: "absolute", inset: 0, alignItems: "center", justifyContent: "center", gap: 6 } as any,
  hint: { color: colors.inkSoft, fontSize: 13, textAlign: "center" },
  errText: { color: colors.danger, fontSize: 14, fontWeight: "600", textAlign: "center" },
});
