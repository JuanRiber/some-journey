import { ActivityIndicator, Text, View } from "react-native";
import { Tabs } from "expo-router";

import JourneyTabBar from "../../components/JourneyTabBar";
import { useRequireAuth } from "../../hooks/use-require-auth";
import { colors } from "../../theme/colors";

export default function AppTabsLayout() {
  const auth = useRequireAuth();

  if (auth.checking) {
    return (
      <View style={{ flex: 1, alignItems: "center", justifyContent: "center", backgroundColor: colors.paper }}>
        <ActivityIndicator color={colors.coral} />
      </View>
    );
  }

  if (auth.error) {
    return (
      <View style={{ flex: 1, alignItems: "center", justifyContent: "center", padding: 28, backgroundColor: colors.paper }}>
        <Text style={{ color: colors.danger, textAlign: "center", lineHeight: 20 }}>{auth.error}</Text>
      </View>
    );
  }

  return (
    <Tabs tabBar={() => <JourneyTabBar />} screenOptions={{ headerShown: false }} initialRouteName="atlas">
      <Tabs.Screen name="atlas" />
      <Tabs.Screen name="timeline" />
    </Tabs>
  );
}
