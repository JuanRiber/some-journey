import { useEffect, useState } from "react";
import { ActivityIndicator, Pressable, ScrollView, Text, TextInput, View } from "react-native";
import { router, useLocalSearchParams } from "expo-router";

import ImagePickerField from "../../components/ImagePickerField";
import LocationPicker from "../../components/LocationPicker";
import * as api from "../../lib/api";
import { colors } from "../../theme/colors";
import { ui } from "../../theme/styles";

// Editar memória: espelha a tela de criar, mas pré-carrega a memória pelo id e
// salva com PATCH (atualização parcial). Segurança: 404/422 (inexistente, de
// outro dono ou UUID malformado) viram "Memória não encontrada." (anti-enumeração).
export default function MemoryEditScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [title, setTitle] = useState("");
  const [text, setText] = useState("");
  const [date, setDate] = useState("");
  const [coords, setCoords] = useState<{ latitude: number; longitude: number } | null>(null);
  const [placeLabel, setPlaceLabel] = useState("");
  const [image, setImage] = useState<api.PickedImage | null>(null);
  const [existingImageUrl, setExistingImageUrl] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    if (!id) {
      setLoadError("Memória não encontrada.");
      return;
    }
    api
      .getMemory(id)
      .then((m) => {
        if (!active) return;
        setTitle(m.title);
        setText(m.text);
        setDate(m.occurred_at.slice(0, 10)); // ISO -> AAAA-MM-DD
        setCoords({ latitude: m.latitude, longitude: m.longitude });
        setExistingImageUrl(m.image_url);
        setLoaded(true);
      })
      .catch((e) => {
        if (!active) return;
        if (api.isUnauthorized(e)) {
          router.replace("/");
          return;
        }
        if (api.isNotFound(e)) {
          setLoadError("Memória não encontrada.");
          return;
        }
        setLoadError(e instanceof api.ApiError ? e.message : "Erro ao carregar.");
      });
    return () => {
      active = false;
    };
  }, [id]);

  function goBack() {
    if (router.canGoBack()) router.back();
    else router.replace(`/memory/${id}`);
  }

  async function onSave() {
    if (!id) return;
    setError("");
    if (!title.trim() || !text.trim()) {
      setError("Dê um título e conte a memória.");
      return;
    }
    if (!coords) {
      setError("Escolha um local: busque, use sua localização ou toque no mapa.");
      return;
    }
    // Mesma validação da criação: rejeita datas impossíveis (ex.: 2023-02-31).
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
    setSaving(true);
    try {
      await api.updateMemory(id, {
        title: title.trim(),
        text: text.trim(),
        latitude: coords.latitude,
        longitude: coords.longitude,
        occurred_at: `${date}T12:00:00Z`,
      });
      // Se o usuário escolheu uma nova foto, sobe (precisa do Storage configurado).
      if (image) await api.uploadMemoryImage(id, image);
      // Volta ao detalhe, que recarrega no mount e mostra os dados atualizados.
      router.replace(`/memory/${id}`);
    } catch (e) {
      if (api.isUnauthorized(e)) {
        router.replace("/");
        return;
      }
      if (api.isNotFound(e)) {
        setError("Memória não encontrada.");
        setSaving(false);
        return;
      }
      setError(e instanceof api.ApiError ? e.message : "Erro ao salvar.");
      setSaving(false);
    }
  }

  return (
    <ScrollView style={ui.screen} contentContainerStyle={{ paddingBottom: 48 }}>
      <View style={{ paddingTop: 50, paddingHorizontal: 28 }}>
        <Pressable onPress={goBack} accessibilityRole="button" accessibilityLabel="Voltar">
          <Text style={ui.back}>← Voltar</Text>
        </Pressable>

        <Text style={[ui.title, { marginTop: 12 }]}>Editar memória</Text>
        <Text style={ui.subtitle}>Ajuste o que precisar.</Text>

        {loadError ? (
          <Text style={{ color: colors.danger, fontSize: 15, marginTop: 32, textAlign: "center" }}>
            {loadError}
          </Text>
        ) : !loaded ? (
          <ActivityIndicator color={colors.terra} style={{ marginTop: 48 }} />
        ) : (
          <>
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

            <Text style={ui.label}>FOTO (OPCIONAL)</Text>
            <ImagePickerField value={image} existingUrl={existingImageUrl} onChange={setImage} />

            {error ? (
              <Text style={{ color: colors.danger, fontSize: 13, marginTop: 12, textAlign: "center" }}>
                {error}
              </Text>
            ) : null}

            <Pressable
              style={({ pressed }) => [ui.button, pressed && ui.buttonPressed]}
              onPress={onSave}
              disabled={saving}
            >
              <Text style={ui.buttonText}>{saving ? "Salvando..." : "Salvar alterações"}</Text>
            </Pressable>
          </>
        )}
      </View>
    </ScrollView>
  );
}
