import { defineConfig, devices } from "@playwright/test";

// E2E do app WEB do Some Journey (Expo Web + Leaflet).
// Pré-requisitos para os fluxos que chamam a API: backend em
// http://127.0.0.1:8000 e o banco (docker) no ar. O smoke de UI (tela de
// login) roda só com o app web, sem backend.
const WEB_URL = process.env.E2E_BASE_URL ?? "http://localhost:8081";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: "html",
  use: {
    baseURL: WEB_URL,
    trace: "on-first-retry",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  // Sobe o app web automaticamente (e reaproveita se você já estiver rodando
  // `npm run web`). NÃO sobe o backend — flows que batem na API precisam dele.
  webServer: {
    command: "npm --prefix mobile run web",
    url: WEB_URL,
    reuseExistingServer: true,
    timeout: 180_000,
  },
});
