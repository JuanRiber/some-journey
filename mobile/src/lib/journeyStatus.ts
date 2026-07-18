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

// Selos vivos sobre o navy (texto escuro em cima; ver badgeText nas telas):
// ativa = coral, pausada = dourado, concluída = violeta (o atlas permanente).
export const STATUS_COLOR: Record<JourneyStatus, string> = {
  draft: colors.inkSoft,
  active: colors.coral,
  paused: colors.gold,
  finished: colors.violet,
};
