import { Tabs } from "expo-router";

import JourneyTabBar from "../../components/JourneyTabBar";

// Área autenticada: abas com a tab bar customizada (Tempo · Criar · Atlas).
// A proteção real é por API (401 → volta ao login, tratado em cada tela), como
// já fazia a home. Um guard de token no layout fica para um bloco futuro.
export default function AppTabsLayout() {
  return (
    <Tabs tabBar={() => <JourneyTabBar />} screenOptions={{ headerShown: false }} initialRouteName="atlas">
      <Tabs.Screen name="atlas" />
      <Tabs.Screen name="timeline" />
    </Tabs>
  );
}
