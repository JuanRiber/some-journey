import { ScrollView, Text, View } from "react-native";
import { Stack } from "expo-router";

import { componentStyles } from "../theme/components";
import { fonts, radius, sjDark, sjLight, space, type, type SJScheme } from "../theme/tokens";

/**
 * Galeria do Design System — vitrine viva de "papel quente" (claro) e "atlas
 * noturno" (escuro) LADO A LADO. Serve de referência visual e de teste de
 * fumaça: se algo aqui parece "Material cru", o token está errado.
 *
 * Renderiza os DOIS modos numa mesma tela (não usa `useTheme`, para exibir ambos
 * simultaneamente): cada seção instancia `componentStyles(scheme)` com o esquema
 * correspondente. Rota: `/design-gallery`.
 */

// Papéis de cor a exibir na paleta (nome do papel → chave do esquema).
const PALETTE: { role: string; key: keyof SJScheme }[] = [
  { role: "bgDeep", key: "bgDeep" },
  { role: "bg", key: "bg" },
  { role: "surface", key: "surface" },
  { role: "surfaceAlt", key: "surfaceAlt" },
  { role: "ink", key: "ink" },
  { role: "inkSoft", key: "inkSoft" },
  { role: "inkFaint", key: "inkFaint" },
  { role: "frame", key: "frame" },
  { role: "primary", key: "primary" },
  { role: "secondary", key: "secondary" },
  { role: "accent", key: "accent" },
  { role: "moss", key: "moss" },
  { role: "highlight", key: "highlight" },
  { role: "danger", key: "danger" },
];

// Amostras da escala tipográfica.
const TYPE_SAMPLES: { name: keyof typeof type; label: string }[] = [
  { name: "display", label: "Sua vida em lugares" },
  { name: "h1", label: "As jornadas" },
  { name: "h2", label: "Os momentos" },
  { name: "title", label: "Lisboa, ao entardecer" },
  { name: "body", label: "O corpo respira: 16pt, altura 24, calmo e legível." },
  { name: "bodySm", label: "Texto de apoio, 14pt." },
  { name: "caption", label: "Legenda / metadados, 13pt." },
];

function ModeShowcase({ scheme }: { scheme: SJScheme }) {
  const c = componentStyles(scheme);
  const modeName = scheme.brightness === "dark" ? "ATLAS NOTURNO" : "PAPEL QUENTE";

  return (
    <View style={{ backgroundColor: scheme.bg, padding: space.screenX, gap: space.x6 }}>
      {/* Cabeçalho do modo */}
      <View style={{ gap: space.x1 }}>
        <Text style={c.overline}>
          {scheme.brightness === "dark" ? "02 / ESCURO" : "01 / CLARO"}
        </Text>
        <Text style={{ fontFamily: fonts.serif, fontSize: type.h1.fontSize, lineHeight: type.h1.lineHeight, color: scheme.ink }}>
          {modeName}
        </Text>
      </View>

      {/* Paleta */}
      <View style={c.sectionHeader}>
        <Text style={c.overline}>PALETA</Text>
        <Text style={c.sectionTitle}>Papéis de cor</Text>
      </View>
      <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space.x3 }}>
        {PALETTE.map((p) => (
          <View key={p.role} style={{ width: 84, gap: space.x1 }}>
            <View
              style={{
                height: 48,
                borderRadius: radius.md,
                backgroundColor: scheme[p.key] as string,
                borderWidth: 1,
                borderColor: scheme.line,
              }}
            />
            <Text style={{ fontFamily: fonts.mono, fontSize: 10, color: scheme.inkSoft }}>{p.role}</Text>
          </View>
        ))}
      </View>

      {/* Tipografia */}
      <View style={c.sectionHeader}>
        <Text style={c.overline}>TIPOGRAFIA</Text>
        <Text style={c.sectionTitle}>Escala</Text>
      </View>
      <View style={{ gap: space.x3 }}>
        {TYPE_SAMPLES.map((t) => {
          const isSerif = t.name === "display" || t.name === "h1" || t.name === "h2" || t.name === "title";
          return (
            <Text
              key={t.name}
              style={{
                fontFamily: isSerif ? fonts.serif : fonts.sans,
                fontSize: type[t.name].fontSize,
                lineHeight: type[t.name].lineHeight,
                color: scheme.ink,
              }}
            >
              {t.label}
            </Text>
          );
        })}
        <Text style={c.overline}>11 / OVERLINE MONO</Text>
      </View>

      {/* Botões */}
      <View style={c.sectionHeader}>
        <Text style={c.overline}>BOTÕES</Text>
        <Text style={c.sectionTitle}>Ações</Text>
      </View>
      <View style={{ gap: space.x3 }}>
        <View style={c.buttonPrimary}>
          <Text style={c.buttonPrimaryLabel}>Criar memória</Text>
        </View>
        <View style={c.buttonSecondary}>
          <Text style={c.buttonSecondaryLabel}>Ver no mapa</Text>
        </View>
        <View style={c.buttonText}>
          <Text style={c.buttonTextLabel}>Esqueci minha senha</Text>
        </View>
      </View>

      {/* Input */}
      <View style={c.sectionHeader}>
        <Text style={c.overline}>CAMPO</Text>
        <Text style={c.sectionTitle}>Entrada</Text>
      </View>
      <View style={{ gap: space.x4 }}>
        <View>
          <Text style={c.inputLabel}>E-MAIL</Text>
          <View style={c.input}>
            <Text style={{ color: scheme.inkFaint, fontSize: type.body.fontSize }}>voce@email.com</Text>
          </View>
          <Text style={c.inputHint}>Usamos apenas para entrar.</Text>
        </View>
        <View>
          <Text style={c.inputLabel}>TÍTULO (EM FOCO)</Text>
          <View style={[c.input, c.inputFocused]}>
            <Text style={{ color: scheme.ink, fontSize: type.body.fontSize }}>Um dia em Sintra</Text>
          </View>
        </View>
      </View>

      {/* Cards */}
      <View style={c.sectionHeader}>
        <Text style={c.overline}>CARDS</Text>
        <Text style={c.sectionTitle}>Páginas de diário</Text>
      </View>
      <View style={{ gap: space.x4 }}>
        <View style={c.card}>
          <Text style={c.overline}>03 / DIÁRIO</Text>
          <Text style={{ fontFamily: fonts.serif, fontSize: type.title.fontSize, lineHeight: type.title.lineHeight, color: scheme.ink, marginTop: space.x2 }}>
            A luz caía dourada sobre o Tejo
          </Text>
          <Text style={{ fontFamily: fonts.sans, fontSize: type.body.fontSize, lineHeight: type.body.lineHeight, color: scheme.inkSoft, marginTop: space.x2 }}>
            Card em repouso: superfície, raio lg e sombra e1 — muito respiro.
          </Text>
        </View>

        {/* Foto-protagonista: imagem sangra no topo, texto complementa embaixo */}
        <View style={c.photoCard}>
          <View style={c.photoCardImage} />
          <View style={c.photoCardBody}>
            <Text style={c.photoCardTitle}>Miradouro da Graça</Text>
            <Text style={c.photoCardMeta}>Lisboa · julho de 2026</Text>
          </View>
        </View>
      </View>

      {/* Chips + Badge */}
      <View style={c.sectionHeader}>
        <Text style={c.overline}>SELOS</Text>
        <Text style={c.sectionTitle}>Chips e badges</Text>
      </View>
      <View style={{ flexDirection: "row", flexWrap: "wrap", alignItems: "center", gap: space.x3 }}>
        <View style={c.chip}>
          <Text style={c.chipLabel}>Nostálgico</Text>
        </View>
        <View style={c.chip}>
          <Text style={c.chipLabel}>Verão</Text>
        </View>
        <View style={c.badge}>
          <Text style={c.badgeLabel}>Novo</Text>
        </View>
      </View>

      {/* Sheet + FAB */}
      <View style={c.sectionHeader}>
        <Text style={c.overline}>FLUTUANTES</Text>
        <Text style={c.sectionTitle}>Sheet e FAB</Text>
      </View>
      <View style={c.sheet}>
        <View style={c.sheetGrabber} />
        <Text style={{ fontFamily: fonts.serif, fontSize: type.h2.fontSize, lineHeight: type.h2.lineHeight, color: scheme.ink }}>
          Adicionar à jornada
        </Text>
        <Text style={{ fontFamily: fonts.sans, fontSize: type.body.fontSize, lineHeight: type.body.lineHeight, color: scheme.inkSoft, marginTop: space.x2 }}>
          Bottom sheet: raio xl no topo, grabber e sombra e2.
        </Text>
      </View>
      <View style={{ flexDirection: "row", justifyContent: "flex-end" }}>
        <View style={c.fab}>
          <Text style={c.fabIcon}>+</Text>
        </View>
      </View>

      {/* Empty state */}
      <View style={c.sectionHeader}>
        <Text style={c.overline}>ESTADO VAZIO</Text>
        <Text style={c.sectionTitle}>Ensina o próximo passo</Text>
      </View>
      <View style={c.emptyState}>
        {/* Marcador de ilustração line-art (bússola/trilha entram no polimento). */}
        <View
          style={{
            width: 64,
            height: 64,
            borderRadius: radius.pill,
            borderWidth: 1.5,
            borderColor: scheme.frame,
          }}
        />
        <Text style={c.emptyStateTitle}>Sua primeira jornada começa aqui</Text>
        <Text style={c.emptyStateBody}>
          Ainda não há memórias. Crie uma e o mapa ganha vida.
        </Text>
        <View style={c.buttonPrimary}>
          <Text style={c.buttonPrimaryLabel}>Começar</Text>
        </View>
      </View>
    </View>
  );
}

export default function DesignGalleryScreen() {
  return (
    <>
      <Stack.Screen options={{ headerShown: true, title: "Design System" }} />
      <ScrollView>
        <ModeShowcase scheme={sjLight} />
        <ModeShowcase scheme={sjDark} />
      </ScrollView>
    </>
  );
}
