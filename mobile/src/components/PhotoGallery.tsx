import { useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { Image } from "expo-image";
import * as ImagePicker from "expo-image-picker";

import type { MemoryImage, PickedImage } from "../lib/api";
import { colors } from "../theme/colors";

type Props = {
  saved?: MemoryImage[]; // fotos já salvas (edição) — removidas via API pelo pai
  picks?: PickedImage[]; // novas escolhas ainda não enviadas
  max?: number; // teto de fotos (default 5)
  onAddPicks?: (imgs: PickedImage[]) => void;
  onRemovePick?: (index: number) => void;
  onRemoveSaved?: (id: string) => void;
};

// Galeria de fotos da memória (usada nas telas criar/editar): mostra as fotos
// salvas + as recém-escolhidas em miniaturas com "×", e um botão "+" que abre a
// seleção múltipla, respeitando o teto. A seleção sobe ao salvar (criar) ou o
// pai chama a API (editar).
export default function PhotoGallery({
  saved = [],
  picks = [],
  max = 5,
  onAddPicks,
  onRemovePick,
  onRemoveSaved,
}: Props) {
  const [error, setError] = useState("");
  const total = saved.length + picks.length;
  const remaining = Math.max(0, max - total);

  async function pick() {
    setError("");
    if (remaining <= 0) return;
    const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!perm.granted) {
      setError("Permissão de acesso às fotos negada.");
      return;
    }
    const res = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ["images"],
      allowsMultipleSelection: true,
      selectionLimit: remaining,
      quality: 0.8,
    });
    if (!res.canceled && res.assets?.length) {
      const imgs = res.assets
        .slice(0, remaining)
        .map((a) => ({ uri: a.uri, mimeType: a.mimeType, fileName: a.fileName }));
      onAddPicks?.(imgs);
    }
  }

  return (
    <View>
      <View style={s.grid}>
        {saved.map((img) => (
          <View key={img.id} style={s.thumbWrap}>
            <Image source={{ uri: img.url }} style={s.thumb} contentFit="cover" />
            <Pressable style={s.remove} onPress={() => onRemoveSaved?.(img.id)} hitSlop={6} accessibilityRole="button" accessibilityLabel="Remover foto">
              <Text style={s.removeText}>×</Text>
            </Pressable>
          </View>
        ))}
        {picks.map((img, i) => (
          <View key={`pick-${i}`} style={s.thumbWrap}>
            <Image source={{ uri: img.uri }} style={s.thumb} contentFit="cover" />
            <Pressable style={s.remove} onPress={() => onRemovePick?.(i)} hitSlop={6} accessibilityRole="button" accessibilityLabel="Remover foto escolhida">
              <Text style={s.removeText}>×</Text>
            </Pressable>
          </View>
        ))}
        {remaining > 0 ? (
          <Pressable style={s.addTile} onPress={pick} accessibilityRole="button" accessibilityLabel="Adicionar foto">
            <Text style={s.addPlus}>+</Text>
            <Text style={s.addHint}>{total === 0 ? "Foto" : `${remaining}`}</Text>
          </Pressable>
        ) : null}
      </View>
      {error ? <Text style={s.error}>{error}</Text> : null}
    </View>
  );
}

const THUMB = 84;

const s = StyleSheet.create({
  grid: { flexDirection: "row", flexWrap: "wrap", gap: 10, marginTop: 6 },
  thumbWrap: { width: THUMB, height: THUMB },
  thumb: { width: THUMB, height: THUMB, borderRadius: 12, backgroundColor: colors.sky, borderWidth: 1, borderColor: colors.line },
  remove: {
    position: "absolute",
    top: -6,
    right: -6,
    width: 22,
    height: 22,
    borderRadius: 11,
    backgroundColor: colors.danger,
    alignItems: "center",
    justifyContent: "center",
  },
  removeText: { color: "#FBF6E8", fontSize: 15, fontWeight: "700", marginTop: -2 },
  addTile: {
    width: THUMB,
    height: THUMB,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "rgba(35,39,47,0.18)",
    borderStyle: "dashed",
    backgroundColor: colors.card,
    alignItems: "center",
    justifyContent: "center",
  },
  addPlus: { color: colors.teal, fontSize: 24, fontWeight: "700", marginBottom: -2 },
  addHint: { color: colors.teal, fontSize: 11, fontWeight: "600" },
  error: { color: colors.danger, fontSize: 12, marginTop: 8 },
});
