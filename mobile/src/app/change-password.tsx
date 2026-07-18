import { useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";
import { router } from "expo-router";

import JourneyHeader from "../components/JourneyHeader";
import * as api from "../lib/api";
import { colors } from "../theme/colors";
import { ui } from "../theme/styles";

// Troca de senha do usuário LOGADO. Confere a senha atual no backend; a nova
// segue a regra do cadastro (min 10). Alcançada pelo Atlas ("Alterar senha").
export default function ChangePasswordScreen() {
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [done, setDone] = useState(false);

  async function onSubmit() {
    setError("");
    if (!current || next.length < 10) {
      setError("Informe a senha atual e uma nova com pelo menos 10 caracteres.");
      return;
    }
    setLoading(true);
    try {
      await api.changePassword(current, next);
      setDone(true);
    } catch (e) {
      // O backend usa 401 para "senha atual incorreta" (além de sessão expirada).
      setError(e instanceof api.ApiError ? e.message : "Não foi possível alterar a senha.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <View style={ui.screen}>
      <JourneyHeader />
      <View style={ui.body}>
        <Pressable style={ui.backWrap} onPress={() => router.back()} accessibilityRole="button" accessibilityLabel="Voltar">
          <Text style={ui.back}>← Voltar</Text>
        </Pressable>

        <Text style={ui.title}>Alterar senha</Text>
        <Text style={ui.subtitle}>Confirme a senha atual e escolha uma nova.</Text>

        {done ? (
          <Text style={{ color: colors.mint, fontSize: 15, lineHeight: 22, marginTop: 22, textAlign: "center" }}>
            Senha alterada! Use a nova no próximo login.
          </Text>
        ) : (
          <>
            <Text style={ui.label}>SENHA ATUAL</Text>
            <TextInput
              style={ui.input}
              value={current}
              onChangeText={setCurrent}
              placeholder="••••••••"
              placeholderTextColor={colors.placeholder}
              secureTextEntry
            />

            <Text style={ui.label}>NOVA SENHA</Text>
            <TextInput
              style={ui.input}
              value={next}
              onChangeText={setNext}
              placeholder="••••••••"
              placeholderTextColor={colors.placeholder}
              secureTextEntry
            />
            <Text style={ui.hint}>Mínimo de 10 caracteres.</Text>

            {error ? (
              <Text style={{ color: colors.danger, fontSize: 13, marginTop: 12, textAlign: "center" }}>
                {error}
              </Text>
            ) : null}

            <Pressable
              style={({ pressed }) => [ui.button, pressed && ui.buttonPressed]}
              onPress={onSubmit}
              disabled={loading}
            >
              <Text style={ui.buttonText}>{loading ? "Alterando..." : "Alterar senha"}</Text>
            </Pressable>
          </>
        )}
      </View>
    </View>
  );
}
