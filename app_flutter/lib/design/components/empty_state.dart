import 'package:flutter/widgets.dart';

import '../sj_theme.dart';
import '../tokens.dart';
import 'buttons.dart';
import 'type_styles.dart';

/// # Estado vazio — `SJEmptyState`
///
/// PORQUÊ (regra do design doc): NUNCA "Nenhum resultado". Todo estado vazio
/// ENSINA o próximo passo — ilustração line-art + título em serifa + um corpo
/// suave + UMA ação primária. A `illustration` é injetada (outro agente desenha
/// as ilustrações); aceitamos `Widget?` e reservamos o espaço mesmo sem ela.
/// Tudo centralizado, com muito respiro — o vazio deve parecer intencional e
/// convidativo, não um erro.
class SJEmptyState extends StatelessWidget {
  const SJEmptyState({
    super.key,
    required this.title,
    required this.body,
    this.illustration,
    this.actionLabel,
    this.onAction,
  });

  /// Slot de ilustração (line-art). Opcional enquanto a arte não existe.
  final Widget? illustration;

  /// Título em serifa (h1) — acolhedor, não técnico.
  final String title;

  /// Corpo suave que explica o próximo passo.
  final String body;

  /// Ação primária opcional (ex.: "Criar primeira jornada").
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(SJSpace.x8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (illustration != null) ...[
                illustration!,
                const SizedBox(height: SJSpace.x8),
              ],
              Text(
                title,
                style: SJText.h1(color: s.ink),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SJSpace.x3),
              Text(
                body,
                style: SJText.body(color: s.inkSoft),
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: SJSpace.x8),
                SJButton(label: actionLabel!, onPressed: onAction),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
