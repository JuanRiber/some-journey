import type { JourneyStatus } from "./api";
import { colors } from "../theme/colors";

// Rótulo e cor de cada status de jornada (draft/active/paused/finished),
// compartilhados pela lista e pelo detalhe.
export const STATUS_LABEL: Record<JourneyStatus, string> = {
  draft: "Rascunho",
  active: "Ativa",
  paused: "Pausada",
  finished: "Concluída",
};

// Selos com TEXTO CREME (ver badgeText nas telas): todas as cores são
// escuras/médias o bastante para o creme ler ≥5:1. Rascunho = ardósia,
// ativa = vinho, pausada = bronze, concluída = ciano profundo.
export const STATUS_COLOR: Record<JourneyStatus, string> = {
  draft: "#4A5364",
  active: colors.wine,
  paused: "#8A5A1E",
  finished: colors.cyanDeep,
};
