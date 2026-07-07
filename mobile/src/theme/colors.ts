import { Platform } from "react-native";

// Paleta destilada das referências (ligne claire · old money · caderno de viagem).
export const colors = {
  pageBg: "#E7D9BC",
  paper: "#F2E7CE",
  card: "#FBF6E8",
  ink: "#23272F",
  inkSoft: "#6E6C5E",
  terra: "#CE5A2C",
  terraDeep: "#A2431F",
  teal: "#3D8A98",
  ochre: "#E0A93A",
  sage: "#788B4E",
  sky: "#AEC9D2",
  placeholder: "#9C947F",
  line: "rgba(35,39,47,0.12)",
  danger: "#A32D2D",
  // Faixa de "capa" de jornada quando não há imagem: areia de mapa desbotado.
  cover: "#E3D5B4",
  // Fundo dos chips (atmosfera, período): tinta quente muito leve.
  chip: "rgba(206,90,44,0.10)",
};

// Serifa editorial (old money). Georgia no web/iOS; "serif" no Android.
export const serif = Platform.select({
  web: "Georgia, 'Times New Roman', serif",
  ios: "Georgia",
  default: "serif",
}) as string;
