import { useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { Image } from "expo-image";
import * as ImagePicker from "expo-image-picker";

import type { PickedImage } from "../lib/api";
import { colors } from "../theme/colors";

type Props = {
  value: PickedImage | null; // imagem recém-escolhida (ainda não enviada)
  existingUrl?: string | null; // imagem já salva (URL assinada) na edição
  onChange: (img: PickedImage | null) => void;
  onRemoveExisting?: () => void; // remover a foto JÁ salva (só na edição)
};

// Campo de foto opcional: escolhe da galeria (expo-image-picker, funciona em web
// e nativo) e mostra o preview. A escolha sobe junto ao salvar a memória.
export default function ImagePickerField({ value, existingUrl, onChange, onRemoveExisting }: Props) {
  const [error, setError] = useState("");
  const previewUri = value?.uri ?? existingUrl ?? null;

  async function pick() {
    setError("");
    const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!perm.granted) {
      setError("Permissão de acesso às fotos negada.");
      return;
    }
    const res = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ["images"],
      quality: 0.8,
    });
    if (!res.canceled && res.assets && res.assets[0]) {
      const a = res.assets[0];
      onChange({ uri: a.uri, mimeType: a.mimeType, fileName: a.fileName });
    }
  }

  return (
    <View>
      {previewUri ? (
        <View style={s.previewWrap}>
          <Image source={{ uri: previewUri }} style={s.preview} contentFit="cover" />
          <View style={s.previewActions}>
            <Pressable onPress={pick} hitSlop={6} accessibilityRole="button" accessibilityLabel="Trocar foto">
              <Text style={s.action}>Trocar</Text>
            </Pressable>
            {value ? (
              <Pressable onPress={() => onChange(null)} hitSlop={6} accessibilityRole="button" accessibilityLabel="Remover foto escolhida">
                <Text style={[s.action, { color: colors.danger }]}>Remover</Text>
              </Pressable>
            ) : existingUrl && onRemoveExisting ? (
              <Pressable onPress={onRemoveExisting} hitSlop={6} accessibilityRole="button" accessibilityLabel="Remover foto salva">
                <Text style={[s.action, { color: colors.danger }]}>Remover</Text>
              </Pressable>
            ) : null}
          </View>
        </View>
      ) : (
        <Pressable
          style={({ pressed }) => [s.addBtn, pressed && { opacity: 0.9 }]}
          onPress={pick}
          accessibilityRole="button"
          accessibilityLabel="Adicionar foto"
        >
          <Text style={s.addText}>+ Adicionar foto (opcional)</Text>
        </Pressable>
      )}
      {error ? <Text style={s.error}>{error}</Text> : null}
    </View>
  );
}

const s = StyleSheet.create({
  addBtn: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: "rgba(35,39,47,0.18)",
    borderStyle: "dashed",
    borderRadius: 12,
    paddingVertical: 16,
    alignItems: "center",
  },
  addText: { color: colors.teal, fontSize: 14, fontWeight: "600" },
  previewWrap: { gap: 8 },
  preview: { width: "100%", height: 200, borderRadius: 12, backgroundColor: colors.sky, borderWidth: 1, borderColor: colors.line },
  previewActions: { flexDirection: "row", gap: 18, justifyContent: "center" },
  action: { color: colors.teal, fontSize: 14, fontWeight: "600" },
  error: { color: colors.danger, fontSize: 12, marginTop: 8 },
});
