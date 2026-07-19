import 'package:flutter/material.dart';

/// Paleta "primeira classe": a base navy noturna com a coloração da arte —
/// VINHO (ação, jornadas, rastros) + AZUL CIANO (links, pontos soltos), ouro
/// nas molduras/overlines. Espelha mobile/src/theme/colors.ts.
abstract final class SJColors {
  static const pageBg = Color(0xFF080D18);
  static const paper = Color(0xFF0D1524);
  static const card = Color(0xFF16213A);
  static const ink = Color(0xFFF3ECDC);
  static const inkSoft = Color(0xFF9AA3B8);
  static const frame = Color(0xFF8C7440);
  static const gold = Color(0xFFE3B04B);
  static const goldDeep = Color(0xFFB88930);
  static const wine = Color(0xFFB7314F);
  static const wineDeep = Color(0xFF8A2740);
  static const cyan = Color(0xFF25B2C6);
  static const cyanDeep = Color(0xFF12707E);
  static const bloom = Color(0xFFD9A94E);
  static const sand = Color(0xFF16213A);
  static const placeholder = Color(0xFF6B7488);
  static const line = Color(0x1FF3ECDC); // creme a 12%
  static const danger = Color(0xFFE4604E);
  static const chip = Color(0x29B7314F); // vinho a 16%
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
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: SJColors.paper,
    colorScheme: const ColorScheme.dark(
      primary: SJColors.wine,
      onPrimary: SJColors.ink,
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
      selectionColor: Color(0x3325B2C6),
      selectionHandleColor: SJColors.cyan,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SJColors.card,
      hintStyle: const TextStyle(color: SJColors.placeholder, fontSize: 15),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0x29F3ECDC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: SJColors.cyan, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: SJColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: SJColors.danger, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SJColors.wine,
        foregroundColor: SJColors.ink,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
