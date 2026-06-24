// Geocodificação via Nominatim (OpenStreetMap) — grátis, sem chave de API.
// CORS confirmado no navegador. Política de uso do Nominatim: ~1 req/s — por
// isso as telas fazem busca com debounce. No web o navegador já envia
// User-Agent/Referer (identificação que a política pede); no nativo e em
// produção, prefira um provedor com chave ou self-host do Nominatim.
//
// O backend continua falando latitude/longitude: o "label" do lugar é só para
// a UI (confiança do usuário), nunca é enviado nem persistido.
// Privacidade: a query digitada e as coordenadas (reverse) saem para o OSM.

export type GeoResult = {
  label: string;
  latitude: number;
  longitude: number;
};

const BASE = "https://nominatim.openstreetmap.org";

export async function searchPlaces(query: string, signal?: AbortSignal): Promise<GeoResult[]> {
  const url =
    `${BASE}/search?q=${encodeURIComponent(query)}` +
    `&format=jsonv2&limit=6&addressdetails=1&accept-language=pt-BR`;
  const res = await fetch(url, { headers: { Accept: "application/json" }, signal });
  // Propaga falha (429/5xx/rede) em vez de fingir "nenhum resultado" — a tela
  // distingue erro de busca de lista vazia.
  if (!res.ok) throw new Error(`Nominatim respondeu ${res.status}`);
  const data = await res.json();
  if (!Array.isArray(data)) return [];
  return data
    .map((it: any) => ({
      label: String(it.display_name ?? ""),
      latitude: parseFloat(it.lat),
      longitude: parseFloat(it.lon),
    }))
    .filter((r) => Number.isFinite(r.latitude) && Number.isFinite(r.longitude));
}

export async function reverseGeocode(
  latitude: number,
  longitude: number,
  signal?: AbortSignal,
): Promise<string> {
  try {
    const url = `${BASE}/reverse?lat=${latitude}&lon=${longitude}&format=jsonv2&accept-language=pt-BR`;
    const res = await fetch(url, { headers: { Accept: "application/json" }, signal });
    if (!res.ok) return "";
    const data = await res.json();
    return typeof data?.display_name === "string" ? data.display_name : "";
  } catch {
    return "";
  }
}
