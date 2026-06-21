import { useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";
import { router } from "expo-router";

import { colors } from "../theme/colors";
import { ui } from "../theme/styles";

export default function ForgotPasswordScreen() {
  const [email, setEmail] = useState("");

  return (
    <View style={ui.screen}>
      <View style={ui.header}>
        <View style={ui.sun} />
        <View style={ui.hill} />
      </View>

      <View style={ui.body}>
        <Text style={ui.title}>Recuperar senha</Text>
        <Text style={ui.subtitle}>
          Informe seu e-mail e enviaremos um link para você voltar à sua jornada.
        </Text>

        <Text style={ui.label}>E-MAIL</Text>
        <TextInput
          style={ui.input}
          value={email}
          onChangeText={setEmail}
          placeholder="voce@email.com"
          placeholderTextColor={colors.placeholder}
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="email-address"
        />

        <Pressable
          style={({ pressed }) => [ui.button, pressed && ui.buttonPressed]}
          onPress={() => {
            // Recuperação de senha é pós-MVP (envio de e-mail + token).
          }}
        >
          <Text style={ui.buttonText}>Enviar link de recuperação</Text>
        </Pressable>

        <Pressable style={ui.backWrap} onPress={() => router.push("/")}>
          <Text style={ui.back}>← Voltar ao login</Text>
        </Pressable>
      </View>
    </View>
  );
}
