import "../global.css";

import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { SafeAreaProvider } from "react-native-safe-area-context";

import { colors } from "../theme/colors";

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: colors.paper },
        }}
      />
      {/* Papel quente é claro: os ícones da barra de status precisam ser ESCUROS
          (com "light" eles ficariam brancos sobre creme, ou seja, invisíveis). */}
      <StatusBar style="dark" />
    </SafeAreaProvider>
  );
}
