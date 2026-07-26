import { useEffect, useMemo, useRef, useState } from "react";
import { ActivityIndicator, StyleSheet, Text, View } from "react-native";
import { WebView, type WebViewMessageEvent } from "react-native-webview";

import type { MapResponse } from "../lib/api";
import { colors } from "../theme/colors";

type Props = {
  data: MapResponse | null;
  onSelect: (memoryId: string) => void;
  // Percursos reais (GPS): cada item é uma LineString em [lng, lat]. Desenhados
  // com um traço distinto (mais escuro/grosso) do rastro simbólico.
  tracks?: number[][][];
};

// Mapa principal do Atlas (nativo): o MESMO mapa Leaflet/OSM do web, só que
// hospedado num WebView (o nativo não roda Leaflet direto). Desenha pins soltos
// (teal), pins de jornada (terra) e os rastros a partir de GET /map; tocar num
// pin manda uma mensagem que abre o detalhe da memória. Leaflet vem do CDN
// (o mapa já depende de rede pelas tiles do OSM). Substitui a antiga lista.
const HTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" />
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
  html, body, #map { height: 100%; margin: 0; padding: 0; }
  body { background: ${colors.sand}; }
  .leaflet-container { background: ${colors.sand}; }
  /* Controles do Leaflet no papel: superfície off-white, tinta marrom e
     hairline da própria paleta (o leaflet.css carrega depois, daí o !important). */
  .leaflet-bar a, .leaflet-bar a:hover, .leaflet-bar a:focus {
    background-color: ${colors.card} !important; color: ${colors.ink} !important;
    border-bottom-color: ${colors.line} !important;
  }
  .leaflet-control-attribution { background: rgba(251,248,241,0.82); color: ${colors.placeholder}; }
  .leaflet-control-attribution a { color: ${colors.inkSoft}; }
</style>
</head>
<body>
<div id="map"></div>
<script>
  var map, layer;
  // BORDER = anel creme do pin (sobre base clara), não a tinta escura.
  var TERRA = '${colors.wine}', TEAL = '${colors.cyan}', BORDER = '${colors.card}', TRACK = '${colors.gold}';

  function post(o) {
    if (window.ReactNativeWebView) window.ReactNativeWebView.postMessage(JSON.stringify(o));
  }
  function pin(color) {
    return L.divIcon({
      className: 'sj-pin',
      html: '<div style="width:20px;height:20px;border-radius:50%;background:' + color +
            ';border:2px solid ' + BORDER + ';box-shadow:0 2px 6px rgba(43,39,36,.28)"></div>',
      iconSize: [20, 20], iconAnchor: [10, 10]
    });
  }
  function addPin(lat, lng, title, id, color, all) {
    all.push([lat, lng]);
    var m = L.marker([lat, lng], { icon: pin(color), title: title });
    m.on('click', function () { post({ type: 'select', memoryId: id }); });
    m.addTo(layer);
  }
  window.__render = function (data) {
    if (!map || !layer || !data) return;
    layer.clearLayers();
    var all = [];
    (data.journeys || []).forEach(function (j) {
      if (j.route && j.route.coordinates && j.route.coordinates.length >= 2) {
        // GeoJSON é [lng, lat]; Leaflet quer [lat, lng].
        var line = j.route.coordinates.map(function (c) { return [c[1], c[0]]; });
        L.polyline(line, { color: TERRA, weight: 3, opacity: 0.75 }).addTo(layer);
      }
      (j.points || []).forEach(function (p) { addPin(p.latitude, p.longitude, p.title, p.memory_id, TERRA, all); });
    });
    (data.loose_points || []).forEach(function (m) { addPin(m.latitude, m.longitude, m.title, m.memory_id, TEAL, all); });
    // Percursos reais (GPS): traço mais escuro e grosso que o rastro simbólico.
    (data.tracks || []).forEach(function (coords) {
      if (coords && coords.length >= 2) {
        var tline = coords.map(function (c) { return [c[1], c[0]]; });
        L.polyline(tline, { color: TRACK, weight: 4, opacity: 0.9, lineCap: 'round', lineJoin: 'round' }).addTo(layer);
        tline.forEach(function (pt) { all.push(pt); });
      }
    });
    if (all.length === 1) map.setView(all[0], 13);
    else if (all.length > 1) map.fitBounds(all, { padding: [40, 40] });
  };
  function init() {
    map = L.map('map', { center: [-14.235, -51.925], zoom: 4, worldCopyJump: true, minZoom: 2 });
    // Positron (light_all): base clara, do mesmo papel da interface.
    L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
      maxZoom: 20, attribution: '© OpenStreetMap © CARTO'
    }).addTo(map);
    layer = L.layerGroup().addTo(map);
    post({ type: 'ready' });
  }
  if (window.L) { try { init(); } catch (e) { post({ type: 'error' }); } }
  else { post({ type: 'error' }); }
</script>
</body>
</html>`;

export default function AtlasMap({ data, onSelect, tracks }: Props) {
  const webRef = useRef<WebView>(null);
  const onSelectRef = useRef(onSelect);
  onSelectRef.current = onSelect;

  const [ready, setReady] = useState(false);
  const [mapError, setMapError] = useState(false);

  const json = useMemo(
    () => JSON.stringify({ ...(data ?? { loose_points: [], journeys: [] }), tracks: tracks ?? [] }),
    [data, tracks],
  );

  // Injeta os dados quando o mapa está pronto e sempre que os dados mudam.
  useEffect(() => {
    if (ready && webRef.current) {
      webRef.current.injectJavaScript(`window.__render(${json}); true;`);
    }
  }, [json, ready]);

  function onMessage(e: WebViewMessageEvent) {
    try {
      const msg = JSON.parse(e.nativeEvent.data);
      if (msg?.type === "select" && msg.memoryId) onSelectRef.current(msg.memoryId);
      else if (msg?.type === "ready") setReady(true);
      else if (msg?.type === "error") setMapError(true);
    } catch {
      // mensagem inesperada: ignora
    }
  }

  return (
    <View style={s.shell}>
      {!mapError ? (
        <WebView
          ref={webRef}
          style={s.web}
          originWhitelist={["*"]}
          source={{ html: HTML }}
          onMessage={onMessage}
          javaScriptEnabled
          domStorageEnabled
          nestedScrollEnabled
          onError={() => setMapError(true)}
          onHttpError={() => setMapError(true)}
        />
      ) : null}
      {mapError ? (
        <View style={s.overlay}>
          <Text style={s.errText}>Não foi possível carregar o mapa.</Text>
          <Text style={s.hint}>Veja suas memórias pela aba Tempo.</Text>
        </View>
      ) : !ready ? (
        <View style={s.overlay}>
          <ActivityIndicator color={colors.cyan} />
          <Text style={s.hint}>Carregando mapa…</Text>
        </View>
      ) : null}
    </View>
  );
}

const s = StyleSheet.create({
  // Moldura de "arte de álbum": carvão grosso, canto quase reto.
  shell: {
    position: "relative",
    width: "100%",
    height: 380,
    borderRadius: 3,
    overflow: "hidden",
    borderWidth: 3,
    borderColor: colors.frame,
    backgroundColor: colors.sand,
  },
  web: { flex: 1, backgroundColor: colors.sand },
  overlay: { position: "absolute", top: 0, left: 0, right: 0, bottom: 0, alignItems: "center", justifyContent: "center", gap: 6 },
  hint: { color: colors.inkSoft, fontSize: 13, textAlign: "center" },
  errText: { color: colors.danger, fontSize: 14, fontWeight: "600", textAlign: "center" },
});
