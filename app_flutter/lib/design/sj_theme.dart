import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Acesso ao esquema de cores ativo (claro/escuro) em qualquer ponto da árvore.
///
/// Os componentes do design system leem `SJTheme.of(context)` para pintar-se no
/// modo vigente — em vez de importar `sjLight`/`sjDark` direto. O app (e o preview
/// da galeria) envolve a subárvore com `SJTheme(scheme: ...)`.
class SJTheme extends InheritedWidget {
  const SJTheme({super.key, required this.scheme, required super.child});

  final SJScheme scheme;

  static SJScheme of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<SJTheme>();
    // Fallback seguro: se ninguém proveu (ex.: componente usado fora do app),
    // assume o modo claro (padrão do produto) em vez de estourar.
    return widget?.scheme ?? sjLight;
  }

  @override
  bool updateShouldNotify(SJTheme oldWidget) => oldWidget.scheme != scheme;
}
