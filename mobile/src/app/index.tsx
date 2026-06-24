import { useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";
import { router } from "expo-router";

import JourneyHeader from "../components/JourneyHeader";
import * as api from "../lib/api";
import { setToken } from "../lib/auth";
import { colors } from "../theme/colors";
import { ui } from "../theme/styles";

export default function LoginScreen() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function onLogin() {
    setError("");
    setLoading(true);
    try {
      const res = await api.login(email.trim(), password);
      await setToken(res.access_token);
      router.replace("/atlas");
    } catch (e) {
      setError(e instanceof api.ApiError ? e.message : "Erro inesperado.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <View style={ui.screen}>
      <JourneyHeader />

      <View style={ui.body}>
        <View style={ui.brandRow}>
          <View style={ui.pin} />
          <Text style={ui.wordmark}>Some Journey</Text>
        </View>
        <Text style={ui.tagline}>A vida deixa rastros.</Text>

        <Text style={ui.label}>E-MAIL</Text>
        <TextInput
          style={ui.input}
          value={email}
          onChangeText={setEmail}
          placeholder="voce@email.com"
          placeholderTextColor={colors.placeholder}
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="email-address"
        />

        <Text style={ui.label}>SENHA</Text>
        <TextInput
          style={ui.input}
          value={password}
          onChangeText={setPassword}
          placeholder="••••••••"
          placeholderTextColor={colors.placeholder}
          secureTextEntry
        />

        <Pressable style={ui.forgotWrap} onPress={() => router.push("/forgot-password")}>
          <Text style={ui.forgot}>Esqueci minha senha</Text>
        </Pressable>

        {error ? (
          <Text style={{ color: "#A32D2D", fontSize: 13, marginTop: 12, textAlign: "center" }}>
            {error}
          </Text>
        ) : null}

        <Pressable
          style={({ pressed }) => [ui.button, pressed && ui.buttonPressed]}
          onPress={onLogin}
          disabled={loading}
        >
          <Text style={ui.buttonText}>{loading ? "Entrando..." : "Entrar"}</Text>
        </Pressable>

        <View style={ui.footerRow}>
          <Text style={ui.footerText}>Não tem conta? </Text>
          <Pressable onPress={() => router.push("/register")}>
            <Text style={ui.footerLink}>Criar conta</Text>
          </Pressable>
        </View>
      </View>
    </View>
  );
}
