import { Platform } from "react-native";

// Paleta "primeira classe": a base navy noturna da landing, agora com a
// coloração da própria arte — VINHO (ação, jornadas, rastros) + AZUL CIANO
// (links, pontos soltos, o secundário), com o ouro reservado a molduras,
// overlines e numerais. Base escura e editorial; a cor pulsa nos acentos.
export const colors = {
  // Navy mais fundo (atrás de tudo, barras).
  pageBg: "#080D18",
  // O navy da landing: superfície principal.
  paper: "#0D1524",
  // Superfície elevada dos cards.
  card: "#16213A",
  // Creme quente: o texto principal (a "tinta" clara da noite).
  ink: "#F3ECDC",
  inkSoft: "#9AA3B8",
  // Moldura dourada envelhecida das "artes" (ilustração, mapa, foto).
  frame: "#8C7440",
  // Ouro: molduras, overlines e numerais (o acento quente, contido).
  gold: "#E3B04B",
  goldDeep: "#B88930",
  // VINHO: ação primária, jornadas, rastros, o que está ativo (o terno da arte).
  wine: "#B7314F",
  wineDeep: "#8A2740",
  // AZUL CIANO: links, pontos soltos, o secundário (a camisa da arte).
  cyan: "#25B2C6",
  cyanDeep: "#12707E",
  // Ouro suave dos itálicos afetivos (tagline, atmosfera, datas).
  bloom: "#D9A94E",
  // Campo noturno: placeholders de mapa/foto e capas sem imagem.
  sand: "#16213A",
  placeholder: "#6B7488",
  line: "rgba(243,236,220,0.12)",
  danger: "#E4604E",
  // Capa de jornada sem imagem: campo noturno com gravuras douradas.
  cover: "#16213A",
  // Fundo dos chips (atmosfera, período): vinho muito leve.
  chip: "rgba(183,49,79,0.16)",
};

// Serifa editorial da landing: títulos, conteúdo das memórias e itálicos.
export const serif = Platform.select({
  web: "Georgia, 'Times New Roman', serif",
  ios: "Georgia",
  default: "serif",
}) as string;

// Mono das overlines e botões (o "01 / OS MOMENTOS" da landing).
export const mono = Platform.select({
  web: "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",
  ios: "Menlo",
  default: "monospace",
}) as string;
