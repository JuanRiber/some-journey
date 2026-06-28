import { useCallback, useState } from "react";
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { router, useFocusEffect, useLocalSearchParams } from "expo-router";

import * as api from "../../lib/api";
import { STATUS_COLOR, STATUS_LABEL } from "../../lib/journeyStatus";
import { colors, serif } from "../../theme/colors";

function formatDate(iso: string): string {
  try {
    return new Date(iso).toLocaleDateString("pt-BR", { day: "2-digit", month: "short", year: "numeric", timeZone: "UTC" });
  } catch {
    return iso;
  }
}

// Detalhe e gestão de uma jornada: ciclo de vida (iniciar/pausar/retomar/
// finalizar), pontos ordenados (reordenar/remover sem apagar a memória),
// vincular um ponto solto e excluir a jornada.
export default function JourneyDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [journey, setJourney] = useState<api.JourneyDetail | null>(null);
  const [error, setError] = useState("");
  const [action, setAction] = useState(""); // texto da ação em curso (desabilita botões)
  const [confirmDelete, setConfirmDelete] = useState(false);

  const [showAdd, setShowAdd] = useState(false);
  const [loose, setLoose] = useState<api.MapPoint[] | null>(null);
  const [addError, setAddError] = useState("");

  const load = useCallback(() => {
    if (!id) {
      setError("Jornada não encontrada.");
      return;
    }
    api
      .getJourney(id)
      .then(setJourney)
      .catch((e) => {
        if (api.isUnauthorized(e)) {
          router.replace("/");
          return;
        }
        if (api.isNotFound(e)) {
          setError("Jornada não encontrada.");
          return;
        }
        setError(e instanceof api.ApiError ? e.message : "Erro ao carregar.");
      });
  }, [id]);

  useFocusEffect(
    useCallback(() => {
      setError("");
      load();
    }, [load]),
  );

  // Wrapper das ações: roda fn, trata 401/erro e recarrega/atualiza a jornada.
  async function run(label: string, fn: () => Promise<unknown>, onResult?: (r: any) => void) {
    if (!id) return;
    setError("");
    setAction(label);
    try {
      const r = await fn();
      if (onResult) onResult(r);
      else load();
    } catch (e) {
      if (api.isUnauthorized(e)) {
        router.replace("/");
        return;
      }
      setError(e instanceof api.ApiError ? e.message : "Erro na operação.");
    } finally {
      setAction("");
    }
  }

  function goBack() {
    if (router.canGoBack()) router.back();
    else router.replace("/journeys");
  }

  function reorder(index: number, dir: -1 | 1) {
    if (!journey) return;
    const ids = journey.points.map((p) => p.memory_id);
    const j = index + dir;
    if (j < 0 || j >= ids.length) return;
    [ids[index], ids[j]] = [ids[j], ids[index]];
    run("reorder", () => api.reorderJourneyPoints(journey.id, ids), setJourney);
  }

  async function openAdd() {
    setShowAdd(true);
    setAddError("");
    setLoose(null);
    try {
      const map = await api.getMap();
      setLoose(map.loose_points);
    } catch (e) {
      if (api.isUnauthorized(e)) {
        router.replace("/");
        return;
      }
      setAddError(e instanceof api.ApiError ? e.message : "Erro ao carregar pontos soltos.");
      setLoose([]);
    }
  }

  function addPoint(memoryId: string) {
    if (!journey) return;
    run(
      `add:${memoryId}`,
      () => api.addJourneyPoint(journey.id, memoryId),
      (detail) => {
        setJourney(detail);
        setLoose((prev) => (prev ? prev.filter((m) => m.memory_id !== memoryId) : prev));
      },
    );
  }

  const busy = action !== "";

  if (error && !journey) {
    return (
      <View style={s.screen}>
        <View style={{ paddingTop: 50, paddingHorizontal: 24 }}>
          <Pressable onPress={goBack} accessibilityRole="button" accessibilityLabel="Voltar">
            <Text style={s.back}>← Voltar</Text>
          </Pressable>
          <Text style={s.error}>{error}</Text>
        </View>
      </View>
    );
  }

  if (!journey) {
    return (
      <View style={s.screen}>
        <ActivityIndicator color={colors.terra} style={{ marginTop: 80 }} />
      </View>
    );
  }

  const st = journey.status;

  return (
    <ScrollView style={s.screen} contentContainerStyle={{ paddingBottom: 48 }}>
      <View style={{ paddingTop: 50, paddingHorizontal: 24 }}>
        <Pressable onPress={goBack} accessibilityRole="button" accessibilityLabel="Voltar">
          <Text style={s.back}>← Voltar</Text>
        </Pressable>

        <View style={s.titleRow}>
          <Text style={s.title}>{journey.title}</Text>
          <View style={[s.badge, { backgroundColor: STATUS_COLOR[st] }]}>
            <Text style={s.badgeText}>{STATUS_LABEL[st]}</Text>
          </View>
        </View>
        {journey.description ? <Text style={s.desc}>{journey.description}</Text> : null}
        <Text style={s.meta}>
          {journey.points_count} {journey.points_count === 1 ? "ponto" : "pontos"}
          {journey.started_at ? ` • início ${formatDate(journey.started_at)}` : ""}
          {journey.ended_at ? ` • fim ${formatDate(journey.ended_at)}` : ""}
        </Text>

        {/* Ações de ciclo de vida conforme o status */}
        <View style={s.actions}>
          {st === "draft" && (
            <Pressable style={[s.primary, busy && s.disabled]} disabled={busy} onPress={() => run("start", () => api.startJourney(journey.id))}>
              <Text style={s.primaryText}>Iniciar</Text>
            </Pressable>
          )}
          {st === "active" && (
            <>
              <Pressable style={[s.secondary, busy && s.disabled]} disabled={busy} onPress={() => run("pause", () => api.pauseJourney(journey.id))}>
                <Text style={s.secondaryText}>Pausar</Text>
              </Pressable>
              <Pressable style={[s.primary, busy && s.disabled]} disabled={busy} onPress={() => run("finish", () => api.finishJourney(journey.id))}>
                <Text style={s.primaryText}>Finalizar</Text>
              </Pressable>
            </>
          )}
          {st === "paused" && (
            <>
              <Pressable style={[s.primary, busy && s.disabled]} disabled={busy} onPress={() => run("resume", () => api.resumeJourney(journey.id))}>
                <Text style={s.primaryText}>Retomar</Text>
              </Pressable>
              <Pressable style={[s.secondary, busy && s.disabled]} disabled={busy} onPress={() => run("finish", () => api.finishJourney(journey.id))}>
                <Text style={s.secondaryText}>Finalizar</Text>
              </Pressable>
            </>
          )}
          {st === "finished" && <Text style={s.finishedNote}>Jornada concluída.</Text>}
        </View>

        {error ? <Text style={s.inlineError}>{error}</Text> : null}

        {/* Pontos ordenados */}
        <Text style={s.sectionLabel}>PONTOS (NA ORDEM DO RASTRO)</Text>
        {journey.points.length === 0 ? (
          <Text style={s.emptyPoints}>Nenhum ponto ainda. Adicione memórias para formar o rastro.</Text>
        ) : (
          <View style={{ gap: 10 }}>
            {journey.points.map((p, i) => (
              <View key={p.memory_id} style={s.point}>
                <Text style={s.pos}>{p.position}</Text>
                <Pressable
                  style={{ flex: 1 }}
                  onPress={() => router.push(`/memory/${p.memory_id}`)}
                  accessibilityRole="button"
                  accessibilityLabel={`Ver memória: ${p.title}`}
                >
                  <Text style={s.pointTitle} numberOfLines={1}>{p.title}</Text>
                  <Text style={s.pointMeta}>
                    {p.latitude.toFixed(3)}, {p.longitude.toFixed(3)} • {formatDate(p.occurred_at)}
                  </Text>
                </Pressable>
                <View style={s.pointActions}>
                  <Pressable disabled={busy || i === 0} onPress={() => reorder(i, -1)} hitSlop={6} accessibilityLabel="Mover para cima">
                    <Text style={[s.move, (busy || i === 0) && s.moveOff]}>↑</Text>
                  </Pressable>
                  <Pressable disabled={busy || i === journey.points.length - 1} onPress={() => reorder(i, 1)} hitSlop={6} accessibilityLabel="Mover para baixo">
                    <Text style={[s.move, (busy || i === journey.points.length - 1) && s.moveOff]}>↓</Text>
                  </Pressable>
                  <Pressable disabled={busy} onPress={() => run(`unlink:${p.memory_id}`, () => api.unlinkJourneyPoint(journey.id, p.memory_id))} hitSlop={6} accessibilityLabel="Remover da jornada">
                    <Text style={s.remove}>✕</Text>
                  </Pressable>
                </View>
              </View>
            ))}
          </View>
        )}

        {/* Adicionar pontos (memória nova nesta jornada ou um ponto solto existente) */}
        {st !== "finished" && (
          <View style={{ marginTop: 22 }}>
            <Pressable
              style={({ pressed }) => [s.addNew, pressed && { opacity: 0.9 }]}
              onPress={() => router.push(`/memory-new?journeyId=${journey.id}`)}
              accessibilityRole="button"
              accessibilityLabel="Adicionar nova memória à jornada"
            >
              <Text style={s.addNewText}>+ Nova memória nesta jornada</Text>
            </Pressable>

            {!showAdd ? (
              <Pressable style={s.linkExisting} onPress={openAdd} accessibilityRole="button" accessibilityLabel="Vincular ponto existente">
                <Text style={s.linkExistingText}>Vincular um ponto solto existente</Text>
              </Pressable>
            ) : (
              <View style={s.addBox}>
                <Text style={s.sectionLabel}>PONTOS SOLTOS</Text>
                {addError ? <Text style={s.inlineError}>{addError}</Text> : null}
                {loose === null ? (
                  <ActivityIndicator color={colors.terra} style={{ marginVertical: 16 }} />
                ) : loose.length === 0 ? (
                  <Text style={s.emptyPoints}>Nenhum ponto solto para vincular.</Text>
                ) : (
                  <View style={{ gap: 8 }}>
                    {loose.map((m) => (
                      <View key={m.memory_id} style={s.looseRow}>
                        <View style={{ flex: 1 }}>
                          <Text style={s.pointTitle} numberOfLines={1}>{m.title}</Text>
                          <Text style={s.pointMeta}>
                            {m.latitude.toFixed(3)}, {m.longitude.toFixed(3)} • {formatDate(m.occurred_at)}
                          </Text>
                        </View>
                        <Pressable disabled={busy} onPress={() => addPoint(m.memory_id)} hitSlop={6} accessibilityLabel={`Adicionar ${m.title}`}>
                          <Text style={s.addPlus}>+ Adicionar</Text>
                        </Pressable>
                      </View>
                    ))}
                  </View>
                )}
                <Pressable onPress={() => setShowAdd(false)} hitSlop={6} accessibilityLabel="Fechar">
                  <Text style={s.closeAdd}>Fechar</Text>
                </Pressable>
              </View>
            )}
          </View>
        )}

        {/* Excluir jornada (soft delete; não apaga as memórias) */}
        {confirmDelete ? (
          <View style={s.confirmRow}>
            <Text style={s.confirmText}>Excluir esta jornada? As memórias não são apagadas.</Text>
            <View style={s.confirmActions}>
              <Pressable style={s.confirmYes} disabled={busy} onPress={() => run("delete", () => api.deleteJourney(journey.id), () => router.replace("/journeys"))} accessibilityLabel="Confirmar exclusão">
                <Text style={s.confirmYesText}>{action === "delete" ? "Excluindo..." : "Sim, excluir"}</Text>
              </Pressable>
              <Pressable onPress={() => setConfirmDelete(false)} disabled={busy} hitSlop={6} accessibilityLabel="Cancelar">
                <Text style={s.confirmNo}>Cancelar</Text>
              </Pressable>
            </View>
          </View>
        ) : (
          <Pressable style={s.deleteBtn} onPress={() => setConfirmDelete(true)} accessibilityRole="button" accessibilityLabel="Excluir jornada">
            <Text style={s.deleteText}>Excluir jornada</Text>
          </Pressable>
        )}
      </View>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.paper },
  back: { color: colors.ink, fontSize: 14, fontWeight: "500" },
  error: { color: colors.danger, textAlign: "center", marginTop: 40, fontSize: 15 },
  inlineError: { color: colors.danger, fontSize: 13, marginTop: 12 },
  titleRow: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 10, marginTop: 14 },
  title: { fontFamily: serif, fontSize: 27, color: colors.ink, flex: 1 },
  badge: { borderRadius: 20, paddingVertical: 3, paddingHorizontal: 10 },
  badgeText: { color: "#FBF6E8", fontSize: 11, fontWeight: "700", letterSpacing: 0.3 },
  desc: { color: colors.inkSoft, fontSize: 14, lineHeight: 21, marginTop: 8 },
  meta: { color: colors.terraDeep, fontSize: 12, fontWeight: "600", marginTop: 8 },
  actions: { flexDirection: "row", gap: 10, marginTop: 16 },
  primary: { backgroundColor: colors.terra, borderRadius: 11, paddingVertical: 11, paddingHorizontal: 20, alignItems: "center" },
  primaryText: { color: "#FBF6E8", fontSize: 14, fontWeight: "700" },
  secondary: { backgroundColor: colors.card, borderWidth: 1, borderColor: colors.terra, borderRadius: 11, paddingVertical: 11, paddingHorizontal: 20, alignItems: "center" },
  secondaryText: { color: colors.terraDeep, fontSize: 14, fontWeight: "700" },
  disabled: { opacity: 0.5 },
  finishedNote: { color: colors.sage, fontSize: 14, fontWeight: "600" },
  sectionLabel: { fontSize: 11, letterSpacing: 1.2, color: colors.inkSoft, marginTop: 26, marginBottom: 10 },
  emptyPoints: { color: colors.inkSoft, fontSize: 14, lineHeight: 20 },
  point: { flexDirection: "row", alignItems: "center", gap: 10, backgroundColor: colors.card, borderWidth: 1, borderColor: colors.line, borderRadius: 12, padding: 12 },
  pos: { fontFamily: serif, fontSize: 16, color: colors.terra, width: 20, textAlign: "center" },
  pointTitle: { fontFamily: serif, fontSize: 16, color: colors.ink },
  pointMeta: { color: colors.inkSoft, fontSize: 12, marginTop: 2 },
  pointActions: { flexDirection: "row", alignItems: "center", gap: 12 },
  move: { fontSize: 18, color: colors.terraDeep, fontWeight: "700" },
  moveOff: { color: colors.line },
  remove: { fontSize: 15, color: colors.danger, fontWeight: "700" },
  addNew: { backgroundColor: colors.terra, borderRadius: 11, paddingVertical: 12, alignItems: "center" },
  addNewText: { color: "#FBF6E8", fontSize: 14, fontWeight: "600" },
  linkExisting: { marginTop: 12, alignItems: "center", paddingVertical: 8 },
  linkExistingText: { color: colors.teal, fontSize: 14, fontWeight: "600" },
  addBox: { marginTop: 8, backgroundColor: "rgba(61,138,152,0.08)", borderRadius: 12, padding: 12 },
  looseRow: { flexDirection: "row", alignItems: "center", gap: 10, backgroundColor: colors.card, borderRadius: 10, padding: 10 },
  addPlus: { color: colors.terraDeep, fontSize: 13, fontWeight: "700" },
  closeAdd: { color: colors.inkSoft, fontSize: 13, textAlign: "center", marginTop: 12 },
  confirmRow: { marginTop: 34, alignItems: "center", gap: 12 },
  confirmText: { color: colors.ink, fontSize: 14, fontWeight: "600", textAlign: "center", lineHeight: 20 },
  confirmActions: { flexDirection: "row", alignItems: "center", gap: 18 },
  confirmYes: { backgroundColor: colors.danger, borderRadius: 10, paddingVertical: 11, paddingHorizontal: 22 },
  confirmYesText: { color: "#FBF6E8", fontSize: 14, fontWeight: "700" },
  confirmNo: { color: colors.inkSoft, fontSize: 14 },
  deleteBtn: { marginTop: 32, alignItems: "center", paddingVertical: 12 },
  deleteText: { color: colors.danger, fontSize: 14, fontWeight: "500" },
});
