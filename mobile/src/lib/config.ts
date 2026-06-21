import { Platform } from "react-native";

// URL base da API.
// - web / simulador iOS: localhost funciona.
// - Android emulator: use "http://10.0.2.2:8000".
// - device físico: use o IP da sua máquina na LAN, ex.: "http://192.168.0.10:8000".
export const API_URL = Platform.select({
  android: "http://10.0.2.2:8000",
  default: "http://127.0.0.1:8000",
});
