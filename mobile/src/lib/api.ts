import { API_URL } from "./config";

// Erro tipado da API: carrega o status HTTP + a mensagem (detail) do backend.
export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
    this.name = "ApiError";
  }
}

async function post(path: string, body: object) {
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    throw new ApiError(0, "Não foi possível conectar ao servidor. A API está rodando?");
  }

  let data: any = {};
  try {
    data = await res.json();
  } catch {
    // sem corpo JSON
  }

  if (!res.ok) {
    // O backend manda { detail: "..." } em 409/401/403. No 422 (validação) o
    // detail é uma lista — caímos na mensagem genérica.
    const detail =
      typeof data?.detail === "string"
        ? data.detail
        : "Não foi possível concluir. Verifique os dados e tente de novo.";
    throw new ApiError(res.status, detail);
  }
  return data;
}

export function register(name: string, email: string, password: string) {
  return post("/auth/register", { name, email, password });
}

export function login(email: string, password: string) {
  return post("/auth/login", { email, password });
}
