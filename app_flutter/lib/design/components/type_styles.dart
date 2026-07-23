import 'package:flutter/widgets.dart';

import '../tokens.dart';

/// # Estilos tipográficos derivados dos tokens (`SJType`).
///
/// PORQUÊ existe: os componentes precisam de `TextStyle`s prontos que já
/// carreguem família + fallback + tamanho + altura de linha + tracking corretos.
/// Reescrever isso à mão em cada widget convida a erros (uma serifa com altura
/// errada quebra o "muito contraste título↔corpo" do design). Este helper é a
/// tradução 1:1 da escala do `tokens.dart` para estilos usáveis — NÃO inventa
/// tamanhos novos, só compõe os existentes. A cor fica opcional de propósito:
/// quem chama passa `scheme.ink`/`scheme.accent`/etc. conforme o papel.
abstract final class SJText {
  // Serifa editorial — títulos e conteúdo afetivo. Um tracking levemente
  // negativo nos tamanhos grandes deixa a serifa mais "impressa", menos larga.
  static TextStyle _serif(
    double size,
    double line,
    Color? color,
    FontWeight w,
    double tracking,
  ) => TextStyle(
    fontFamily: SJType.serif,
    fontFamilyFallback: SJType.serifFallback,
    fontSize: size,
    height: line / size,
    fontWeight: w,
    letterSpacing: tracking,
    color: color,
  );

  // Sans de interface — corpo, labels, textos de sistema. Calmo e legível.
  static TextStyle _sans(
    double size,
    double line,
    Color? color,
    FontWeight w,
  ) => TextStyle(
    fontFamily: SJType.sans,
    fontFamilyFallback: SJType.sansFallback,
    fontSize: size,
    height: line / size,
    fontWeight: w,
    color: color,
  );

  /// Display 34/40 — abertura de tela, número grande da jornada.
  static TextStyle display({
    Color? color,
    FontWeight weight = FontWeight.w600,
  }) => _serif(SJType.displaySize, SJType.displayLine, color, weight, -0.4);

  /// H1 28/34 — título de página.
  static TextStyle h1({Color? color, FontWeight weight = FontWeight.w600}) =>
      _serif(SJType.h1Size, SJType.h1Line, color, weight, -0.3);

  /// H2 22/28 — título de seção (usado no `SJSectionHeader`).
  static TextStyle h2({Color? color, FontWeight weight = FontWeight.w600}) =>
      _serif(SJType.h2Size, SJType.h2Line, color, weight, -0.2);

  /// Title 18/24 — título de card / item.
  static TextStyle title({Color? color, FontWeight weight = FontWeight.w600}) =>
      _serif(SJType.titleSize, SJType.titleLine, color, weight, 0);

  /// Body 16/24 — corpo padrão.
  static TextStyle body({Color? color, FontWeight weight = FontWeight.w400}) =>
      _sans(SJType.bodySize, SJType.bodyLine, color, weight);

  /// Body pequeno 14/20 — legendas de apoio, hints.
  static TextStyle bodySm({
    Color? color,
    FontWeight weight = FontWeight.w400,
  }) => _sans(SJType.bodySmSize, SJType.bodySmLine, color, weight);

  /// Caption 13/18 — metadados, textos de erro.
  static TextStyle caption({
    Color? color,
    FontWeight weight = FontWeight.w400,
  }) => _sans(SJType.captionSize, SJType.captionLine, color, weight);

  /// Overline mono 11/16 CAIXA ALTA com tracking 1.6 — o motivo "01 / TÍTULO".
  /// (O widget que renderiza é quem faz o `.toUpperCase()`; aqui só o estilo.)
  static TextStyle overline({
    Color? color,
    FontWeight weight = FontWeight.w600,
  }) => TextStyle(
    fontFamily: SJType.mono,
    fontFamilyFallback: SJType.monoFallback,
    fontSize: SJType.overlineSize,
    height: SJType.overlineLine / SJType.overlineSize,
    fontWeight: weight,
    letterSpacing: SJType.overlineTracking,
    color: color,
  );

  /// Label de botão — mono CAIXA ALTA, um pouco maior/mais espaçado que a
  /// overline, para dar peso à ação. Quem chama faz `.toUpperCase()`.
  static TextStyle button({
    Color? color,
    double size = 13,
    FontWeight weight = FontWeight.w600,
  }) => TextStyle(
    fontFamily: SJType.mono,
    fontFamilyFallback: SJType.monoFallback,
    fontSize: size,
    height: 1.0,
    fontWeight: weight,
    letterSpacing: 1.2,
    color: color,
  );
}
