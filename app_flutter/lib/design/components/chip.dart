import 'package:flutter/widgets.dart';

import '../sj_theme.dart';
import '../tokens.dart';
import 'buttons.dart' show SJPressable;
import 'type_styles.dart';

/// # Chip — `SJChip`
///
/// PORQUÊ: filtro/tag de baixo peso — fundo TONAL do acento (o acento a ~16% de
/// alpha, quase um "grifo" de aquarela) com label em sans, formato pílula. Não
/// é botão de ação (esse é o `SJButton`); é um marcador selecionável. Quando
/// `selected`, o preenchimento adensa e o texto vai para a cor cheia do acento,
/// deixando claro o estado sem depender só de cor de fundo.
class SJChip extends StatelessWidget {
  const SJChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;

  /// Acento base do chip (default = `scheme.accent`). Aceita moss/highlight/etc.
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final accent = color ?? s.accent;

    // Selecionado adensa o véu (24%) e escurece o texto; repouso é leve (16%).
    final bg = accent.withValues(alpha: selected ? 0.24 : 0.16);
    final fg = selected ? accent : s.inkSoft;

    final chip = Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(
        horizontal: SJSpace.x3,
        vertical: SJSpace.x1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SJRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: SJSpace.x1),
          ],
          Text(
            label,
            style: SJText.bodySm(color: fg, weight: FontWeight.w600),
          ),
        ],
      ),
    );

    if (onTap == null) return Semantics(label: label, child: chip);
    return SJPressable(
      onTap: onTap,
      semanticLabel: label,
      pressedScale: 0.95,
      child: chip,
    );
  }
}
