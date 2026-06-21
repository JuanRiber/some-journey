import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";

import { colors } from "../theme/colors";

export default function RootLayout() {
  return (
    <>
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: colors.paper },
        }}
      />
      <StatusBar style="dark" />
    </>
  );
}
