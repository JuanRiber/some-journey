import { Image } from "expo-image";
import { StyleSheet, View } from "react-native";

import { colors } from "../theme/colors";

// "Primeira classe": a arte de marca do Some Journey — o viajante lendo o
// atlas no vagão, com o vale na janela e o logotipo/tagline aplicados na
// própria arte (ilustração vintage retocada). Emoldurada em ouro envelhecido.
// Asset raster via expo-image; proporção fixa para a composição nunca cortar.
export default function JourneyHeader() {
  return (
    <View style={s.mat}>
      <View style={s.frame}>
        <Image
          source={require("../../assets/images/first-class-art.jpg")}
          style={s.art}
          contentFit="cover"
          accessibilityLabel="Ilustração: viajante lendo o atlas num vagão de primeira classe, montanhas na janela"
        />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  mat: { paddingTop: 62, paddingHorizontal: 26, backgroundColor: colors.paper },
  frame: {
    backgroundColor: colors.frame,
    padding: 2,
    borderRadius: 3,
    width: "100%",
    maxWidth: 640,
    alignSelf: "center",
  },
  art: { width: "100%", aspectRatio: 2.25, borderRadius: 2, backgroundColor: colors.sand },
});
