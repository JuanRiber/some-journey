import 'package:flutter/widgets.dart';

import '../sj_theme.dart';
import '../tokens.dart';
import 'buttons.dart' show SJPressable;

/// # Botão de ícone — `SJIconButton`
///
/// PORQUÊ existe: voltar, editar, subir e descer uma linha são ações que não
/// cabem num rótulo — e cada tela resolvia isso com o `IconButton` do Material,
/// que traz a própria tinta, o próprio realce de toque e pede um ancestral
/// Material. Este é o mesmo gesto dos outros componentes (`SJPressable`: encolhe
/// de leve, haptic), com alvo de 44pt.
///
/// Duas formas:
/// - **nu** (padrão): só o glifo, para linhas e barras sobre papel;
/// - **disco** ([disc]): um disco de papel com hairline e sombra `e1`, para
///   flutuar sobre foto ou mapa. O disco é opaco de propósito — sobre imagem
///   não se sabe que cor vem por baixo, e um ícone solto some na primeira foto
///   clara.
///
/// O [semanticLabel] é obrigatório: um ícone sozinho não diz nada ao leitor de
/// tela.
class SJIconButton extends StatelessWidget {
  const SJIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onTap,
    this.disc = false,
    this.color,
  });

  final IconData icon;
  final String semanticLabel;

  /// Nulo desliga o botão: ele esmaece e ignora o toque.
  final VoidCallback? onTap;

  /// Desenha o disco de papel por trás do glifo.
  final bool disc;

  /// Tinta do glifo. Padrão: `ink` no disco, `inkSoft` no nu.
  final Color? color;

  /// Lado do alvo de toque — o piso do design system.
  static const double target = 44;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final ativo = onTap != null;
    final glifo = Icon(
      icon,
      size: disc ? 20 : 18,
      color: color ?? (disc ? s.ink : s.inkSoft),
    );
    final corpo = disc
        ? Container(
            width: SJSpace.x10,
            height: SJSpace.x10,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: s.surface,
              shape: BoxShape.circle,
              border: Border.all(color: s.line),
              boxShadow: SJElevation.e1(s),
            ),
            child: glifo,
          )
        : glifo;

    return SJPressable(
      onTap: onTap,
      enabled: ativo,
      semanticLabel: semanticLabel,
      pressedScale: 0.9,
      child: AnimatedOpacity(
        opacity: ativo ? 1 : 0.35,
        duration: SJMotion.fast,
        child: SizedBox(
          width: target,
          height: target,
          child: Center(child: corpo),
        ),
      ),
    );
  }
}
