/// Painel de gravação do percurso real — a única parte disto que é tela.
///
/// Escuta o [TrackRecorder] e desenha; não decide nada. Toda regra (o que vira
/// ponto, quando subir lote, o que fazer se a rede cair) vive no domínio e no
/// gravador, testados sem Flutter.
library;

import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/sj_theme.dart';
import '../../design/tokens.dart';
import '../atlas/atlas_domain.dart';
import 'track_domain.dart';
import 'track_recorder.dart';

class TrackPanel extends StatelessWidget {
  const TrackPanel({
    super.key,
    required this.recorder,
    required this.onFinished,
  });

  final TrackRecorder recorder;

  /// Chamado ao encerrar um trecho, para a tela recarregar o mapa.
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return AnimatedBuilder(
      animation: recorder,
      builder: (context, _) {
        final gravando = recorder.isRecording;
        return Container(
          padding: const EdgeInsets.all(SJSpace.x5),
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: BorderRadius.circular(SJRadius.lg),
            border: Border.all(color: gravando ? s.secondary : s.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SJOverline(gravando ? 'gravando o percurso' : 'percurso real'),
              const SizedBox(height: SJSpace.x2),
              Text(
                gravando
                    ? _linhaViva()
                    : 'Grave por onde você passou — o caminho de verdade, não '
                        'só a linha que liga as memórias.',
                style: SJText.bodySm(color: s.inkSoft),
              ),
              if (recorder.error.isNotEmpty) ...[
                const SizedBox(height: SJSpace.x3),
                Text(recorder.error, style: SJText.bodySm(color: s.danger)),
              ],
              if (gravando && _aviso() != null) ...[
                const SizedBox(height: SJSpace.x2),
                Text(_aviso()!, style: SJText.caption(color: s.accent)),
              ],
              const SizedBox(height: SJSpace.x4),
              SJButton(
                label: gravando ? 'Encerrar percurso' : 'Gravar percurso',
                variant:
                    gravando ? SJButtonVariant.secondary : SJButtonVariant.primary,
                onPressed: recorder.isBusy
                    ? null
                    : () async {
                        if (gravando) {
                          await recorder.stop();
                          onFinished();
                        } else {
                          await recorder.start();
                        }
                      },
              ),
            ],
          ),
        );
      },
    );
  }

  /// O número que importa enquanto grava: quanto já andou e quantos pontos.
  String _linhaViva() {
    final d = AtlasDomain.formatDistance(recorder.distanceMeters);
    final n = recorder.pointCount;
    final pendentes = recorder.pendingCount;
    final base = n == 1 ? '$d · 1 ponto' : '$d · $n pontos';
    return pendentes > 0 ? '$base · $pendentes a enviar' : base;
  }

  /// Explica o silêncio. Sem isto, sinal ruim parece app travado.
  String? _aviso() => switch (recorder.lastVerdict) {
        SampleVerdict.inaccurate => 'Sinal fraco — procurando posição melhor.',
        SampleVerdict.stationary => 'Parado. O percurso continua quando você andar.',
        _ => null,
      };
}
