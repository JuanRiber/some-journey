import { Platform } from "react-native";

// Paleta "atlas noturno": o navy profundo da landing com serifa creme, e a
// vida de viajante nos acentos — dourado (ação), coral (jornadas/rastros),
// menta (pontos soltos/links) e violeta (o atlas permanente). Base escura e
// editorial; a cor pulsa nos pins, selos, trilhas e numerais.
export const colors = {
  // Navy mais fundo (atrás de tudo, barras).
  pageBg: "#080D18",
  // O navy da landing: superfície principal.
  paper: "#0D1524",
  // Superfície elevada dos cards.
  card: "#141E33",
  // Creme quente: o texto principal (a "tinta" clara da noite).
  ink: "#F2EAD8",
  inkSoft: "#98A0B3",
  // Moldura dourada envelhecida das "artes" (ilustração, mapa, foto).
  frame: "#8C7440",
  // Dourado da landing: ação primária, numerais, overlines.
  gold: "#E3B04B",
  goldDeep: "#B88930",
  // Coral vivo: jornadas, rastros, o que está ativo.
  coral: "#F0784A",
  coralDeep: "#C85A2E",
  // Menta: pontos soltos, links, sucesso.
  mint: "#37C3A2",
  // Violeta: o selo do que ficou para sempre (jornadas concluídas).
  violet: "#8B7BF0",
  // Ouro suave dos itálicos afetivos (tagline, atmosfera, datas).
  bloom: "#D9A94E",
  // Campo noturno: placeholders de mapa/foto e capas sem imagem.
  sand: "#1B2740",
  placeholder: "#6B7488",
  line: "rgba(242,234,216,0.10)",
  danger: "#E4604E",
  // Capa de jornada sem imagem: campo noturno com gravuras douradas.
  cover: "#1B2740",
  // Fundo dos chips (atmosfera, período): coral muito leve.
  chip: "rgba(240,120,74,0.14)",
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
