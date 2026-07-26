import 'package:flutter/material.dart';

/// Tema COMPARTILHADO (legado) — agora reapontado para a paleta "papel quente".
///
/// Historicamente estas constantes eram o "atlas noturno" (navy escuro). O
/// produto adotou o PAPEL QUENTE como modo padrão (ver `lib/design/tokens.dart`,
/// a fonte única da verdade). Como ~19 telas leem estes MESMOS nomes
/// (`SJColors.wine`, `serif(...)`, `monoLabel(...)`), reapontá-los aqui migra o
/// app inteiro para o novo visual sem reescrever cada tela — os NOMES/roles
/// continuam iguais, só os VALORES mudaram para o esquema claro `sjLight`.
///
/// A migração fina para dois modos (claro/escuro por tela, via
/// `SJTheme.of(context)` + componentes de `lib/design/`) é a etapa editorial
/// seguinte; este arquivo garante que, enquanto isso, tudo já respire papel.
abstract final class SJColors {
  static const pageBg = Color(0xFFECE3D2); // bgDeep — barras/fundo recuado
  static const paper = Color(0xFFF5F0E6); // bg — superfície principal (creme)
  static const card = Color(0xFFFBF8F1); // surface — cards (off-white)
  static const ink = Color(0xFF2B2724); // tinta marrom quente
  static const inkSoft = Color(0xFF6E6353);
  static const frame = Color(0xFFC4AE86); // moldura couro
  static const gold = Color(0xFF7A5A2E); // acento couro (overlines/numerais)
  static const goldDeep = Color(0xFF5E4522);
  static const wine = Color(0xFF6E2C3A); // ação primária / jornada ativa
  static const wineDeep = Color(0xFF57222D);
  static const cyan = Color(0xFF2E6C7E); // links / pontos soltos (azul-lago)
  static const cyanDeep = Color(0xFF224E5B);
  static const bloom = Color(0xFF8A6A34); // itálicos afetivos / datas
  static const sand = Color(0xFFEFE7D7); // surfaceAlt — campos/placeholders
  static const placeholder = Color(0xFF9C917E);
  static const line = Color(0x1A2B2724); // tinta a 10%
  static const danger = Color(0xFFA6392C);
  static const chip = Color(0x1F6E2C3A); // vinho a ~12%
}

/// Serifa editorial (Georgia) para títulos e itálicos afetivos.
const serifFamily = 'Georgia';
const serifFallback = ['Times New Roman', 'serif'];

/// Mono das overlines, selos e botões.
const monoFamily = 'Menlo';
const monoFallback = ['Consolas', 'Courier New', 'monospace'];

TextStyle serif(double size, {Color color = SJColors.ink, FontStyle? style, double? height}) =>
    TextStyle(
      fontFamily: serifFamily,
      fontFamilyFallback: serifFallback,
      fontSize: size,
      color: color,
      fontStyle: style,
      height: height,
    );

TextStyle monoLabel(double size, {Color color = SJColors.bloom, FontWeight weight = FontWeight.w400}) =>
    TextStyle(
      fontFamily: monoFamily,
      fontFamilyFallback: monoFallback,
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: 1.6,
    );

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    scaffoldBackgroundColor: SJColors.paper,
    colorScheme: const ColorScheme.light(
      primary: SJColors.wine,
      onPrimary: Color(0xFFF7F1E7),
      secondary: SJColors.cyan,
      surface: SJColors.card,
      onSurface: SJColors.ink,
      error: SJColors.danger,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: SJColors.ink, displayColor: SJColors.ink),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: SJColors.cyan,
      selectionColor: Color(0x332E6C7E),
      selectionHandleColor: SJColors.cyan,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SJColors.sand,
      hintStyle: const TextStyle(color: SJColors.placeholder, fontSize: 15),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: SJColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: SJColors.cyan, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: SJColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: SJColors.danger, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SJColors.wine,
        foregroundColor: const Color(0xFFF7F1E7),
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: TextStyle(
          fontFamily: monoFamily,
          fontFamilyFallback: monoFallback,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: SJColors.wine),
  );
}
