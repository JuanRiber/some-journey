import { useCallback, useEffect, useRef, useState } from "react";
import * as Location from "expo-location";

import * as api from "./api";

// Gravador de percurso em PRIMEIRO PLANO (foreground). Enquanto a tela está
// aberta, captura pontos GPS (expo-location watchPositionAsync — funciona no web
// via Geolocation do navegador e no nativo com o app em foco) e envia em lotes
// ao backend. Pausar encerra o trecho atual; retomar abre um novo (vários
// trechos = uma experiência). NÃO faz rastreamento em segundo plano: isso exige
// expo-task-manager + permissões de background + dev build (o Expo Go não
// suporta). O usuário sempre inicia/para de forma explícita.

export type RecorderState = "idle" | "requesting" | "recording" | "paused" | "error";

// A cada N pontos no buffer, sobe um lote (evita segurar tudo em memória e
// perder dados se a tela fechar).
const FLUSH_EVERY = 5;

export function useTrackRecorder(journeyId: string, opts?: { onFlush?: () => void }) {
  const [state, setState] = useState<RecorderState>("idle");
  const [error, setError] = useState("");
  const [pointCount, setPointCount] = useState(0);

  const trackIdRef = useRef<string | null>(null);
  const bufferRef = useRef<api.TrackPointInput[]>([]);
  const subRef = useRef<Location.LocationSubscription | null>(null);
  // Envio em andamento (serializa os flushes) e flag de "encerrando o trecho".
  const pendingRef = useRef<Promise<void> | null>(null);
  const closingRef = useRef(false);
  const onFlushRef = useRef(opts?.onFlush);
  onFlushRef.current = opts?.onFlush;

  // Sobe UM lote (o que estiver no buffer). Não lança: em falha, devolve os
  // pontos ao buffer para retry — a menos que o trecho já esteja sendo encerrado
  // (aí o trackId pode ter sido finalizado; reinserir órfão só perderia os pontos).
  const flushOnce = useCallback(async () => {
    const trackId = trackIdRef.current;
    if (!trackId || bufferRef.current.length === 0) return;
    const batch = bufferRef.current.splice(0, bufferRef.current.length);
    try {
      await api.addTrackPoints(journeyId, trackId, batch);
      onFlushRef.current?.();
    } catch {
      if (!closingRef.current) bufferRef.current.unshift(...batch);
    }
  }, [journeyId]);

  // Serializa os envios: encadeia após o envio em andamento. Assim dois disparos
  // de flush nunca rodam em paralelo (sem duplicar nem corromper a ordem).
  const flush = useCallback((): Promise<void> => {
    const prev = pendingRef.current ?? Promise.resolve();
    const next = prev.then(() => flushOnce()).finally(() => {
      if (pendingRef.current === next) pendingRef.current = null;
    });
    pendingRef.current = next;
    return next;
  }, [flushOnce]);

  // Esvazia o buffer por completo: espera o envio em andamento e repete até zerar.
  const drain = useCallback(async () => {
    await pendingRef.current;
    while (trackIdRef.current && bufferRef.current.length > 0) {
      await flush();
    }
  }, [flush]);

  const stopWatch = useCallback(() => {
    if (subRef.current) {
      subRef.current.remove();
      subRef.current = null;
    }
  }, []);

  // Abre um trecho novo e começa a capturar. Usado por "Iniciar" e "Retomar".
  const begin = useCallback(async () => {
    setError("");
    setState("requesting");
    const { status } = await Location.requestForegroundPermissionsAsync();
    if (status !== "granted") {
      setError("Permissão de localização negada. Ative para gravar o percurso.");
      setState("error");
      return;
    }
    try {
      const track = await api.startTrack(journeyId);
      trackIdRef.current = track.id;
    } catch (e) {
      if (e instanceof api.ApiError && e.status === 409) {
        // Já existe um trecho aberto (ex.: a tela fechou no meio de uma gravação):
        // reaproveita em vez de falhar.
        const tracks = await api.listTracks(journeyId);
        const openTrack = tracks.find((track) => track.is_active);
        if (openTrack) {
          trackIdRef.current = openTrack.id;
        } else {
          setError(e.message);
          setState("error");
          return;
        }
      } else {
        setError(e instanceof api.ApiError ? e.message : "Não foi possível iniciar o percurso.");
        setState("error");
        return;
      }
    }
    try {
      subRef.current = await Location.watchPositionAsync(
        { accuracy: Location.Accuracy.Balanced, timeInterval: 5000, distanceInterval: 10 },
        (loc) => {
          bufferRef.current.push({
            latitude: loc.coords.latitude,
            longitude: loc.coords.longitude,
            accuracy: loc.coords.accuracy ?? null,
            altitude: loc.coords.altitude ?? null,
            speed: loc.coords.speed ?? null,
            heading: loc.coords.heading ?? null,
            recorded_at: new Date(loc.timestamp).toISOString(),
          });
          setPointCount((c) => c + 1);
          if (bufferRef.current.length >= FLUSH_EVERY) void flush();
        },
      );
      setState("recording");
    } catch {
      setError("Não foi possível acessar a localização.");
      setState("error");
    }
  }, [journeyId, flush]);

  // Encerra o trecho: para de capturar, AGUARDA todos os pontos subirem (sem
  // correr com o finish) e só então finaliza no backend. Compartilhado por
  // "Pausar" e "Finalizar". Se a rede falhar bem na hora de fechar, os pontos
  // pendentes se perdem (foreground, sem persistência offline — ver limitações).
  const closeSegment = useCallback(async () => {
    closingRef.current = true;
    stopWatch();
    try {
      await drain();
      const trackId = trackIdRef.current;
      trackIdRef.current = null;
      if (trackId) {
        try {
          await api.finishTrack(journeyId, trackId);
        } catch {
          // já pode ter sido finalizado; ignora
        }
      }
      onFlushRef.current?.();
    } finally {
      closingRef.current = false;
    }
  }, [journeyId, drain, stopWatch]);

  const start = useCallback(() => begin(), [begin]);
  const resume = useCallback(() => begin(), [begin]);
  const pause = useCallback(async () => {
    await closeSegment();
    setPointCount(0);
    setState("paused");
  }, [closeSegment]);
  const finish = useCallback(async () => {
    await closeSegment();
    setPointCount(0);
    setState("idle");
  }, [closeSegment]);

  // Se a tela fechar no meio, para o watch (o backend fica com o trecho aberto;
  // o usuário pode finalizá-lo ao voltar). Sem tracking em segundo plano.
  useEffect(() => () => stopWatch(), [stopWatch]);

  return {
    state,
    error,
    pointCount,
    recording: state === "recording",
    paused: state === "paused",
    busy: state === "requesting",
    start,
    pause,
    resume,
    finish,
  };
}
