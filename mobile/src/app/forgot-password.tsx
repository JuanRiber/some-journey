import { Pressable, Text, View } from "react-native";
import { router } from "expo-router";

import JourneyHeader from "../components/JourneyHeader";
import { colors } from "../theme/colors";
import { ui } from "../theme/styles";

// Recuperação por e-mail ainda não existe (pós-MVP). Tela honesta: em vez de um
// botão que não faz nada, explica os caminhos reais de hoje.
export default function ForgotPasswordScreen() {
  return (
    <View style={ui.screen}>
      <JourneyHeader />

      <View style={ui.body}>
        <Text style={ui.title}>Recuperar senha</Text>
        <Text style={ui.subtitle}>A recuperação por e-mail ainda não está disponível.</Text>

        <Text style={{ color: colors.inkSoft, fontSize: 14, lineHeight: 22, marginTop: 18 }}>
          Se você já está logado, troque a senha em “Alterar senha”, no seu Atlas.
          {"\n\n"}
          Se esqueceu e não consegue entrar, peça ao desenvolvedor para redefinir a sua senha.
        </Text>

        <Pressable
          style={({ pressed }) => [ui.button, pressed && ui.buttonPressed, { marginTop: 28 }]}
          onPress={() => router.push("/")}
          accessibilityRole="button"
          accessibilityLabel="Voltar ao login"
        >
          <Text style={ui.buttonText}>Voltar ao login</Text>
        </Pressable>
      </View>
    </View>
  );
}
