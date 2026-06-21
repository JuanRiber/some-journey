import { Platform } from "react-native";
import * as SecureStore from "expo-secure-store";

// Guarda o JWT com segurança: SecureStore (keychain/keystore) no celular,
// localStorage no web (SecureStore não existe no navegador).
const KEY = "sj_access_token";

export async function setToken(token: string): Promise<void> {
  if (Platform.OS === "web") {
    localStorage.setItem(KEY, token);
    return;
  }
  await SecureStore.setItemAsync(KEY, token);
}

export async function getToken(): Promise<string | null> {
  if (Platform.OS === "web") {
    return localStorage.getItem(KEY);
  }
  return SecureStore.getItemAsync(KEY);
}

export async function clearToken(): Promise<void> {
  if (Platform.OS === "web") {
    localStorage.removeItem(KEY);
    return;
  }
  await SecureStore.deleteItemAsync(KEY);
}
