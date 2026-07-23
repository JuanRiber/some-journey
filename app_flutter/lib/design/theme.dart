/// # Ponte tokens → Material 3
///
/// O app é Flutter/Material por baixo, mas a linguagem visual é nossa (papel
/// quente / atlas noturno). Este arquivo é o ÚNICO lugar onde os tokens
/// semânticos ([SJScheme], [SJType], [SJRadius]…) são "traduzidos" para o
/// `ThemeData` que o Material entende — assim os widgets crus do framework
/// (campos, botões, seleção de texto, spinner) já nascem no nosso tom em vez
/// de exibir o roxo/azul genérico do Material Design.
///
/// Por que uma função e não duas constantes? Porque as DUAS aparências saem do
/// MESMO mapeamento: `buildSjTheme(sjLight)` e `buildSjTheme(sjDark)` produzem
/// temas idênticos em estrutura, divergindo só nas cores do esquema. Um único
/// caminho de código = zero chance de o modo escuro "esquecer" um ajuste feito
/// no claro. O `MaterialApp` recebe os dois e alterna via `themeMode`.
///
/// Importante: os componentes do design system continuam lendo o
/// `SJTheme.of(context)` para detalhes finos (mono, overlines, molduras). Este
/// tema cobre o "chão" do Material; ele NÃO substitui o design system, apenas
/// evita que o padrão do framework vaze por baixo dele.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Constrói o [ThemeData] Material a partir de um [SJScheme] (claro OU escuro).
///
/// Chame com `sjLight` para o "papel quente" (padrão) e `sjDark` para o "atlas
/// noturno". O `brightness` do esquema propaga para o `ColorScheme`, então o
/// Material acerta sozinho contrastes de ícones/ripples de sistema.
ThemeData buildSjTheme(SJScheme scheme) {
  final isDark = scheme.brightness == Brightness.dark;

  // ── ColorScheme ──────────────────────────────────────────────────────────
  // Mapeamos papéis → slots do Material. `surface` é a cor de cards/superfícies
  // no M3 (o antigo `background` foi absorvido por ela). `tertiary` recebe o
  // acento (couro/ouro) para que qualquer widget que caia nele fique coerente.
  final colorScheme = ColorScheme(
    brightness: scheme.brightness,
    primary: scheme.primary,
    onPrimary: scheme.onPrimary,
    secondary: scheme.secondary,
    onSecondary: scheme.onPrimary,
    tertiary: scheme.accent,
    onTertiary: scheme.onPrimary,
    surface: scheme.surface,
    onSurface: scheme.ink,
    surfaceContainerHighest: scheme.surfaceAlt,
    outline: scheme.line,
    error: scheme.danger,
    onError: scheme.onPrimary,
  );

  // ── Tipografia ─────────────────────────────────────────────────────────────
  // Serifa editorial manda em display/headline/title (o "afeto" do diário);
  // sans calmo cuida do corpo e labels de interface. O mono (overlines/selos)
  // é aplicado pontualmente pelos componentes, não pelo textTheme global.
  TextStyle serif(double size, double line, FontWeight weight) => TextStyle(
        fontFamily: SJType.serif,
        fontFamilyFallback: SJType.serifFallback,
        fontSize: size,
        height: line / size,
        fontWeight: weight,
        color: scheme.ink,
      );

  TextStyle sans(double size, double line, Color color) => TextStyle(
        fontFamily: SJType.sans,
        fontFamilyFallback: SJType.sansFallback,
        fontSize: size,
        height: line / size,
        color: color,
      );

  final textTheme = TextTheme(
    // Títulos em serifa — muito contraste com o corpo.
    displayLarge: serif(SJType.displaySize, SJType.displayLine, FontWeight.w600),
    displayMedium: serif(SJType.h1Size, SJType.h1Line, FontWeight.w600),
    displaySmall: serif(SJType.h2Size, SJType.h2Line, FontWeight.w600),
    headlineLarge: serif(SJType.h1Size, SJType.h1Line, FontWeight.w600),
    headlineMedium: serif(SJType.h2Size, SJType.h2Line, FontWeight.w600),
    headlineSmall: serif(SJType.titleSize, SJType.titleLine, FontWeight.w600),
    titleLarge: serif(SJType.titleSize, SJType.titleLine, FontWeight.w600),
    titleMedium: serif(SJType.bodySize, SJType.bodyLine, FontWeight.w600),
    titleSmall: serif(SJType.bodySmSize, SJType.bodySmLine, FontWeight.w600),
    // Corpo/labels em sans.
    bodyLarge: sans(SJType.bodySize, SJType.bodyLine, scheme.ink),
    bodyMedium: sans(SJType.bodySmSize, SJType.bodySmLine, scheme.ink),
    bodySmall: sans(SJType.captionSize, SJType.captionLine, scheme.inkSoft),
    labelLarge: sans(SJType.bodySmSize, SJType.bodySmLine, scheme.ink),
    labelMedium: sans(SJType.captionSize, SJType.captionLine, scheme.inkSoft),
    labelSmall: sans(SJType.overlineSize, SJType.overlineLine, scheme.inkFaint),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    scaffoldBackgroundColor: scheme.bg,
    colorScheme: colorScheme,
    textTheme: textTheme,
    // Fonte-base do app (widgets que não passam por textTheme herdam sans).
    fontFamily: SJType.sans,
    fontFamilyFallback: SJType.sansFallback,
    // Divisores hairline no tom da tinta a ~10-12%.
    dividerColor: scheme.line,
    splashColor: scheme.primary.withValues(alpha: 0.08),
    highlightColor: scheme.primary.withValues(alpha: 0.06),
  );

  // Borda reutilizada pelos estados do campo (só a cor/espessura mudam).
  OutlineInputBorder inputBorder(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(SJRadius.md),
        borderSide: BorderSide(color: color, width: width),
      );

  return base.copyWith(
    // ── Campos ────────────────────────────────────────────────────────────
    // Preenchido em `surfaceAlt` (areia recuada), hairline `line`, foco no
    // `secondary` (azul-lago/ciano) 1.5px. Sem borda dura — nada de "caixa".
    // A label vira overline mono no tom do acento (o motivo "01 / TÍTULO").
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: SJSpace.x4,
        vertical: SJSpace.x3,
      ),
      hintStyle: TextStyle(
        color: scheme.inkFaint,
        fontFamily: SJType.sans,
        fontFamilyFallback: SJType.sansFallback,
        fontSize: SJType.bodySize,
      ),
      labelStyle: TextStyle(
        color: scheme.accent,
        fontFamily: SJType.mono,
        fontFamilyFallback: SJType.monoFallback,
        fontSize: SJType.overlineSize,
        letterSpacing: SJType.overlineTracking,
      ),
      floatingLabelStyle: TextStyle(
        color: scheme.accent,
        fontFamily: SJType.mono,
        fontFamilyFallback: SJType.monoFallback,
        fontSize: SJType.overlineSize,
        letterSpacing: SJType.overlineTracking,
      ),
      enabledBorder: inputBorder(scheme.line, 1),
      focusedBorder: inputBorder(scheme.secondary, 1.5),
      errorBorder: inputBorder(scheme.danger, 1),
      focusedErrorBorder: inputBorder(scheme.danger, 1.5),
      errorStyle: TextStyle(
        color: scheme.danger,
        fontFamily: SJType.sans,
        fontFamilyFallback: SJType.sansFallback,
        fontSize: SJType.captionSize,
      ),
    ),

    // ── Botão primário ──────────────────────────────────────────────────────
    // Preenchido em `primary` (vinho), texto `onPrimary`, label mono em CAIXA
    // ALTA com tracking (o conteúdo maiúsculo vem do widget). Raio md, sem
    // elevação — a "sombra" do app mora nos cards, não nos botões.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: scheme.primary.withValues(alpha: 0.35),
        disabledForegroundColor: scheme.onPrimary.withValues(alpha: 0.6),
        elevation: 0,
        minimumSize: const Size.fromHeight(48), // toque ≥ 44pt
        padding: const EdgeInsets.symmetric(vertical: SJSpace.x4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SJRadius.md),
        ),
        textStyle: const TextStyle(
          fontFamily: SJType.mono,
          fontFamilyFallback: SJType.monoFallback,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: SJType.overlineTracking,
        ),
      ),
    ),

    // ── Botão de texto (link) ─────────────────────────────────────────────
    // Papel de "link solto" → cor `secondary`, tipografia sans do corpo.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.secondary,
        textStyle: const TextStyle(
          fontFamily: SJType.sans,
          fontFamilyFallback: SJType.sansFallback,
          fontSize: SJType.bodySmSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // ── Seleção de texto ──────────────────────────────────────────────────
    // Cursor/alças no `secondary`; realce no mesmo tom bem transparente.
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.secondary,
      selectionColor: scheme.secondary.withValues(alpha: 0.28),
      selectionHandleColor: scheme.secondary,
    ),

    // ── Spinner ─────────────────────────────────────────────────────────────
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),

    // ── AppBar ────────────────────────────────────────────────────────────
    // Transparente sobre o fundo da página; título em serifa (o textTheme já
    // define o tom), sem a sombra/elevação padrão do Material.
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.bg,
      foregroundColor: scheme.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
      iconTheme: IconThemeData(color: scheme.ink),
    ),

    // Divisor fino coerente com hairlines.
    dividerTheme: DividerThemeData(
      color: scheme.line,
      thickness: 1,
      space: 1,
    ),

    // Ícones herdam a tinta por padrão.
    iconTheme: IconThemeData(color: scheme.ink),

    // Fundo de diálogos/sheets na superfície de card, sem sombra dura (o
    // desenho da sombra suave é feito pelos componentes via SJElevation).
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SJRadius.xl),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SJRadius.xl)),
      ),
    ),

    // Remove o tint automático do M3 nos cards (queremos a cor exata do token).
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SJRadius.lg),
      ),
    ),

    // Cor de fundo dos snackbars alinhada à tinta invertida do modo.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? scheme.surfaceAlt : scheme.ink,
      contentTextStyle: TextStyle(
        color: isDark ? scheme.ink : scheme.bg,
        fontFamily: SJType.sans,
        fontFamilyFallback: SJType.sansFallback,
        fontSize: SJType.bodySmSize,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SJRadius.md),
      ),
    ),
  );
}
