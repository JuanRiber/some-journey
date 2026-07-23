import 'package:flutter/material.dart' show showModalBottomSheet;
import 'package:flutter/widgets.dart';

import '../sj_theme.dart';
import '../tokens.dart';

/// # Bottom sheet — `showSJSheet`
///
/// Anatomia (do design doc): superfície `surface`, topo com raio `xl`, um
/// "grabber" (pega) centralizado, sombra `e2`, ciente da safe-area.
///
/// PORQUÊ envolvemos o conteúdo em `SJTheme(scheme:)`: o sheet é empurrado numa
/// rota nova (fora da subárvore que tinha o tema), então o esquema ativo se
/// perderia. Recebemos o `scheme` de quem chama e reprovemos por dentro, para o
/// conteúdo continuar pintando no modo certo. Usamos `showModalBottomSheet`
/// apenas pela mecânica (barreira + arrastar-para-fechar); o visual é todo nosso
/// (fundo transparente, caixa desenhada à mão).
Future<T?> showSJSheet<T>(
  BuildContext context, {
  required Widget child,
  bool isScrollControlled = true,
  bool dismissible = true,
}) {
  final scheme = SJTheme.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: const Color(0x00000000),
    elevation: 0,
    barrierColor: scheme.shadow.withValues(alpha: 0.45),
    builder: (_) => SJTheme(
      scheme: scheme,
      child: _SJSheetContainer(child: child),
    ),
  );
}

/// A caixa visual do sheet: raio superior `xl`, grabber e respiro + safe-area.
class _SJSheetContainer extends StatelessWidget {
  const _SJSheetContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SJRadius.xl),
        ),
        boxShadow: SJElevation.e2(s),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SJSpace.x6,
            SJSpace.x3,
            SJSpace.x6,
            SJSpace.x6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grabber: pega curta e esmaecida, só afordância de arraste.
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: SJSpace.x5),
                decoration: BoxDecoration(
                  color: s.inkFaint.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(SJRadius.pill),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
