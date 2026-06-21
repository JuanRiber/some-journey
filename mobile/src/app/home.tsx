import { useEffect, useState } from "react";
import { ActivityIndicator, Pressable, Text, View } from "react-native";
import { router } from "expo-router";

import JourneyHeader from "../components/JourneyHeader";
import { clearToken, getToken } from "../lib/auth";
import { API_URL } from "../lib/config";
import { colors } from "../theme/colors";
import { ui } from "../theme/styles";

type Me = {
  id: string;
  name: string;
  email: string;
  is_active: boolean;
  created_at: string;
};

export default function HomeScreen() {
  const [me, setMe] = useState<Me | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    (async () => {
      const token = await getToken();
      if (!token) {
        router.replace("/");
        return;
      }
      try {
        const res = await fetch(`${API_URL}/auth/me`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!res.ok) throw new Error("invalid");
        setMe((await res.json()) as Me);
      } catch {
        setError("Sua sessão expirou. Entre novamente.");
      }
    })();
  }, []);

  async function logout() {
    await clearToken();
    router.replace("/");
  }

  return (
    <View style={ui.screen}>
      <JourneyHeader />
      <View style={ui.body}>
        {!me && !error ? (
          <ActivityIndicator color={colors.terra} />
        ) : error ? (
          <>
            <Text style={ui.title}>Ops</Text>
            <Text style={ui.subtitle}>{error}</Text>
            <Pressable
              style={({ pressed }) => [ui.button, pressed && ui.buttonPressed]}
              onPress={logout}
            >
              <Text style={ui.buttonText}>Voltar ao login</Text>
            </Pressable>
          </>
        ) : (
          <>
            <Text style={ui.title}>Bem-vindo, {me!.name.split(" ")[0]}</Text>
            <Text style={ui.subtitle}>
              Você está dentro do seu atlas — {me!.email}.
            </Text>
            <Text style={{ color: colors.inkSoft, fontSize: 13, marginTop: 18, lineHeight: 20 }}>
              Aqui vai entrar o mapa das suas memórias.
            </Text>
            <Pressable
              style={({ pressed }) => [ui.button, pressed && ui.buttonPressed]}
              onPress={logout}
            >
              <Text style={ui.buttonText}>Sair</Text>
            </Pressable>
          </>
        )}
      </View>
    </View>
  );
}
