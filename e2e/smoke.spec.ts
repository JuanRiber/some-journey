import { test, expect } from "@playwright/test";

// Smoke: a tela inicial (login) do app web monta e renderiza. Não depende do
// backend — valida que o Expo Web sobe e o app carrega sem tela branca.
test("a tela de login renderiza", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByText("Some Journey")).toBeVisible();
  await expect(page.getByText("A vida deixa rastros.")).toBeVisible();
  await expect(page.getByText("Criar conta")).toBeVisible();
});
