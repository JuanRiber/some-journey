import 'package:flutter/widgets.dart';

import '../sj_theme.dart';
import '../tokens.dart';
import 'overline.dart';
import 'type_styles.dart';

/// # Cabeçalho de seção — `SJSectionHeader`
///
/// PORQUÊ: padroniza o "início de bloco" das telas — overline (com numeral
/// opcional) empilhada sobre um título em serifa (`h2`), com uma ação de texto
/// opcional alinhada à direita (ex.: "Ver tudo"). Concentrar a anatomia aqui
/// garante o mesmo respiro vertical e o mesmo contraste overline↔título em toda
/// parte, em vez de cada tela montar isso à mão.
class SJSectionHeader extends StatelessWidget {
  const SJSectionHeader({
    super.key,
    required this.title,
    this.overline,
    this.numeral,
    this.action,
  });

  /// Título em serifa (h2).
  final String title;

  /// Texto da overline mono acima do título (opcional).
  final String? overline;

  /// Numeral do motivo "01 / TÍTULO" (só usado quando há `overline`).
  final String? numeral;

  /// Ação à direita, alinhada ao título (ex.: um `SJButton` variante text).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (overline != null) ...[
          SJOverline(overline!, numeral: numeral),
          const SizedBox(height: SJSpace.x2),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(title, style: SJText.h2(color: s.ink)),
            ),
            if (action != null) ...[const SizedBox(width: SJSpace.x3), action!],
          ],
        ),
      ],
    );
  }
}
