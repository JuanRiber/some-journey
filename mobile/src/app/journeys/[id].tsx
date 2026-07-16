import { useCallback, useState } from "react";
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";
import { router, useFocusEffect, useLocalSearchParams } from "expo-router";

import AtlasMap from "../../components/AtlasMap";
import * as api from "../../lib/api";
import { STATUS_COLOR, STATUS_LABEL } from "../../lib/journeyStatus";
import { useTrackRecorder } from "../../lib/useTrackRecorder";
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

  const [editing, setEditing] = useState(false);
  const [editTitle, setEditTitle] = useState("");
  const [editDesc, setEditDesc] = useState("");
  const [editMood, setEditMood] = useState("");
  const [editPrivate, setEditPrivate] = useState(true);

  const [showAdd, setShowAdd] = useState(false);
  const [loose, setLoose] = useState<api.MapPoint[] | null>(null);
  const [addError, setAddError] = useState("");

  // Mapa da jornada (percurso real + memórias + rastro simbólico) e o modo de
  // visualização. mode=null => automático (real quando há percurso; senão simbólico).
  const [journeyMap, setJourneyMap] = useState<api.JourneyMapResponse | null>(null);
  const [mode, setMode] = useState<"real" | "symbolic" | null>(null);

  const loadMap = useCallback(() => {
    if (!id) return;
    api.getJourneyMap(id).then(setJourneyMap).catch(() => {
      // mapa é complementar; falha silenciosa não bloqueia a tela
    });
  }, [id]);

  // Gravador de percurso em primeiro plano (sem tracking em segundo plano).
  const recorder = useTrackRecorder(id ?? "", { onFlush: loadMap });

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
      loadMap();
    }, [load, loadMap]),
  );

  // Wrapper das ações: roda fn, trata 401/erro e recarrega/atualiza a jornada.
  async function run(label: string, fn: () => Promise<unknown>, onResult?: (r: any) => void) {
    if (!id) return;
    setError("");
    setAction(label);
    try {
      const r = await fn();
      if (onResult) onResult(r);
      else {
        load();
        loadMap();
      }
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

  function openEdit() {
    if (!journey) return;
    setEditTitle(journey.title);
    setEditDesc(journey.description ?? "");
    setEditMood(journey.mood ?? "");
    setEditPrivate(journey.is_private);
    setError("");
    setEditing(true);
  }

  function saveEdit() {
    if (!journey) return;
    if (!editTitle.trim()) {
      setError("O título não pode ficar vazio.");
      return;
    }
    run(
      "edit",
      () =>
        api.updateJourney(journey.id, {
          title: editTitle.trim(),
          description: editDesc.trim(),
          mood: editMood.trim() || null,
          is_private: editPrivate,
        }),
      () => {
        setEditing(false);
        load();
      },
    );
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
  const hasTrack = !!journeyMap && journeyMap.tracks.features.length > 0;
  const hasMemories = journey.points.length > 0;
  // Modo mostrado: automático quando o usuário não escolheu (real se há percurso).
  const mapMode: "real" | "symbolic" = mode ?? (hasTrack ? "real" : "symbolic");
  // MapResponse "de uma jornada só" para reaproveitar o AtlasMap no detalhe.
  const mapData: api.MapResponse | null = journeyMap
    ? {
        loose_points: [],
        journeys: [
          {
            id: journey.id,
            title: journey.title,
            status: journey.status,
            points: journeyMap.memories.features.map((f) => ({
              memory_id: f.properties.memory_id,
              title: f.properties.title,
              latitude: f.geometry.coordinates[1],
              longitude: f.geometry.coordinates[0],
              occurred_at: f.properties.memory_date,
              position: null,
            })),
            // Rastro simbólico no modo "Conectar memórias" — e também como
            // fallback no modo "Percurso real" quando ainda não há GPS, para o
            // mapa não ficar sem linha (a legenda avisa que é a linha simbólica).
            route: mapMode === "symbolic" || !hasTrack ? journeyMap.symbolic_route : null,
          },
        ],
      }
    : null;
  const trackLines =
    mapMode === "real" && journeyMap
      ? journeyMap.tracks.features.map((f) => f.geometry.coordinates)
      : [];
  const distanceKm = journeyMap ? journeyMap.distance_m / 1000 : 0;

  return (
    <ScrollView style={s.screen} contentContainerStyle={{ paddingBottom: 48 }}>
      <View style={{ paddingTop: 50, paddingHorizontal: 24 }}>
        <Pressable onPress={goBack} accessibilityRole="button" accessibilityLabel="Voltar">
          <Text style={s.back}>← Voltar</Text>
        </Pressable>

        {editing ? (
          <View style={s.editBox}>
            <Text style={s.sectionLabel}>TÍTULO</Text>
            <TextInput
              style={s.editInput}
              value={editTitle}
              onChangeText={setEditTitle}
              placeholder="Título da jornada"
              placeholderTextColor={colors.placeholder}
            />
            <Text style={s.sectionLabel}>DESCRIÇÃO (OPCIONAL)</Text>
            <TextInput
              style={[s.editInput, { height: 90, textAlignVertical: "top" }]}
              value={editDesc}
              onChangeText={setEditDesc}
              placeholder="Sobre esta jornada..."
              placeholderTextColor={colors.placeholder}
              multiline
            />
            <Text style={s.sectionLabel}>ATMOSFERA (OPCIONAL)</Text>
            <TextInput
              style={s.editInput}
              value={editMood}
              onChangeText={setEditMood}
              placeholder="Ex.: noturno, nostálgico"
              placeholderTextColor={colors.placeholder}
            />
            <Text style={s.sectionLabel}>PRIVACIDADE</Text>
            <Pressable
              style={s.toggleRow}
              onPress={() => setEditPrivate((v) => !v)}
              accessibilityRole="switch"
              accessibilityState={{ checked: editPrivate }}
              accessibilityLabel="Alternar privacidade"
            >
              <View style={[s.track, editPrivate && s.trackOn]}>
                <View style={[s.knob, editPrivate && s.knobOn]} />
              </View>
              <Text style={s.toggleText}>
                {editPrivate ? "Só você vê esta jornada" : "Pode ser compartilhada"}
              </Text>
            </Pressable>
            {error ? <Text style={s.inlineError}>{error}</Text> : null}
            <View style={s.editActions}>
              <Pressable style={[s.primary, busy && s.disabled]} disabled={busy} onPress={saveEdit} accessibilityRole="button" accessibilityLabel="Salvar título e descrição">
                <Text style={s.primaryText}>{action === "edit" ? "Salvando..." : "Salvar"}</Text>
              </Pressable>
              <Pressable disabled={busy} onPress={() => { setEditing(false); setError(""); }} hitSlop={6} accessibilityRole="button" accessibilityLabel="Cancelar edição">
                <Text style={s.confirmNo}>Cancelar</Text>
              </Pressable>
            </View>
          </View>
        ) : (
          <>
            <View style={s.titleRow}>
              <Text style={s.title}>{journey.title}</Text>
              <View style={[s.badge, { backgroundColor: STATUS_COLOR[st] }]}>
                <Text style={s.badgeText}>{STATUS_LABEL[st]}</Text>
              </View>
            </View>
            {journey.description ? <Text style={s.desc}>{journey.description}</Text> : null}
            {journey.mood ? <Text style={s.mood}>{journey.mood}</Text> : null}
            <Text style={s.meta}>
              {journey.points_count} {journey.points_count === 1 ? "memória" : "memórias"}
              {journey.started_at ? ` · início ${formatDate(journey.started_at)}` : ""}
              {journey.ended_at ? ` · fim ${formatDate(journey.ended_at)}` : ""}
              {!journey.is_private ? " · pública" : ""}
            </Text>
            <Pressable onPress={openEdit} hitSlop={6} accessibilityRole="button" accessibilityLabel="Editar jornada">
              <Text style={s.editLink}>Editar jornada</Text>
            </Pressable>
          </>
        )}

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

        {error && !editing ? <Text style={s.inlineError}>{error}</Text> : null}

        {/* Percurso real (GPS): controles de gravação + mapa + distância */}
        <Text style={s.sectionLabel}>PERCURSO REAL</Text>

        {recorder.recording || recorder.paused ? (
          <View style={s.recBox}>
            <View style={s.recRow}>
              <View style={[s.recDot, recorder.recording && s.recDotOn]} />
              <Text style={s.recLabel}>
                {recorder.recording
                  ? `Percurso ativo · ${recorder.pointCount} ${recorder.pointCount === 1 ? "ponto" : "pontos"}`
                  : "Percurso pausado"}
              </Text>
            </View>
            <View style={s.recActions}>
              {recorder.recording ? (
                <Pressable style={s.secondary} onPress={recorder.pause} accessibilityRole="button" accessibilityLabel="Pausar percurso">
                  <Text style={s.secondaryText}>Pausar</Text>
                </Pressable>
              ) : (
                <Pressable style={s.primary} onPress={recorder.resume} accessibilityRole="button" accessibilityLabel="Retomar percurso">
                  <Text style={s.primaryText}>Retomar</Text>
                </Pressable>
              )}
              <Pressable style={s.secondary} onPress={recorder.finish} accessibilityRole="button" accessibilityLabel="Finalizar percurso">
                <Text style={s.secondaryText}>Finalizar</Text>
              </Pressable>
            </View>
          </View>
        ) : st !== "finished" ? (
          <Pressable
            style={({ pressed }) => [s.trackStart, pressed && { opacity: 0.9 }]}
            onPress={recorder.start}
            disabled={recorder.busy}
            accessibilityRole="button"
            accessibilityLabel="Iniciar percurso"
          >
            <Text style={s.trackStartText}>{recorder.busy ? "Preparando…" : "Iniciar percurso"}</Text>
          </Pressable>
        ) : null}
        {recorder.error ? <Text style={s.inlineError}>{recorder.error}</Text> : null}

        {hasMemories || hasTrack ? (
          <>
            <View style={s.modeRow}>
              <Pressable onPress={() => setMode("real")} hitSlop={6} accessibilityRole="button" accessibilityLabel="Ver percurso real">
                <Text style={[s.modeTab, mapMode === "real" && s.modeTabOn]}>Percurso real</Text>
              </Pressable>
              <Pressable onPress={() => setMode("symbolic")} hitSlop={6} accessibilityRole="button" accessibilityLabel="Conectar memórias">
                <Text style={[s.modeTab, mapMode === "symbolic" && s.modeTabOn]}>Conectar memórias</Text>
              </Pressable>
            </View>
            <View style={{ marginTop: 12 }}>
              <AtlasMap data={mapData} tracks={trackLines} onSelect={(mid) => router.push(`/memory/${mid}`)} />
            </View>
            <Text style={s.trackMeta}>
              {hasTrack
                ? `${distanceKm.toFixed(2)} km de percurso real registrado`
                : "Sem percurso real ainda — mostrando a linha simbólica entre as memórias."}
            </Text>
            {hasTrack && !hasMemories ? (
              <Text style={s.trackHint}>
                Seu caminho foi registrado. Agora adicione memórias aos lugares que fizeram parte
                dessa jornada.
              </Text>
            ) : null}
          </>
        ) : (
          <Text style={s.emptyPoints}>
            Esta jornada ainda não tem caminho. Inicie um percurso ou adicione memórias para
            começar a construir este mapa.
          </Text>
        )}

        {/* Pontos ordenados */}
        <Text style={s.sectionLabel}>MEMÓRIAS (NA ORDEM DO RASTRO)</Text>
        {journey.points.length === 0 ? (
          <Text style={s.emptyPoints}>
            Esta jornada ainda está vazia. Adicione uma memória nova ou traga uma memória que
            você já registrou para começar a construir este mapa.
          </Text>
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
              <Pressable style={s.linkExisting} onPress={openAdd} accessibilityRole="button" accessibilityLabel="Trazer memória existente">
                <Text style={s.linkExistingText}>Trazer uma memória que já existe</Text>
              </Pressable>
            ) : (
              <View style={s.addBox}>
                <Text style={s.sectionLabel}>MEMÓRIAS SOLTAS</Text>
                {addError ? <Text style={s.inlineError}>{addError}</Text> : null}
                {loose === null ? (
                  <ActivityIndicator color={colors.terra} style={{ marginVertical: 16 }} />
                ) : loose.length === 0 ? (
                  <Text style={s.emptyPoints}>Nenhuma memória solta para trazer.</Text>
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
  editBox: { marginTop: 16 },
  editInput: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.line,
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 15,
    color: colors.ink,
    marginBottom: 6,
  },
  editActions: { flexDirection: "row", alignItems: "center", gap: 18, marginTop: 8 },
  editLink: { color: colors.teal, fontSize: 13, fontWeight: "600", marginTop: 10 },
  mood: { fontFamily: serif, fontStyle: "italic", color: colors.inkSoft, fontSize: 14.5, marginTop: 6 },
  toggleRow: { flexDirection: "row", alignItems: "center", gap: 12, marginTop: 2, marginBottom: 4 },
  track: { width: 46, height: 27, borderRadius: 14, backgroundColor: "rgba(35,39,47,0.18)", padding: 3, justifyContent: "center" },
  trackOn: { backgroundColor: colors.sage },
  knob: { width: 21, height: 21, borderRadius: 11, backgroundColor: colors.card },
  knobOn: { alignSelf: "flex-end" },
  toggleText: { color: colors.inkSoft, fontSize: 14, flex: 1 },
  // Percurso real
  recBox: { marginTop: 4, backgroundColor: "rgba(206,90,44,0.08)", borderRadius: 12, padding: 12, gap: 10 },
  recRow: { flexDirection: "row", alignItems: "center", gap: 8 },
  recDot: { width: 10, height: 10, borderRadius: 5, backgroundColor: colors.inkSoft },
  recDotOn: { backgroundColor: colors.terra },
  recLabel: { color: colors.ink, fontSize: 14, fontWeight: "600" },
  recActions: { flexDirection: "row", flexWrap: "wrap", gap: 10 },
  trackStart: { backgroundColor: colors.ink, borderRadius: 11, paddingVertical: 12, alignItems: "center" },
  trackStartText: { color: colors.card, fontSize: 14, fontWeight: "600", letterSpacing: 0.3 },
  modeRow: { flexDirection: "row", gap: 20, marginTop: 18, borderBottomWidth: 1, borderColor: colors.line, paddingBottom: 8 },
  modeTab: { color: colors.inkSoft, fontSize: 14, fontWeight: "600" },
  modeTabOn: { color: colors.terra },
  trackMeta: { color: colors.terraDeep, fontSize: 12, fontWeight: "600", marginTop: 10 },
  trackHint: { color: colors.inkSoft, fontSize: 13, lineHeight: 19, marginTop: 8 },
});
