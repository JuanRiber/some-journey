import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../sj_theme.dart';

/// # Ramo — `SJSprig`
///
/// O raminho prensado no canto do papel: caule curvo, folhas aos pares e uma
/// na ponta. É o par do [SJSeal] — carimbo num canto, herbário no outro — e
/// junto com ele é o que faz uma superfície lisa parecer uma PÁGINA.
///
/// PORQUÊ desenhado e não uma imagem: pelos mesmos motivos do carimbo (troca
/// de cor com o tema, escala sem borrar) e por mais um — ele quase sempre
/// aparece pela metade, sangrando para fora do papel. Um PNG precisaria de uma
/// versão por recorte; um traço vetorial só precisa ser cortado pela moldura.
///
/// É DECORAÇÃO: opacidade baixa e `ExcludeSemantics`.
class SJSprig extends StatelessWidget {
  const SJSprig({
    super.key,
    this.size = 150,
    this.opacity = 0.28,
    this.flip = false,
  });

  /// Altura do ramo. A caixa é mais alta que larga, como um ramo de verdade.
  final double size;

  final double opacity;

  /// Espelha na horizontal — para o ramo "cair" do outro canto.
  final bool flip;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final ramo = SizedBox(
      width: size * 0.72,
      height: size,
      child: CustomPaint(
        painter: _SprigPainter(s.moss.withValues(alpha: opacity)),
      ),
    );
    return ExcludeSemantics(
      child: flip
          ? Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..scaleByDouble(-1, 1, 1, 1),
              child: ramo,
            )
          : ramo,
    );
  }
}

class _SprigPainter extends CustomPainter {
  const _SprigPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final traco = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.9, size.height * 0.008)
      ..strokeCap = StrokeCap.round
      ..color = color
      ..isAntiAlias = true;

    // Caule: uma curva só, da base ao topo, inclinada para dentro do canto.
    final base = Offset(size.width * 0.86, size.height);
    final topo = Offset(size.width * 0.22, size.height * 0.06);
    final caule = Path()
      ..moveTo(base.dx, base.dy)
      ..cubicTo(
        size.width * 0.80, size.height * 0.62,
        size.width * 0.52, size.height * 0.38,
        topo.dx, topo.dy,
      );
    canvas.drawPath(caule, traco);

    // As folhas nascem SOBRE a curva, não em posições inventadas: cada par sai
    // de um ponto real do caule, com a inclinação da tangente ali. É o que
    // evita a aparência de folhas coladas num arame.
    final metrica = caule.computeMetrics().first;
    const pares = 6;
    for (var i = 0; i < pares; i++) {
      // Começa depois da base (o cabo) e para antes da ponta (onde vai a
      // folha solitária).
      final t = 0.16 + (i / (pares - 1)) * 0.68;
      final tan = metrica.getTangentForOffset(metrica.length * t);
      if (tan == null) continue;
      final anguloCaule = math.atan2(tan.vector.dy, tan.vector.dx);
      // Folhas diminuem em direção à ponta — é o que dá a silhueta de ramo.
      final comprimento = size.height * (0.17 - i * 0.012);
      for (final lado in [-1.0, 1.0]) {
        _folha(
          canvas,
          traco,
          tan.position,
          anguloCaule + lado * 0.85,
          comprimento,
        );
      }
    }

    // A folha da ponta, no prolongamento do caule.
    final pontaTan = metrica.getTangentForOffset(metrica.length);
    if (pontaTan != null) {
      _folha(
        canvas,
        traco,
        pontaTan.position,
        math.atan2(pontaTan.vector.dy, pontaTan.vector.dx),
        size.height * 0.13,
      );
    }
  }

  /// Uma folha: duas curvas espelhadas saindo do mesmo ponto e se encontrando
  /// na ponta — a forma de lente, que é o que o olho lê como "folha" com duas
  /// linhas só.
  void _folha(Canvas canvas, Paint traco, Offset raiz, double angulo, double comprimento) {
    final ponta = raiz + Offset(math.cos(angulo), math.sin(angulo)) * comprimento;
    final meio = Offset.lerp(raiz, ponta, 0.5)!;
    final normal = Offset(-math.sin(angulo), math.cos(angulo)) * (comprimento * 0.30);

    final folha = Path()
      ..moveTo(raiz.dx, raiz.dy)
      ..quadraticBezierTo(
        meio.dx + normal.dx, meio.dy + normal.dy,
        ponta.dx, ponta.dy,
      )
      ..quadraticBezierTo(
        meio.dx - normal.dx, meio.dy - normal.dy,
        raiz.dx, raiz.dy,
      );
    canvas.drawPath(folha, traco);
  }

  @override
  bool shouldRepaint(covariant _SprigPainter old) => old.color != color;
}
