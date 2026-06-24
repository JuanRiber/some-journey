import { Platform } from "react-native";
import * as SecureStore from "expo-secure-store";

// Native stores the JWT in SecureStore. Web uses sessionStorage to reduce token
// lifetime in browser storage; production web should prefer HttpOnly cookies.
const KEY = "sj_access_token";

export async function setToken(token: string): Promise<void> {
  if (Platform.OS === "web") {
    localStorage.removeItem(KEY);
    sessionStorage.setItem(KEY, token);
    return;
  }
  await SecureStore.setItemAsync(KEY, token);
}

export async function getToken(): Promise<string | null> {
  if (Platform.OS === "web") {
    return sessionStorage.getItem(KEY);
  }
  return SecureStore.getItemAsync(KEY);
}

export async function clearToken(): Promise<void> {
  if (Platform.OS === "web") {
    sessionStorage.removeItem(KEY);
    localStorage.removeItem(KEY);
    return;
  }
  await SecureStore.deleteItemAsync(KEY);
}
