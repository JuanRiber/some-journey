import { useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";
import { router } from "expo-router";

import { colors } from "../theme/colors";
import { ui } from "../theme/styles";

export default function RegisterScreen() {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  return (
    <View style={ui.screen}>
      <View style={ui.header}>
        <View style={ui.sun} />
        <View style={ui.hill} />
      </View>

      <View style={ui.body}>
        <Text style={ui.title}>Criar conta</Text>
        <Text style={ui.subtitle}>Comece o seu atlas pessoal.</Text>

        <Text style={ui.label}>NOME</Text>
        <TextInput
          style={ui.input}
          value={name}
          onChangeText={setName}
          placeholder="Seu nome"
          placeholderTextColor={colors.placeholder}
        />

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
        <Text style={ui.hint}>Mínimo de 7 caracteres.</Text>

        <Pressable
          style={({ pressed }) => [ui.button, pressed && ui.buttonPressed]}
          onPress={() => {
            // TODO: chamar POST /auth/register e voltar para o login
          }}
        >
          <Text style={ui.buttonText}>Criar conta</Text>
        </Pressable>

        <View style={ui.footerRow}>
          <Text style={ui.footerText}>Já tem conta? </Text>
          <Pressable onPress={() => router.push("/")}>
            <Text style={ui.footerLink}>Entrar</Text>
          </Pressable>
        </View>
      </View>
    </View>
  );
}
