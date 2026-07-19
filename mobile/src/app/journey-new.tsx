import { useState } from "react";
import { Pressable, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";
import { router } from "expo-router";

import * as api from "../lib/api";
import { colors } from "../theme/colors";
import { ui } from "../theme/styles";

// Criar uma jornada (uma viagem, fase, cidade, rotina...). Nasce como rascunho;
// iniciar/pausar/finalizar e adicionar memórias acontecem na tela de detalhe.
export default function JourneyNewScreen() {
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [mood, setMood] = useState("");
  const [isPrivate, setIsPrivate] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  async function onSave() {
    setError("");
    if (!title.trim()) {
      setError("Dê um nome à sua jornada.");
      return;
    }
    setSaving(true);
    try {
      const journey = await api.createJourney({
        title: title.trim(),
        description: description.trim() || null,
        mood: mood.trim() || null,
        is_private: isPrivate,
      });
      // Abre o detalhe da jornada recém-criada para começar a reunir memórias.
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
        <Text style={ui.subtitle}>
          Uma viagem, uma fase da vida, uma cidade ou uma rotina — qualquer conjunto de
          memórias que faça sentido para você.
        </Text>

        <Text style={ui.label}>NOME DA JORNADA</Text>
        <TextInput
          style={ui.input}
          value={title}
          onChangeText={setTitle}
          placeholder="Ex.: Fortaleza Nights"
          placeholderTextColor={colors.placeholder}
        />

        <Text style={ui.label}>DESCRIÇÃO (OPCIONAL)</Text>
        <TextInput
          style={[ui.input, { height: 96, textAlignVertical: "top" }]}
          value={description}
          onChangeText={setDescription}
          placeholder="Noites, ruas e lugares que ficaram marcados..."
          placeholderTextColor={colors.placeholder}
          multiline
        />

        <Text style={ui.label}>ATMOSFERA (OPCIONAL)</Text>
        <TextInput
          style={ui.input}
          value={mood}
          onChangeText={setMood}
          placeholder="Ex.: noturno, nostálgico, urbano"
          placeholderTextColor={colors.placeholder}
        />
        <Text style={ui.hint}>Uma palavra ou clima que resume o sentimento da jornada.</Text>

        <Text style={ui.label}>PRIVACIDADE</Text>
        <Pressable
          style={s.toggleRow}
          onPress={() => setIsPrivate((v) => !v)}
          accessibilityRole="switch"
          accessibilityState={{ checked: isPrivate }}
          accessibilityLabel="Alternar privacidade da jornada"
        >
          <View style={[s.track, isPrivate && s.trackOn]}>
            <View style={[s.knob, isPrivate && s.knobOn]} />
          </View>
          <Text style={s.toggleText}>
            {isPrivate ? "Só você vê esta jornada" : "Pode ser compartilhada"}
          </Text>
        </Pressable>

        {error ? (
          <Text style={{ color: colors.danger, fontSize: 13, marginTop: 14, textAlign: "center" }}>
            {error}
          </Text>
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

const s = StyleSheet.create({
  toggleRow: { flexDirection: "row", alignItems: "center", gap: 12, marginTop: 4 },
  track: {
    width: 46, height: 27, borderRadius: 14, backgroundColor: "rgba(242,234,216,0.16)",
    padding: 3, justifyContent: "center",
  },
  trackOn: { backgroundColor: colors.cyan },
  knob: { width: 21, height: 21, borderRadius: 11, backgroundColor: colors.ink },
  knobOn: { alignSelf: "flex-end" },
  toggleText: { color: colors.inkSoft, fontSize: 14, flex: 1 },
});
