import { useState } from "react";
import { Pressable, ScrollView, Text, TextInput, View } from "react-native";
import { router, useLocalSearchParams } from "expo-router";

import DateField from "../components/DateField";
import ImagePickerField from "../components/ImagePickerField";
import LocationPicker from "../components/LocationPicker";
import * as api from "../lib/api";
import { colors } from "../theme/colors";
import { ui } from "../theme/styles";

function todayISODate(): string {
  return new Date().toISOString().slice(0, 10); // AAAA-MM-DD
}

export default function MemoryNewScreen() {
  // journeyId opcional: quando presente, a memória já nasce vinculada à jornada
  // (modo jornada — o ponto entra em sequência no rastro).
  const { journeyId } = useLocalSearchParams<{ journeyId?: string }>();
  const [title, setTitle] = useState("");
  const [text, setText] = useState("");
  const [date, setDate] = useState(todayISODate());
  const [coords, setCoords] = useState<{ latitude: number; longitude: number } | null>(null);
  const [placeLabel, setPlaceLabel] = useState("");
  const [image, setImage] = useState<api.PickedImage | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function onSave() {
    setError("");
    if (!title.trim()) {
      setError("Dê um título à memória.");
      return;
    }
    if (!coords) {
      setError("Escolha um local: busque, use sua localização ou toque no mapa.");
      return;
    }
    if (!date) {
      setError("Escolha a data.");
      return;
    }
    setLoading(true);
    const payload = {
      title: title.trim(),
      text: text.trim(),
      latitude: coords.latitude,
      longitude: coords.longitude,
      occurred_at: `${date.trim()}T12:00:00Z`,
    };
    try {
      let memId: string | null = null;
      if (journeyId) {
        // Modo jornada: cria a memória já vinculada (o novo ponto é o último).
        const detail = await api.createMemoryInJourney(journeyId, payload);
        memId = detail.points[detail.points.length - 1]?.memory_id ?? null;
      } else {
        const mem = await api.createMemory(payload);
        memId = mem.id;
      }
      // Foto opcional: sobe após criar a memória (precisa do id). Se o Storage
      // não estiver configurado, isto retorna 503 e a mensagem é exibida.
      if (image && memId) await api.uploadMemoryImage(memId, image);
      router.replace(journeyId ? `/journeys/${journeyId}` : "/timeline");
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
          onPress={() =>
            router.canGoBack()
              ? router.back()
              : router.replace(journeyId ? `/journeys/${journeyId}` : "/atlas")
          }
          accessibilityRole="button"
          accessibilityLabel="Voltar"
        >
          <Text style={ui.back}>← Voltar</Text>
        </Pressable>

        <Text style={[ui.title, { marginTop: 12 }]}>
          {journeyId ? "Nova memória na jornada" : "Nova memória"}
        </Text>
        <Text style={ui.subtitle}>
          {journeyId
            ? "Este ponto entra em sequência no rastro da jornada."
            : "Um acontecimento, um lugar, um momento."}
        </Text>

        <Text style={ui.label}>TÍTULO</Text>
        <TextInput
          style={ui.input}
          value={title}
          onChangeText={setTitle}
          placeholder="Ex.: Fim de tarde em Jericoacoara"
          placeholderTextColor={colors.placeholder}
        />

        <Text style={ui.label}>O QUE ACONTECEU (OPCIONAL)</Text>
        <TextInput
          style={[ui.input, { height: 110, textAlignVertical: "top" }]}
          value={text}
          onChangeText={setText}
          placeholder="Conte a memória..."
          placeholderTextColor={colors.placeholder}
          multiline
        />

        <Text style={ui.label}>QUANDO</Text>
        <DateField value={date} onChange={setDate} />

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

        <Text style={ui.label}>FOTO (OPCIONAL)</Text>
        <ImagePickerField value={image} onChange={setImage} />

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
