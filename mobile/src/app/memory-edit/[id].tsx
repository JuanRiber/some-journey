import { useEffect, useState } from "react";
import { ActivityIndicator, Pressable, ScrollView, Text, TextInput, View } from "react-native";
import { router, useLocalSearchParams } from "expo-router";

import DateField from "../../components/DateField";
import LocationPicker from "../../components/LocationPicker";
import PhotoGallery from "../../components/PhotoGallery";
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
  const [savedImages, setSavedImages] = useState<api.MemoryImage[]>([]);
  const [picks, setPicks] = useState<api.PickedImage[]>([]);
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
        setSavedImages(m.images);
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

  async function removeSavedPhoto(imageId: string) {
    if (!id) return;
    try {
      await api.deleteMemoryImage(id, imageId);
      setSavedImages((cur) => cur.filter((img) => img.id !== imageId));
    } catch (e) {
      if (api.isUnauthorized(e)) {
        router.replace("/");
        return;
      }
      setError(e instanceof api.ApiError ? e.message : "Erro ao remover foto.");
    }
  }

  async function onSave() {
    if (!id) return;
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
    setSaving(true);
    try {
      await api.updateMemory(id, {
        title: title.trim(),
        text: text.trim(),
        latitude: coords.latitude,
        longitude: coords.longitude,
        occurred_at: `${date.trim()}T12:00:00Z`,
      });
      // Novas fotos sobem (remoções de fotos salvas já foram via API na hora).
      for (const p of picks) await api.addMemoryImage(id, p);
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

            <Text style={ui.label}>FOTOS (OPCIONAL, ATÉ 5)</Text>
            <PhotoGallery
              saved={savedImages}
              picks={picks}
              onAddPicks={(imgs) => setPicks((cur) => [...cur, ...imgs])}
              onRemovePick={(i) => setPicks((cur) => cur.filter((_, idx) => idx !== i))}
              onRemoveSaved={removeSavedPhoto}
            />

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
