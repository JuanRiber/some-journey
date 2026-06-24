import { useEffect, useState } from "react";
import { router } from "expo-router";

import * as api from "../lib/api";
import { clearToken, getToken } from "../lib/auth";

type AuthState = {
  checking: boolean;
  error: string;
};

export function useRequireAuth(): AuthState {
  const [state, setState] = useState<AuthState>({ checking: true, error: "" });

  useEffect(() => {
    let active = true;

    async function checkSession() {
      setState({ checking: true, error: "" });
      try {
        const token = await getToken();
        if (!token) {
          router.replace("/");
          return;
        }
        await api.me();
        if (active) setState({ checking: false, error: "" });
      } catch (e) {
        if (!active) return;
        if (api.isUnauthorized(e)) {
          await clearToken();
          router.replace("/");
          return;
        }
        setState({
          checking: false,
          error: e instanceof api.ApiError ? e.message : "Nao foi possivel validar sua sessao.",
        });
      }
    }

    checkSession();
    return () => {
      active = false;
    };
  }, []);

  return state;
}
