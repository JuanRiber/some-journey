import { useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";
import { router } from "expo-router";

import JourneyHeader from "../components/JourneyHeader";
import * as api from "../lib/api";
import { colors } from "../theme/colors";
import { ui } from "../theme/styles";

export default function RegisterScreen() {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function onRegister() {
    setError("");
    setLoading(true);
    try {
      await api.register(name.trim(), email.trim(), password);
      // Cadastro não retorna token: volta para o login (decisão do contrato).
      router.replace("/");
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
        <Text style={ui.title}>Criar conta</Text>
        <Text style={ui.subtitle}>Comece o seu atlas pessoal.</Text>

        <Text style={ui.label}>NOME</Text>
        <TextInput
          style={ui.input}
          value={name}
          onChangeText={setName}
          placeholder="Seu nome"
          placeholderTextColor={colors.placeholder}
        />

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
        <Text style={ui.hint}>Mínimo de 7 caracteres.</Text>

        {error ? (
          <Text style={{ color: "#A32D2D", fontSize: 13, marginTop: 12, textAlign: "center" }}>
            {error}
          </Text>
        ) : null}

        <Pressable
          style={({ pressed }) => [ui.button, pressed && ui.buttonPressed]}
          onPress={onRegister}
          disabled={loading}
        >
          <Text style={ui.buttonText}>{loading ? "Criando..." : "Criar conta"}</Text>
        </Pressable>

        <View style={ui.footerRow}>
          <Text style={ui.footerText}>Já tem conta? </Text>
          <Pressable onPress={() => router.push("/")}>
            <Text style={ui.footerLink}>Entrar</Text>
          </Pressable>
        </View>
      </View>
    </View>
  );
}
