import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// O surgimento de um item que acabou de chegar: um fade com uma subida curta.
///
/// Uma vez só, ao montar, e só quando [ativo] — quem usa decide o que é "novo"
/// (a timeline guarda as memórias que já mostrou). Com "reduzir movimento"
/// ligado no aparelho, aparece direto, sem animação.
class SJSurge extends StatefulWidget {
  const SJSurge({super.key, required this.child, this.ativo = true});

  final Widget child;
  final bool ativo;

  @override
  State<SJSurge> createState() => _SJSurgeState();
}

class _SJSurgeState extends State<SJSurge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SJMotion.base,
  );
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: SJMotion.standard);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.value > 0) return;
    final semMovimento = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.ativo && !semMovimento) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _t,
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, 10 * (1 - _t.value)),
            child: child,
          ),
          child: widget.child,
        ),
      );
}
