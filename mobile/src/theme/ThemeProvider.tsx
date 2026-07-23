import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { Appearance, Platform, useColorScheme } from "react-native";
import * as SecureStore from "expo-secure-store";

import { sjDark, sjLight, type SJScheme } from "./tokens";

/**
 * Some Journey — provedor de tema (Expo).
 *
 * Dois modos, uma linguagem: CLARO "papel quente" (PADRÃO) e ESCURO "atlas
 * noturno". O usuário escolhe entre três MODOS:
 * - `light` / `dark`: fixa o esquema, ignorando o sistema.
 * - `system`: segue o aparelho (Appearance/useColorScheme), reagindo em tempo real.
 *
 * A escolha é PERSISTIDA reaproveitando o mesmo padrão de `lib/auth.ts`
 * (SecureStore no nativo, storage do navegador no web). Como a preferência de
 * tema não é sensível — ao contrário do token — no web usamos `localStorage`
 * (persiste entre sessões), não `sessionStorage`.
 *
 * Telas leem `useTheme()` para obter o esquema ATIVO (`scheme`) e alternar
 * (`toggle`, `setMode`), em vez de importar `sjLight`/`sjDark` direto.
 */

export type ThemeMode = "light" | "dark" | "system";

type ThemeContextValue = {
  /** Esquema de cores efetivo já resolvido (o que as telas pintam). */
  scheme: SJScheme;
  /** Preferência bruta escolhida pelo usuário. */
  mode: ThemeMode;
  /** Troca a preferência (e persiste). */
  setMode: (mode: ThemeMode) => void;
  /** Atalho: vai para o oposto do brilho ATUAL (claro↔escuro), fixando o modo. */
  toggle: () => void;
};

const MODE_KEY = "sj_theme_mode";

// Persistência espelhando lib/auth.ts (web usa storage do navegador; nativo,
// SecureStore). Envolvida em try/catch: falha de storage nunca deve derrubar a UI
// — cai no padrão (claro).
async function loadMode(): Promise<ThemeMode | null> {
  try {
    if (Platform.OS === "web") {
      return localStorage.getItem(MODE_KEY) as ThemeMode | null;
    }
    return (await SecureStore.getItemAsync(MODE_KEY)) as ThemeMode | null;
  } catch {
    return null;
  }
}

async function saveMode(mode: ThemeMode): Promise<void> {
  try {
    if (Platform.OS === "web") {
      localStorage.setItem(MODE_KEY, mode);
      return;
    }
    await SecureStore.setItemAsync(MODE_KEY, mode);
  } catch {
    // Silencioso: a preferência apenas não persistirá nesta sessão.
  }
}

/**
 * Resolve o esquema efetivo a partir do modo + brilho do sistema. Aceita o tipo
 * amplo do RN (`light`/`dark`/`null`/`unspecified`): só `dark` vira escuro; tudo
 * mais recai no claro (padrão do produto).
 */
function resolveScheme(mode: ThemeMode, system: string | null | undefined): SJScheme {
  if (mode === "system") {
    return system === "dark" ? sjDark : sjLight;
  }
  return mode === "dark" ? sjDark : sjLight;
}

// Valor padrão SEGURO (igual ao fallback do Flutter `SJTheme.of`): se algum
// componente usar `useTheme()` fora do provedor, assume o modo claro (padrão do
// produto) em vez de estourar. Os setters são no-op nesse caminho.
const defaultValue: ThemeContextValue = {
  scheme: sjLight,
  mode: "light",
  setMode: () => {},
  toggle: () => {},
};

const ThemeContext = createContext<ThemeContextValue>(defaultValue);

export function ThemeProvider({ children }: { children: ReactNode }) {
  // Começa em `light` (padrão do produto) para não piscar antes de hidratar a
  // preferência salva.
  const [mode, setModeState] = useState<ThemeMode>("light");

  // Brilho do sistema (reage a mudanças quando o modo é `system`).
  const system = useColorScheme() ?? null;

  // Hidrata a preferência persistida uma vez, na montagem.
  useEffect(() => {
    let alive = true;
    loadMode().then((saved) => {
      if (alive && saved) setModeState(saved);
    });
    return () => {
      alive = false;
    };
  }, []);

  const setMode = useCallback((next: ThemeMode) => {
    setModeState(next);
    void saveMode(next);
  }, []);

  const toggle = useCallback(() => {
    // Resolve o brilho corrente (respeitando `system`) e vai para o oposto,
    // fixando um modo explícito — o toggle é uma escolha deliberada do usuário.
    const current = resolveScheme(mode, Appearance.getColorScheme() ?? null);
    setMode(current.brightness === "dark" ? "light" : "dark");
  }, [mode, setMode]);

  const value = useMemo<ThemeContextValue>(
    () => ({ scheme: resolveScheme(mode, system), mode, setMode, toggle }),
    [mode, system, setMode, toggle],
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

/** Hook de acesso ao tema ativo (esquema + modo + alternância). */
export function useTheme(): ThemeContextValue {
  return useContext(ThemeContext);
}
