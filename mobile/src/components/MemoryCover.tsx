import { Image } from "expo-image";
import { StyleSheet, View } from "react-native";

import { colors } from "../theme/colors";

type Props = { url?: string | null; size?: number };

// Capa da memória: mostra a foto (capa) quando existe; senão, um "livrinho" 2D
// marrom com um marcador vermelho — desenhado só com Views (sem react-native-svg,
// evitado no projeto por causa do bug no build web).
export default function MemoryCover({ url, size = 54 }: Props) {
  if (url) {
    return (
      <Image
        source={{ uri: url }}
        style={[s.box, { width: size, height: size }]}
        contentFit="cover"
      />
    );
  }
  const bookW = size * 0.5;
  const bookH = size * 0.66;
  return (
    <View style={[s.box, s.paper, { width: size, height: size }]}>
      <View style={{ width: bookW, height: bookH }}>
        <View style={s.cover} />
        <View style={s.spine} />
        <View style={s.bookmark} />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  box: {
    borderRadius: 10,
    borderWidth: 1,
    borderColor: colors.line,
    alignItems: "center",
    justifyContent: "center",
    overflow: "hidden",
  },
  paper: { backgroundColor: colors.card },
  cover: {
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: "#8A5A2B", // capa marrom
    borderRadius: 3,
  },
  spine: {
    position: "absolute",
    left: 0,
    top: 0,
    bottom: 0,
    width: 5,
    backgroundColor: "#5E3A17", // lombada (marrom escuro)
    borderTopLeftRadius: 3,
    borderBottomLeftRadius: 3,
  },
  bookmark: {
    position: "absolute",
    top: -3,
    right: "22%",
    width: 6,
    height: 15,
    backgroundColor: colors.danger, // marcador vermelho
    borderBottomLeftRadius: 2,
    borderBottomRightRadius: 2,
  },
});
