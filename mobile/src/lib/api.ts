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

export type MemoryInput = {
  title: string;
  text: string;
  latitude: number;
  longitude: number;
  occurred_at: string;
};

// Memória como a API devolve (MemoryRead). `image_url` é null até o upload existir.
export type Memory = MemoryInput & {
  id: string;
  created_at: string;
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

// Soft delete no backend (204 sem corpo) — aqui só disparamos e confirmamos.
export function deleteMemory(id: string): Promise<null> {
  return request("DELETE", `/memories/${id}`, undefined, true);
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
