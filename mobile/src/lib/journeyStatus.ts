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

export const STATUS_COLOR: Record<JourneyStatus, string> = {
  draft: colors.inkSoft,
  active: colors.terra,
  paused: colors.ochre,
  finished: colors.sage,
};
