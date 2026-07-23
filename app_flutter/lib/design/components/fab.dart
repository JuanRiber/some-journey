import 'package:flutter/widgets.dart';

import '../sj_theme.dart';
import '../tokens.dart';
import 'buttons.dart' show SJPressable;

/// # FAB — `SJFab`
///
/// PORQUÊ: a ação flutuante primária (ex.: "nova memória") — círculo em
/// `primary`, ícone em `onPrimary`, sombra `e2` (flutua acima do conteúdo). O
/// toque já vem com haptic e feedback de escala do `SJPressable`. Diâmetro 56
/// (bem acima dos 44pt de alvo). O `semanticLabel` é OBRIGATÓRIO — um ícone
/// sozinho não diz nada ao leitor de tela.
class SJFab extends StatelessWidget {
  const SJFab({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.size = 56,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return SJPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      pressedScale: 0.92,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: s.primary,
          shape: BoxShape.circle,
          boxShadow: SJElevation.e2(s),
        ),
        child: Icon(icon, size: size * 0.42, color: s.onPrimary),
      ),
    );
  }
}
