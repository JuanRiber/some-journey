import 'dart:math' as math;

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
/// `selected`, o tom fica CHEIO e o texto troca para a tinta que mais contrasta
/// com ele — o estado se lê pelo peso da pílula, não por um degrau de véu.
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

  /// Tinta que escreve SOBRE o tom cheio. O tom vem de fora (fase, acento do
  /// esquema) e muda de luminância com o modo: o vinho pede creme nos dois, o
  /// ouro do atlas noturno pede a tinta escura. Fica com a de maior contraste.
  static Color _sobre(Color tom, SJScheme s) {
    final escura = s.brightness == Brightness.dark ? s.bgDeep : s.ink;
    final lt = tom.computeLuminance();
    double razao(Color c) {
      final lc = c.computeLuminance();
      return (math.max(lt, lc) + 0.05) / (math.min(lt, lc) + 0.05);
    }

    return razao(s.onPrimary) >= razao(escura) ? s.onPrimary : escura;
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final accent = color ?? s.accent;

    // Repouso é um véu leve do tom (16%) com texto calmo. Selecionado é o tom
    // CHEIO: com véu nos dois estados, a diferença entre "este" e "os outros"
    // era de 8 pontos de opacidade — lia-se como a mesma pílula bege.
    final bg = selected ? accent : accent.withValues(alpha: 0.16);
    final fg = selected ? _sobre(accent, s) : s.inkSoft;

    final chip = AnimatedContainer(
      duration: SJMotion.base,
      curve: SJMotion.standard,
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
