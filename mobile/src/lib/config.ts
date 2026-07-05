import Constants from "expo-constants";
import { Platform } from "react-native";

// Prioridade: EXPO_PUBLIC_API_URL (usado no build web/deploy) > app.json
// (extra.apiUrl) > fallback local por plataforma. Assim o build de produção
// aponta pro backend hospedado sem sujar o dev local.
const envApiUrl = (process.env.EXPO_PUBLIC_API_URL ?? "").trim();
const configuredApiUrl = (Constants.expoConfig?.extra?.apiUrl ?? "").trim();
const chosenApiUrl = envApiUrl || configuredApiUrl;

export const API_URL = chosenApiUrl
  ? chosenApiUrl.replace(/\/$/, "")
  : Platform.select({
      android: "http://10.0.2.2:8000",
      default: "http://127.0.0.1:8000",
    });

// Configurável via app.json (extra.apiTimeoutMs). Padrão 12s; em deploy free
// (backend que "dorme") vale subir para ~20s por causa do cold start.
const configuredTimeout = Constants.expoConfig?.extra?.apiTimeoutMs;
export const API_TIMEOUT_MS =
  typeof configuredTimeout === "number" && configuredTimeout > 0
    ? configuredTimeout
    : 12000;
