import 'dart:math' as math;

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import '../sj_theme.dart';
import '../tokens.dart';
import 'type_styles.dart';

/// # Primitiva de toque — `SJPressable`
///
/// PORQUÊ: quase todo elemento tocável do sistema (botão, FAB, card, chip)
/// compartilha o MESMO vocabulário de feedback — encolhe de leve ao pressionar
/// (mola curta), dispara haptic opcional e anuncia-se como botão ao leitor de
/// tela. Concentrar isso aqui evita que cada componente reinvente (e diverja) o
/// gesto. NÃO usa `InkWell`/ripple do Material — o efeito é a escala suave,
/// coerente com o "app que respira".
class SJPressable extends StatefulWidget {
  const SJPressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
    this.haptic = true,
    this.semanticLabel,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Escala no estado pressionado (0.97 = 3% menor, sutil).
  final double pressedScale;

  /// Dispara `HapticFeedback.selectionClick` ao tocar (desligável).
  final bool haptic;

  /// Rótulo de acessibilidade; o nó vira `button` semântico.
  final String? semanticLabel;

  /// Quando falso (ou `onTap == null`), não reage a toques.
  final bool enabled;

  @override
  State<SJPressable> createState() => _SJPressableState();
}

class _SJPressableState extends State<SJPressable> {
  bool _down = false;

  bool get _active => widget.enabled && widget.onTap != null;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: _active,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _active ? (_) => _set(true) : null,
        onTapUp: _active ? (_) => _set(false) : null,
        onTapCancel: _active ? () => _set(false) : null,
        onTap: _active
            ? () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!.call();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? widget.pressedScale : 1.0,
          duration: SJMotion.fast,
          curve: SJMotion.standard,
          child: widget.child,
        ),
      ),
    );
  }
}

/// # Spinner minimalista — `SJSpinner`
///
/// PORQUÊ: um arco fino girando, sem o `CircularProgressIndicator` do Material
/// (que traz cor/espessura "genéricas"). Herda a cor de quem chama para ficar
/// legível sobre qualquer superfície (ex.: creme sobre o vinho do botão).
class SJSpinner extends StatefulWidget {
  const SJSpinner({super.key, this.size = 18, this.color, this.stroke = 2});

  final double size;
  final Color? color;
  final double stroke;

  @override
  State<SJSpinner> createState() => _SJSpinnerState();
}

class _SJSpinnerState extends State<SJSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? SJTheme.of(context).ink;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RotationTransition(
        turns: _c,
        child: CustomPaint(painter: _ArcPainter(color, widget.stroke)),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.color, this.stroke);
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    // ~270° de arco: comunica "girando" sem parecer um anel completo.
    canvas.drawArc(
      rect.deflate(stroke / 2),
      -math.pi / 2,
      math.pi * 1.5,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.color != color || old.stroke != stroke;
}

/// Variantes do botão. `primary` = ação preenchida (vinho); `secondary` =
/// tonal/contorno para ações de apoio; `text` = link discreto.
enum SJButtonVariant { primary, secondary, text }

/// # Botão — `SJButton`
///
/// PORQUÊ o label é mono/CAIXA ALTA nas variantes cheia e tonal: é o mesmo tom
/// "carimbo de passaporte" das overlines — dá autoridade à ação sem gritar. A
/// variante `text` foge disso (vira link em sans, cor de `secondary`) porque
/// link não é carimbo, é navegação.
///
/// Estados cobertos: repouso, pressionado (via `SJPressable`), desabilitado
/// (esmaece e ignora toque) e carregando (troca o label pelo `SJSpinner`,
/// mantendo a largura para o layout não "pular"). Toque ≥ 48pt de altura.
class SJButton extends StatelessWidget {
  const SJButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = SJButtonVariant.primary,
    this.loading = false,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final SJButtonVariant variant;

  /// Mostra spinner e bloqueia o toque (a ação já está em andamento).
  final bool loading;

  /// Ícone opcional à esquerda do label.
  final IconData? icon;

  /// Ocupa toda a largura disponível (útil em formulários/rodapés de sheet).
  final bool expand;

  static const double _minHeight = 48; // > 44pt de alvo de toque

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final disabled = onPressed == null || loading;

    // Papéis de cor por variante.
    late final Color bg;
    late final Color fg;
    late final Border? border;
    switch (variant) {
      case SJButtonVariant.primary:
        bg = s.primary;
        fg = s.onPrimary;
        border = null;
      case SJButtonVariant.secondary:
        // Tonal: leve véu do vinho + hairline; texto na cor de ação.
        bg = s.primary.withValues(alpha: 0.10);
        fg = s.primary;
        border = Border.all(color: s.line);
      case SJButtonVariant.text:
        bg = const Color(0x00000000);
        fg = s.secondary;
        border = null;
    }

    final isLink = variant == SJButtonVariant.text;
    final labelStyle = isLink
        ? SJText.body(color: fg, weight: FontWeight.w600)
        : SJText.button(color: fg);
    final text = isLink ? label : label.toUpperCase();

    Widget content = loading
        ? SJSpinner(size: 18, color: fg)
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: SJSpace.x2),
              ],
              Flexible(
                child: Text(
                  text,
                  style: labelStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    // Link é mais enxuto (sem preenchimento largo); os demais têm respiro.
    final padding = isLink
        ? const EdgeInsets.symmetric(
            horizontal: SJSpace.x2,
            vertical: SJSpace.x2,
          )
        : const EdgeInsets.symmetric(
            horizontal: SJSpace.x5,
            vertical: SJSpace.x3,
          );

    Widget box = AnimatedOpacity(
      opacity: disabled ? 0.45 : 1.0,
      duration: SJMotion.fast,
      child: Container(
        constraints: const BoxConstraints(minHeight: _minHeight),
        padding: padding,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: border,
          borderRadius: BorderRadius.circular(
            isLink ? SJRadius.sm : SJRadius.md,
          ),
        ),
        child: content,
      ),
    );

    if (expand) box = SizedBox(width: double.infinity, child: box);

    return SJPressable(
      onTap: disabled ? null : onPressed,
      enabled: !disabled,
      // Label sem CAIXA ALTA para o leitor de tela (mais natural que "gritado").
      semanticLabel: label,
      pressedScale: isLink ? 0.94 : 0.97,
      child: box,
    );
  }
}
