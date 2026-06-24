import Constants from "expo-constants";
import { Platform } from "react-native";

const configuredApiUrl = Constants.expoConfig?.extra?.apiUrl;

export const API_URL =
  typeof configuredApiUrl === "string" && configuredApiUrl.trim()
    ? configuredApiUrl.trim().replace(/\/$/, "")
    : Platform.select({
        android: "http://10.0.2.2:8000",
        default: "http://127.0.0.1:8000",
      });

export const API_TIMEOUT_MS = 12000;
