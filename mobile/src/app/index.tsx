import { useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";
import { router } from "expo-router";

import { colors } from "../theme/colors";
import { ui } from "../theme/styles";

export default function LoginScreen() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  return (
    <View style={ui.screen}>
      <View style={ui.header}>
        <View style={ui.sun} />
        <View style={ui.hill} />
      </View>

      <View style={ui.body}>
        <View style={ui.brandRow}>
          <View style={ui.pin} />
          <Text style={ui.wordmark}>Some Journey</Text>
        </View>
        <Text style={ui.tagline}>A vida deixa rastros.</Text>

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

        <Text style={ui.label}>SENHA</Text>
        <TextInput
          style={ui.input}
          value={password}
          onChangeText={setPassword}
          placeholder="••••••••"
          placeholderTextColor={colors.placeholder}
          secureTextEntry
        />

        <Pressable style={ui.forgotWrap} onPress={() => router.push("/forgot-password")}>
          <Text style={ui.forgot}>Esqueci minha senha</Text>
        </Pressable>

        <Pressable
          style={({ pressed }) => [ui.button, pressed && ui.buttonPressed]}
          onPress={() => {
            // TODO: chamar POST /auth/login, guardar o token e ir para o mapa
          }}
        >
          <Text style={ui.buttonText}>Entrar</Text>
        </Pressable>

        <View style={ui.footerRow}>
          <Text style={ui.footerText}>Não tem conta? </Text>
          <Pressable onPress={() => router.push("/register")}>
            <Text style={ui.footerLink}>Criar conta</Text>
          </Pressable>
        </View>
      </View>
    </View>
  );
}
