import 'package:flutter/widgets.dart';

import '../sj_theme.dart';
import '../tokens.dart';
import 'type_styles.dart';

/// # Badge — `SJBadge`
///
/// PORQUÊ: selo de status de alto contraste (ex.: "ATIVA", "RASCUNHO") — fundo
/// CHEIO do acento + texto contrastante, mono CAIXA ALTA. Difere do `SJChip`
/// (que é tonal/selecionável): o badge grita um estado, não é tocável. A cor do
/// texto é escolhida por luminância do fundo, então qualquer acento (couro,
/// ouro, vinho, musgo) fica legível sem o chamador ter de calcular contraste.
class SJBadge extends StatelessWidget {
  const SJBadge(this.label, {super.key, this.color});

  final String label;

  /// Cor de preenchimento (default = `scheme.accent`).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final bg = color ?? s.accent;
    // Fundo claro pede tinta escura; fundo escuro pede tinta creme.
    final fg = bg.computeLuminance() > 0.45 ? s.ink : s.onPrimary;

    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SJSpace.x2,
          vertical: SJSpace.x1,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(SJRadius.sm),
        ),
        child: Text(
          label.toUpperCase(),
          style: SJText.overline(color: fg, weight: FontWeight.w700),
        ),
      ),
    );
  }
}
