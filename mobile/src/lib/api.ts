import { Platform } from "react-native";

import { getToken } from "./auth";
import { API_TIMEOUT_MS, API_URL } from "./config";

// Erro tipado da API: carrega o status HTTP + a mensagem (detail) do backend.
export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
    this.name = "ApiError";
  }
}

async function request(method: string, path: string, body?: object, authed = false) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (authed) {
    const token = await getToken();
    if (token) headers.Authorization = `Bearer ${token}`;
  }

  const ctrl = new AbortController();
  const timeout = setTimeout(() => ctrl.abort(), API_TIMEOUT_MS);
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
      signal: ctrl.signal,
    });
  } catch (e) {
    const errorName = e && typeof e === "object" && "name" in e ? String(e.name) : "";
    if (errorName === "AbortError") {
      throw new ApiError(0, "Tempo esgotado ao conectar ao servidor.");
    }
    throw new ApiError(0, "Nao foi possivel conectar ao servidor. A API esta rodando?");
  } finally {
    clearTimeout(timeout);
  }

  if (res.status === 204) return null; // sem corpo (ex.: DELETE)

  let data: any = {};
  try {
    data = await res.json();
  } catch {
    // sem corpo JSON
  }

  if (!res.ok) {
    // 409/401/403/404 mandam { detail: "..." }. No 422 (validação) o detail é
    // uma lista — caímos na mensagem genérica.
    const detail =
      typeof data?.detail === "string"
        ? data.detail
        : "Não foi possível concluir. Verifique os dados e tente de novo.";
    throw new ApiError(res.status, detail);
  }
  return data;
}

// --- Públicas ---
export function register(name: string, email: string, password: string) {
  return request("POST", "/auth/register", { name, email, password });
}

export function login(email: string, password: string) {
  return request("POST", "/auth/login", { email, password });
}

// --- Autenticadas (token no header) ---
export function me() {
  return request("GET", "/auth/me", undefined, true);
}

// Troca de senha do usuário logado (confere a atual no backend). 204 sem corpo.
export function changePassword(currentPassword: string, newPassword: string): Promise<null> {
  return request(
    "POST",
    "/auth/change-password",
    { current_password: currentPassword, new_password: newPassword },
    true,
  );
}

export type MemoryInput = {
  title: string;
  text: string;
  latitude: number;
  longitude: number;
  occurred_at: string;
};

// Foto de uma memória: id (para remover) + URL assinada temporária.
export type MemoryImage = { id: string; url: string };

// Memória como a API devolve (MemoryRead). `images` = todas as fotos, na ordem;
// `image_url` = a primeira (capa), null se não houver.
export type Memory = MemoryInput & {
  id: string;
  created_at: string;
  images: MemoryImage[];
  image_url: string | null;
};

export async function listMemories(): Promise<Memory[]> {
  // Blindagem: se o servidor responder 200 sem um array válido, devolve [] em vez
  // de deixar um objeto vazar para for-of/.map e quebrar o render da Timeline.
  const data = await request("GET", "/memories", undefined, true);
  return Array.isArray(data) ? data : [];
}

export function getMemory(id: string): Promise<Memory> {
  return request("GET", `/memories/${id}`, undefined, true);
}

export function createMemory(memory: MemoryInput): Promise<Memory> {
  return request("POST", "/memories", memory, true);
}

// Atualização parcial (PATCH). Backend aceita só os campos enviados; latitude e
// longitude precisam ir juntas (validação no MemoryUpdate do backend).
export type MemoryPatch = Partial<MemoryInput>;

export function updateMemory(id: string, patch: MemoryPatch): Promise<Memory> {
  return request("PATCH", `/memories/${id}`, patch, true);
}

// Imagem escolhida pelo expo-image-picker (forma mínima que precisamos).
export type PickedImage = { uri: string; mimeType?: string | null; fileName?: string | null };

// Upload da imagem (multipart). NÃO setamos Content-Type — o fetch monta o
// boundary. No web convertemos a uri em Blob; no nativo o objeto {uri,name,type}
// é o formato aceito pelo FormData do React Native.
export async function addMemoryImage(id: string, asset: PickedImage): Promise<Memory> {
  const token = await getToken();
  const type = asset.mimeType || "image/jpeg";
  const name = asset.fileName || `photo.${type.split("/")[1] || "jpg"}`;
  const form = new FormData();
  if (Platform.OS === "web") {
    const blob = await (await fetch(asset.uri)).blob();
    form.append("file", blob, name);
  } else {
    form.append("file", { uri: asset.uri, name, type } as any);
  }

  const ctrl = new AbortController();
  const timeout = setTimeout(() => ctrl.abort(), API_TIMEOUT_MS * 3); // upload pode demorar mais
  let res: Response;
  try {
    res = await fetch(`${API_URL}/memories/${id}/images`, {
      method: "POST",
      headers: token ? { Authorization: `Bearer ${token}` } : {},
      body: form,
      signal: ctrl.signal,
    });
  } catch (e) {
    const n = e && typeof e === "object" && "name" in e ? String((e as { name?: unknown }).name) : "";
    throw new ApiError(0, n === "AbortError" ? "Tempo esgotado ao enviar a imagem." : "Falha ao enviar a imagem.");
  } finally {
    clearTimeout(timeout);
  }

  let data: any = {};
  try {
    data = await res.json();
  } catch {
    // sem corpo
  }
  if (!res.ok) {
    const detail = typeof data?.detail === "string" ? data.detail : "Não foi possível enviar a imagem.";
    throw new ApiError(res.status, detail);
  }
  return data;
}

// Soft delete no backend (204 sem corpo) — aqui só disparamos e confirmamos.
export function deleteMemory(id: string): Promise<null> {
  return request("DELETE", `/memories/${id}`, undefined, true);
}

// Remove UMA foto da memória (por id da foto). Devolve a memória atualizada.
export function deleteMemoryImage(id: string, imageId: string): Promise<Memory> {
  return request("DELETE", `/memories/${id}/images/${imageId}`, undefined, true);
}

// --- Jornadas (fases) ---

export type JourneyStatus = "draft" | "active" | "paused" | "finished";

export type Journey = {
  id: string;
  title: string;
  description: string | null;
  mood: string | null;
  is_private: boolean;
  cover_image_url: string | null;
  status: JourneyStatus;
  started_at: string | null;
  ended_at: string | null;
  points_count: number;
  created_at: string;
};

export type JourneyPoint = {
  memory_id: string;
  position: number;
  title: string;
  text: string;
  latitude: number;
  longitude: number;
  occurred_at: string;
  created_at: string;
};

export type JourneyRoute = { type: "LineString"; coordinates: number[][] };

export type JourneyDetail = Journey & {
  points: JourneyPoint[];
  route: JourneyRoute | null;
};

export type JourneyCreateInput = {
  title: string;
  description?: string | null;
  mood?: string | null;
  is_private?: boolean;
  started_at?: string | null;
  ended_at?: string | null;
};

export async function listJourneys(): Promise<Journey[]> {
  const data = await request("GET", "/journeys", undefined, true);
  return Array.isArray(data) ? data : [];
}

export function getJourney(id: string): Promise<JourneyDetail> {
  return request("GET", `/journeys/${id}`, undefined, true);
}

export function createJourney(input: JourneyCreateInput): Promise<Journey> {
  return request("POST", "/journeys", input, true);
}

// Edita os metadados da jornada (título/descrição). Só os campos enviados mudam;
// não mexe no ciclo de vida (que tem endpoints próprios de start/pause/etc.).
export type JourneyUpdateInput = {
  title?: string;
  description?: string;
  mood?: string | null;
  is_private?: boolean;
  started_at?: string | null;
  ended_at?: string | null;
};

export function updateJourney(id: string, patch: JourneyUpdateInput): Promise<Journey> {
  return request("PATCH", `/journeys/${id}`, patch, true);
}

// Memórias da jornada em ordem cronológica (timeline própria da jornada).
export async function listJourneyMemories(id: string): Promise<Memory[]> {
  const data = await request("GET", `/journeys/${id}/memories`, undefined, true);
  return Array.isArray(data) ? data : [];
}

export function startJourney(id: string): Promise<Journey> {
  return request("POST", `/journeys/${id}/start`, undefined, true);
}

export function pauseJourney(id: string): Promise<Journey> {
  return request("POST", `/journeys/${id}/pause`, undefined, true);
}

export function resumeJourney(id: string): Promise<Journey> {
  return request("POST", `/journeys/${id}/resume`, undefined, true);
}

export function finishJourney(id: string): Promise<Journey> {
  return request("POST", `/journeys/${id}/finish`, undefined, true);
}

// Vincula uma memória existente (ponto solto) à jornada.
export function addJourneyPoint(id: string, memoryId: string): Promise<JourneyDetail> {
  return request("POST", `/journeys/${id}/points`, { memory_id: memoryId }, true);
}

// Cria uma memória já vinculada à jornada (atômico no backend).
export function createMemoryInJourney(id: string, memory: MemoryInput): Promise<JourneyDetail> {
  return request("POST", `/journeys/${id}/memories`, memory, true);
}

// Desvincula sem apagar a memória (204 sem corpo).
export function unlinkJourneyPoint(id: string, memoryId: string): Promise<null> {
  return request("DELETE", `/journeys/${id}/points/${memoryId}`, undefined, true);
}

export function reorderJourneyPoints(id: string, memoryIds: string[]): Promise<JourneyDetail> {
  return request("PATCH", `/journeys/${id}/points/reorder`, { memory_ids: memoryIds }, true);
}

export function deleteJourney(id: string): Promise<null> {
  return request("DELETE", `/journeys/${id}`, undefined, true);
}

// --- Percurso real (GPS) da jornada ---

// Um trecho de percurso (uma sessão de gravação GPS).
export type Track = {
  id: string;
  journey_id: string;
  source: string;
  started_at: string;
  ended_at: string | null;
  is_active: boolean;
  point_count: number;
  distance_m: number;
  created_at: string;
};

// Um ponto GPS enviado ao backend (lote). recorded_at = ISO do momento capturado.
export type TrackPointInput = {
  latitude: number;
  longitude: number;
  accuracy?: number | null;
  altitude?: number | null;
  speed?: number | null;
  heading?: number | null;
  recorded_at: string;
};

// GeoJSON do mapa da jornada (percurso real + memórias + rastro simbólico).
export type GeoLineString = { type: "LineString"; coordinates: number[][] };
export type GeoPoint = { type: "Point"; coordinates: number[] };
export type TrackFeature = {
  type: "Feature";
  properties: {
    track_id: string;
    source: string;
    started_at: string;
    ended_at: string | null;
    point_count: number;
    distance_m: number;
  };
  geometry: GeoLineString;
};
export type JourneyMemoryFeature = {
  type: "Feature";
  properties: { memory_id: string; title: string; image_url: string | null; memory_date: string };
  geometry: GeoPoint;
};
export type JourneyMapResponse = {
  journey: { id: string; title: string };
  tracks: { type: "FeatureCollection"; features: TrackFeature[] };
  memories: { type: "FeatureCollection"; features: JourneyMemoryFeature[] };
  symbolic_route: JourneyRoute | null;
  distance_m: number;
};

export type TrackSource = "gps_live" | "manual" | "imported";

// Abre um trecho de gravação (409 se já houver um aberto na jornada).
export function startTrack(journeyId: string, source: TrackSource = "gps_live"): Promise<Track> {
  return request("POST", `/journeys/${journeyId}/tracks/start`, { source }, true);
}

// Envia pontos GPS em lote ao trecho aberto. Devolve o trecho atualizado.
export function addTrackPoints(
  journeyId: string,
  trackId: string,
  points: TrackPointInput[],
): Promise<Track> {
  return request("POST", `/journeys/${journeyId}/tracks/${trackId}/points`, { points }, true);
}

// Finaliza o trecho aberto (idempotente).
export function finishTrack(journeyId: string, trackId: string): Promise<Track> {
  return request("POST", `/journeys/${journeyId}/tracks/${trackId}/finish`, undefined, true);
}

export async function listTracks(journeyId: string): Promise<Track[]> {
  const data = await request("GET", `/journeys/${journeyId}/tracks`, undefined, true);
  return Array.isArray(data) ? data : [];
}

// Remove o percurso (não apaga as memórias). 204 sem corpo.
export function deleteTrack(journeyId: string, trackId: string): Promise<null> {
  return request("DELETE", `/journeys/${journeyId}/tracks/${trackId}`, undefined, true);
}

// Mapa da jornada em GeoJSON: percurso real + memórias + rastro simbólico.
export function getJourneyMap(journeyId: string): Promise<JourneyMapResponse> {
  return request("GET", `/journeys/${journeyId}/map`, undefined, true);
}

// --- Mapa principal (pins soltos + jornadas com rastro) ---

export type MapPoint = {
  memory_id: string;
  title: string;
  latitude: number;
  longitude: number;
  occurred_at: string;
  position: number | null;
};

export type MapJourney = {
  id: string;
  title: string;
  status: JourneyStatus;
  points: MapPoint[];
  route: JourneyRoute | null;
};

export type MapResponse = { loose_points: MapPoint[]; journeys: MapJourney[] };

export function getMap(opts?: { bbox?: string; journeyId?: string }): Promise<MapResponse> {
  const params = new URLSearchParams();
  if (opts?.bbox) params.set("bbox", opts.bbox);
  if (opts?.journeyId) params.set("journey_id", opts.journeyId);
  const qs = params.toString();
  return request("GET", `/map${qs ? `?${qs}` : ""}`, undefined, true);
}

// --- Helpers de erro: a MESMA regra em toda tela autenticada (load e mutação) ---

// 401: sessão inválida/expirada → a tela deve voltar ao login.
export function isUnauthorized(e: unknown): boolean {
  return e instanceof ApiError && e.status === 401;
}

// Para o usuário, qualquer id inacessível é "não encontrada": 404 (inexistente ou
// de outro dono — anti-enumeração) e 422 (UUID malformado em deep-link) caem no
// mesmo texto, sem vazar a string crua do backend nem revelar existência.
export function isNotFound(e: unknown): boolean {
  return e instanceof ApiError && (e.status === 404 || e.status === 422);
}
