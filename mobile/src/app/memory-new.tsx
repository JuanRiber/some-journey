import { useState } from "react";
import { Pressable, ScrollView, Text, TextInput, View } from "react-native";
import { router } from "expo-router";

import LocationPicker from "../components/LocationPicker";
import * as api from "../lib/api";
import { colors } from "../theme/colors";
import { ui } from "../theme/styles";

function todayISODate(): string {
  return new Date().toISOString().slice(0, 10); // AAAA-MM-DD
}

export default function MemoryNewScreen() {
  const [title, setTitle] = useState("");
  const [text, setText] = useState("");
  const [date, setDate] = useState(todayISODate());
  const [coords, setCoords] = useState<{ latitude: number; longitude: number } | null>(null);
  const [placeLabel, setPlaceLabel] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function onSave() {
    setError("");
    if (!title.trim() || !text.trim()) {
      setError("Dê um título e conte a memória.");
      return;
    }
    if (!coords) {
      setError("Escolha um local: busque, use sua localização ou toque no mapa.");
      return;
    }
    // Valida a data (campo livre AAAA-MM-DD) antes de montar o occurred_at —
    // inclusive datas impossíveis como 2023-02-31 (que o Date "rolaria").
    const dm = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date.trim());
    const dt = dm ? new Date(`${date.trim()}T12:00:00Z`) : null;
    if (
      !dm ||
      !dt ||
      Number.isNaN(dt.getTime()) ||
      dt.getUTCFullYear() !== +dm[1] ||
      dt.getUTCMonth() + 1 !== +dm[2] ||
      dt.getUTCDate() !== +dm[3]
    ) {
      setError("Use uma data válida no formato AAAA-MM-DD.");
      return;
    }
    setLoading(true);
    try {
      await api.createMemory({
        title: title.trim(),
        text: text.trim(),
        latitude: coords.latitude,
        longitude: coords.longitude,
        occurred_at: `${date}T12:00:00Z`,
      });
      // Volta para a Timeline: a memória recém-criada aparece no topo da lista.
      router.replace("/timeline");
    } catch (e) {
      if (api.isUnauthorized(e)) {
        router.replace("/");
        return;
      }
      setError(e instanceof api.ApiError ? e.message : "Erro ao salvar.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <ScrollView style={ui.screen} contentContainerStyle={{ paddingBottom: 48 }}>
      <View style={{ paddingTop: 50, paddingHorizontal: 28 }}>
        <Pressable
          onPress={() => (router.canGoBack() ? router.back() : router.replace("/atlas"))}
          accessibilityRole="button"
          accessibilityLabel="Voltar"
        >
          <Text style={ui.back}>← Voltar</Text>
        </Pressable>

        <Text style={[ui.title, { marginTop: 12 }]}>Nova memória</Text>
        <Text style={ui.subtitle}>Um acontecimento, um lugar, um momento.</Text>

        <Text style={ui.label}>TÍTULO</Text>
        <TextInput
          style={ui.input}
          value={title}
          onChangeText={setTitle}
          placeholder="Ex.: Fim de tarde em Jericoacoara"
          placeholderTextColor={colors.placeholder}
        />

        <Text style={ui.label}>O QUE ACONTECEU</Text>
        <TextInput
          style={[ui.input, { height: 110, textAlignVertical: "top" }]}
          value={text}
          onChangeText={setText}
          placeholder="Conte a memória..."
          placeholderTextColor={colors.placeholder}
          multiline
        />

        <Text style={ui.label}>QUANDO (AAAA-MM-DD)</Text>
        <TextInput
          style={ui.input}
          value={date}
          onChangeText={setDate}
          placeholder="2023-07-15"
          placeholderTextColor={colors.placeholder}
          autoCapitalize="none"
        />

        <Text style={ui.label}>LOCALIZAÇÃO</Text>
        <LocationPicker
          latitude={coords?.latitude ?? null}
          longitude={coords?.longitude ?? null}
          label={placeLabel}
          onChange={(latitude, longitude, lbl) => {
            setCoords({ latitude, longitude });
            if (lbl !== undefined) setPlaceLabel(lbl);
          }}
        />

        {error ? (
          <Text style={{ color: "#A32D2D", fontSize: 13, marginTop: 12, textAlign: "center" }}>
            {error}
          </Text>
        ) : null}

        <Pressable
          style={({ pressed }) => [ui.button, pressed && ui.buttonPressed]}
          onPress={onSave}
          disabled={loading}
        >
          <Text style={ui.buttonText}>{loading ? "Salvando..." : "Salvar memória"}</Text>
        </Pressable>
      </View>
    </ScrollView>
  );
}
