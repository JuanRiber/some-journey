import { useEffect, useState } from "react";
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { Image } from "expo-image";
import { router, useLocalSearchParams } from "expo-router";

import * as api from "../../lib/api";
import { colors, mono, serif } from "../../theme/colors";

function formatFull(iso: string): string {
  try {
    // Parte UTC: occurred_at é canonicamente o dia em UTC (ver Timeline).
    return new Date(iso).toLocaleDateString("pt-BR", {
      day: "2-digit",
      month: "long",
      year: "numeric",
      timeZone: "UTC",
    });
  } catch {
    return iso;
  }
}

// Detalhe de uma memória. Segurança: id de outro usuário / inexistente / apagado
// volta 404; UUID malformado volta 422 — ambos viram "Memória não encontrada."
// (anti-enumeração: qualquer id inacessível parece idêntico, sem string crua do
// backend e sem revelar existência).
export default function MemoryDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [memory, setMemory] = useState<api.Memory | null>(null);
  const [error, setError] = useState("");
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    let active = true;
    if (!id) {
      setError("Memória não encontrada.");
      return;
    }
    api
      .getMemory(id)
      .then((m) => {
        if (active) setMemory(m);
      })
      .catch((e) => {
        if (!active) return;
        if (api.isUnauthorized(e)) {
          router.replace("/");
          return;
        }
        if (api.isNotFound(e)) {
          setError("Memória não encontrada.");
          return;
        }
        setError(e instanceof api.ApiError ? e.message : "Erro ao carregar.");
      });
    return () => {
      active = false;
    };
  }, [id]);

  function goBack() {
    if (router.canGoBack()) router.back();
    else router.replace("/atlas");
  }

  async function onDelete() {
    if (!id) return;
    setDeleting(true);
    try {
      await api.deleteMemory(id);
      router.replace("/timeline");
    } catch (e) {
      // Mesma regra das demais telas: 401 numa ação destrutiva → volta ao login.
      if (api.isUnauthorized(e)) {
        router.replace("/");
        return;
      }
      setError(e instanceof api.ApiError ? e.message : "Erro ao apagar.");
      setDeleting(false);
    }
  }

  return (
    <View style={s.screen}>
      <View style={s.topBar}>
        <Pressable style={s.back} onPress={goBack} hitSlop={10} accessibilityRole="button" accessibilityLabel="Voltar">
          <Text style={s.backArrow}>←</Text>
        </Pressable>
      </View>

      <ScrollView style={s.body} contentContainerStyle={{ paddingBottom: 48 }}>
        {error ? (
          <View style={s.center}>
            <Text style={s.error}>{error}</Text>
            <Pressable onPress={goBack} hitSlop={6} accessibilityRole="button" accessibilityLabel="Voltar">
              <Text style={s.open}>← Voltar</Text>
            </Pressable>
          </View>
        ) : !memory ? (
          <ActivityIndicator color={colors.coral} style={{ marginTop: 48 }} />
        ) : (
          <>
            <Text style={s.title}>{memory.title}</Text>
            <View style={s.metaRow}>
              <View style={s.pin} />
              <Text style={s.meta}>
                {memory.latitude.toFixed(3)}, {memory.longitude.toFixed(3)} • {formatFull(memory.occurred_at)}
              </Text>
            </View>

            {memory.images.map((img) => (
              <Image key={img.id} source={{ uri: img.url }} style={s.image} contentFit="cover" transition={200} />
            ))}

            <Text style={s.text}>{memory.text}</Text>

            {/* Os chips de Humor e Trilha dos mockups dependem de campos fora do
                schema atual (e "trilha" cairia em referência de banda) — entram
                num bloco futuro, quando o modelo de dados crescer. */}

            <View style={s.divider} />
            <Text style={s.quote}>“A vida deixa rastros.”</Text>

            {confirmDelete ? (
              <View style={s.confirmRow}>
                <Text style={s.confirmText}>Apagar esta memória?</Text>
                <View style={s.confirmActions}>
                  <Pressable
                    style={({ pressed }) => [s.confirmYesBtn, pressed && { opacity: 0.9 }]}
                    onPress={onDelete}
                    disabled={deleting}
                    accessibilityRole="button"
                    accessibilityLabel="Confirmar exclusão"
                  >
                    <Text style={s.confirmYesText}>{deleting ? "Apagando..." : "Sim, apagar"}</Text>
                  </Pressable>
                  <Pressable onPress={() => setConfirmDelete(false)} disabled={deleting} hitSlop={6} accessibilityRole="button" accessibilityLabel="Cancelar">
                    <Text style={s.confirmNo}>Cancelar</Text>
                  </Pressable>
                </View>
              </View>
            ) : (
              <>
                <Pressable
                  style={({ pressed }) => [s.editBtn, pressed && { opacity: 0.9 }]}
                  onPress={() => router.push(`/memory-edit/${id}`)}
                  accessibilityRole="button"
                  accessibilityLabel="Editar memória"
                >
                  <Text style={s.editText}>Editar memória</Text>
                </Pressable>
                <Pressable style={s.deleteBtn} onPress={() => setConfirmDelete(true)} accessibilityRole="button" accessibilityLabel="Apagar memória">
                  <Text style={s.deleteText}>Apagar memória</Text>
                </Pressable>
              </>
            )}
          </>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.paper },
  topBar: {
    paddingTop: 52,
    paddingBottom: 6,
    paddingHorizontal: 18,
    backgroundColor: colors.paper,
  },
  back: {
    width: 38,
    height: 38,
    borderRadius: 19,
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.line,
    alignItems: "center",
    justifyContent: "center",
  },
  backArrow: { fontSize: 20, color: colors.ink, marginTop: -2 },
  body: {
    flex: 1,
    backgroundColor: colors.paper,
    paddingHorizontal: 28,
    paddingTop: 8,
  },
  center: { marginTop: 40, alignItems: "center", gap: 12 },
  error: { color: colors.danger, textAlign: "center", fontSize: 15 },
  title: { fontFamily: serif, fontSize: 28, color: colors.ink, lineHeight: 34 },
  metaRow: { flexDirection: "row", alignItems: "center", gap: 7, marginTop: 8 },
  pin: { width: 9, height: 9, borderRadius: 5, backgroundColor: colors.coral },
  meta: { fontFamily: mono, color: colors.bloom, fontSize: 11, letterSpacing: 1, textTransform: "uppercase" },
  // Foto emoldurada como arte de capa: moldura carvão, canto quase reto.
  image: { width: "100%", maxWidth: 560, alignSelf: "center", aspectRatio: 4 / 3, borderRadius: 3, marginTop: 16, backgroundColor: colors.sand, borderWidth: 3, borderColor: colors.frame },
  text: { color: colors.ink, fontSize: 16, lineHeight: 25, marginTop: 18 },
  divider: { height: 1, backgroundColor: colors.line, marginTop: 28 },
  quote: { fontFamily: serif, fontStyle: "italic", fontSize: 16, color: colors.bloom, textAlign: "center", marginTop: 18 },
  editBtn: {
    marginTop: 30,
    backgroundColor: colors.gold,
    borderRadius: 8,
    paddingVertical: 13,
    alignItems: "center",
  },
  editText: { fontFamily: mono, color: colors.pageBg, fontSize: 13, fontWeight: "700", letterSpacing: 1.4, textTransform: "uppercase" },
  deleteBtn: { marginTop: 14, alignItems: "center", paddingVertical: 12 },
  deleteText: { color: colors.danger, fontSize: 14, fontWeight: "500" },
  confirmRow: { marginTop: 32, alignItems: "center", gap: 14 },
  confirmText: { color: colors.ink, fontSize: 15, fontWeight: "600" },
  confirmActions: { flexDirection: "row", alignItems: "center", gap: 18 },
  confirmYesBtn: { backgroundColor: colors.danger, borderRadius: 8, paddingVertical: 11, paddingHorizontal: 22 },
  confirmYesText: { fontFamily: mono, color: colors.pageBg, fontSize: 12, fontWeight: "700", letterSpacing: 1.2, textTransform: "uppercase" },
  confirmNo: { color: colors.inkSoft, fontSize: 14 },
  open: { color: colors.coral, fontWeight: "600", fontSize: 14 },
});
