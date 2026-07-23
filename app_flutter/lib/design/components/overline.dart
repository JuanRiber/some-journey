import 'package:flutter/widgets.dart';

import '../sj_theme.dart';
import 'type_styles.dart';

/// # Overline — `SJOverline`
///
/// PORQUÊ: é a assinatura tipográfica da marca — mono, CAIXA ALTA, cor de
/// `accent` (couro no claro, ouro no escuro), com tracking largo. Aparece como
/// "rótulo de capítulo" acima de títulos e como selo de seção. O `numeral`
/// opcional reproduz o motivo "01 / OS MOMENTOS" da landing: o número é
/// esmaecido (`inkFaint`) e o título fica na cor do acento, separados por "/".
class SJOverline extends StatelessWidget {
  const SJOverline(this.text, {super.key, this.numeral, this.color});

  final String text;

  /// Numeral do motivo "01 / TÍTULO" (ex.: "01", "02"). Quando nulo, só o texto.
  final String? numeral;

  /// Sobrescreve a cor do acento (default = `scheme.accent`).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final accent = color ?? s.accent;
    final label = text.toUpperCase();

    if (numeral == null) {
      return Text(label, style: SJText.overline(color: accent));
    }

    // Numeral esmaecido + separador + título no acento, tudo na mesma linha.
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: numeral!.toUpperCase(),
            style: SJText.overline(color: s.inkFaint),
          ),
          TextSpan(
            text: '  /  ',
            style: SJText.overline(color: s.inkFaint),
          ),
          TextSpan(
            text: label,
            style: SJText.overline(color: accent),
          ),
        ],
      ),
    );
  }
}
