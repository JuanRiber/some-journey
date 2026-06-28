import { useState } from "react";
import { Pressable, ScrollView, Text, TextInput, View } from "react-native";
import { router } from "expo-router";

import * as api from "../lib/api";
import { colors } from "../theme/colors";
import { ui } from "../theme/styles";

// Criar uma jornada (fase/trajetória). Nasce como "rascunho"; iniciar/pausar/
// finalizar e adicionar pontos acontecem na tela de detalhe.
export default function JourneyNewScreen() {
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  async function onSave() {
    setError("");
    if (!title.trim()) {
      setError("Dê um título à jornada.");
      return;
    }
    setSaving(true);
    try {
      const journey = await api.createJourney({
        title: title.trim(),
        description: description.trim() || null,
      });
      // Abre o detalhe da jornada recém-criada para começar a adicionar pontos.
      router.replace(`/journeys/${journey.id}`);
    } catch (e) {
      if (api.isUnauthorized(e)) {
        router.replace("/");
        return;
      }
      setError(e instanceof api.ApiError ? e.message : "Erro ao salvar.");
      setSaving(false);
    }
  }

  return (
    <ScrollView style={ui.screen} contentContainerStyle={{ paddingBottom: 48 }}>
      <View style={{ paddingTop: 50, paddingHorizontal: 28 }}>
        <Pressable
          onPress={() => (router.canGoBack() ? router.back() : router.replace("/journeys"))}
          accessibilityRole="button"
          accessibilityLabel="Voltar"
        >
          <Text style={ui.back}>← Voltar</Text>
        </Pressable>

        <Text style={[ui.title, { marginTop: 12 }]}>Nova jornada</Text>
        <Text style={ui.subtitle}>Uma fase, uma viagem, uma trajetória que conecta memórias.</Text>

        <Text style={ui.label}>TÍTULO</Text>
        <TextInput
          style={ui.input}
          value={title}
          onChangeText={setTitle}
          placeholder="Ex.: Viagem pelos EUA"
          placeholderTextColor={colors.placeholder}
        />

        <Text style={ui.label}>DESCRIÇÃO (OPCIONAL)</Text>
        <TextInput
          style={[ui.input, { height: 96, textAlignVertical: "top" }]}
          value={description}
          onChangeText={setDescription}
          placeholder="Sobre o que é esta jornada..."
          placeholderTextColor={colors.placeholder}
          multiline
        />

        {error ? (
          <Text style={{ color: colors.danger, fontSize: 13, marginTop: 12, textAlign: "center" }}>{error}</Text>
        ) : null}

        <Pressable
          style={({ pressed }) => [ui.button, pressed && ui.buttonPressed]}
          onPress={onSave}
          disabled={saving}
        >
          <Text style={ui.buttonText}>{saving ? "Criando..." : "Criar jornada"}</Text>
        </Pressable>
      </View>
    </ScrollView>
  );
}
