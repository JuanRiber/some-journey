import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../sj_theme.dart';
import '../tokens.dart';

/// # Carimbo — `SJSeal`
///
/// O selo de passaporte: ondas de cancelamento à esquerda, anel duplo com a
/// legenda em arco e a rosa dos ventos no meio.
///
/// PORQUÊ existe como componente e não como imagem: ele precisa trocar de cor
/// com o tema (couro no papel quente, ouro no atlas noturno) e viver em
/// tamanhos diferentes sem borrar — num cartão de login, na capa do livro, num
/// cabeçalho de perfil. Um PNG resolveria o primeiro uso e atrapalharia os
/// outros dois.
///
/// É DECORAÇÃO: nasce com opacidade baixa e `ExcludeSemantics`. Um carimbo que
/// disputa atenção com o formulário deixou de ser marca d'água.
class SJSeal extends StatelessWidget {
  const SJSeal({
    super.key,
    this.size = 120,
    this.legend = 'SOME JOURNEY',
    this.opacity = 0.42,
  });

  /// Diâmetro do selo redondo. A caixa é mais larga que alta para caber as
  /// ondas de cancelamento à esquerda, como num carimbo de correio.
  final double size;

  /// Texto em arco na parte de cima do anel. Vazio esconde a legenda.
  final String legend;

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: size * 1.7,
        height: size,
        child: CustomPaint(
          painter: _SealPainter(
            color: s.accent.withValues(alpha: opacity),
            legend: legend,
          ),
        ),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  const _SealPainter({required this.color, required this.legend});

  final Color color;
  final String legend;

  @override
  void paint(Canvas canvas, Size size) {
    final raio = size.height / 2 * 0.92;
    final centro = Offset(size.width - raio - 2, size.height / 2);

    final traco = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, raio * 0.022)
      ..color = color
      ..isAntiAlias = true;

    // Ondas de cancelamento, à esquerda do selo. São o que faz um círculo
    // carimbado parecer carimbado — sem elas é só um emblema.
    final faixa = centro.dx - raio;
    if (faixa > 24) {
      for (var i = 0; i < 3; i++) {
        final y = centro.dy + (i - 1) * raio * 0.34;
        final onda = Path()..moveTo(4, y);
        const passos = 28;
        for (var p = 1; p <= passos; p++) {
          final x = 4 + (faixa - 12) * p / passos;
          onda.lineTo(x, y + math.sin(p / passos * math.pi * 3) * raio * 0.07);
        }
        canvas.drawPath(onda, traco);
      }
    }

    // Anel duplo.
    canvas.drawCircle(centro, raio, traco);
    canvas.drawCircle(centro, raio * 0.74, traco);

    if (legend.isNotEmpty) _legendaEmArco(canvas, centro, raio * 0.86);

    // Rosa dos ventos — o mesmo motivo da capa do livro e das ilustrações:
    // cardeais inteiros, colaterais pela metade.
    final miolo = raio * 0.52;
    canvas.drawCircle(centro, miolo * 0.30, traco);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final comprimento = i.isEven ? miolo : miolo * 0.55;
      canvas.drawLine(
        centro,
        centro + Offset(math.sin(a), -math.cos(a)) * comprimento,
        traco,
      );
    }
  }

  /// Legenda letra a letra no arco de cima.
  ///
  /// Não existe "texto curvo" no Flutter: cada glifo é medido, o canvas gira o
  /// ângulo que aquela largura ocupa no raio, e o glifo é desenhado no topo.
  /// A conta é `ângulo = largura / raio` — espaçar por ângulo fixo faria o "I"
  /// e o "M" ficarem tortos entre si.
  void _legendaEmArco(Canvas canvas, Offset centro, double raio) {
    final estilo = TextStyle(
      fontFamily: SJType.mono,
      fontFamilyFallback: SJType.monoFallback,
      fontSize: math.max(6.0, raio * 0.17),
      letterSpacing: 0,
      color: color,
      fontWeight: FontWeight.w600,
    );

    final glifos = [
      for (final ch in legend.characters)
        TextPainter(
          text: TextSpan(text: ch, style: estilo),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    if (glifos.isEmpty) return;

    final folga = estilo.fontSize! * 0.42;
    final larguraTotal =
        glifos.fold<double>(0, (a, g) => a + g.width) + folga * (glifos.length - 1);
    var angulo = -(larguraTotal / raio) / 2;

    canvas.save();
    canvas.translate(centro.dx, centro.dy);
    for (final g in glifos) {
      final passo = g.width / raio;
      canvas.save();
      canvas.rotate(angulo + passo / 2);
      canvas.translate(0, -raio);
      g.paint(canvas, Offset(-g.width / 2, 0));
      canvas.restore();
      angulo += passo + folga / raio;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SealPainter old) =>
      old.color != color || old.legend != legend;
}
