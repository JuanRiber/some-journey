/// # Ilustrações line-art — `SJIllustration`
///
/// PORQUÊ: o design doc pede estados vazio/erro/loading que ENSINAM o próximo
/// passo, nunca um "Nenhum resultado" seco. Para isso cada estado ganha uma arte
/// minimalista de traço fino (bússola, montanhas + trilha, lua + estrelas, nuvem
/// offline, bússola quebrada) — coerente com "papel quente" (claro) e "atlas
/// noturno" (escuro).
///
/// Decisões de fundo (o "porquê" que amarra tudo):
/// - **CustomPaint puro**: zero dependências novas, controle total do traço e
///   escala perfeita em qualquer tamanho (o doc pede ~120–160px).
/// - **Cor derivada do tema**: o traço estrutural usa `scheme.inkSoft` (calmo,
///   não compete com o texto), os destaques usam `scheme.accent` (couro/ouro —
///   o "selo" da marca) e os erros usam `scheme.danger`. Preenchimentos existem
///   só como véus suavíssimos do acento, nunca chapados — line-art é traço.
/// - **Traço proporcional**: a espessura acompanha o tamanho (`shortestSide/60`),
///   então a arte fica igualmente delicada a 120 ou a 160px.
/// - **Acessibilidade**: cada arte é embrulhada em `Semantics` com um rótulo em
///   português — o leitor de tela anuncia o ESTADO, não "imagem".
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'sj_theme.dart';
import 'tokens.dart';

/// Os estados que a arte cobre (herdados do doc §6). Um por situação real do app.
enum SJIllustrationKind {
  /// Onboarding / lista de jornadas vazia — montanhas + trilha sinuosa.
  firstJourney,

  /// Jornada sem memórias ainda — lua + estrelas (a noite à espera de histórias).
  noMemories,

  /// Sem conexão — nuvem cortada.
  offline,

  /// Falha (carregar/salvar) — bússola quebrada, agulha à deriva.
  error,

  /// Carregando — bússola cuja agulha oscila procurando o rumo.
  loading,

  /// Vazio genérico / busca sem retorno — bússola serena.
  empty,
}

/// Widget público: escolhe o `CustomPainter` certo para o `kind` e o embrulha
/// com tamanho fixo + `Semantics`. Único ponto de entrada da lane de ilustrações.
class SJIllustration extends StatelessWidget {
  const SJIllustration({super.key, required this.kind, this.size = 144});

  /// Qual estado ilustrar.
  final SJIllustrationKind kind;

  /// Lado do quadrado (a arte é sempre quadrada e centrada). Default 144 — o
  /// meio da faixa elegante (120–160) sugerida no doc.
  final double size;

  /// Rótulo para leitores de tela: descreve o ESTADO em linguagem humana.
  String get _semanticLabel => switch (kind) {
    SJIllustrationKind.firstJourney =>
      'Ilustração: montanhas e uma trilha — sua primeira jornada começa aqui.',
    SJIllustrationKind.noMemories =>
      'Ilustração: lua e estrelas — ainda sem memórias nesta jornada.',
    SJIllustrationKind.offline => 'Ilustração: sem conexão com a internet.',
    SJIllustrationKind.error => 'Ilustração: algo deu errado.',
    SJIllustrationKind.loading => 'Ilustração: carregando.',
    SJIllustrationKind.empty => 'Ilustração: nada por aqui ainda.',
  };

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);

    // O loading é o único com movimento (agulha que oscila), então tem widget
    // próprio com ticker. Os demais são pintura estática.
    final Widget art = switch (kind) {
      SJIllustrationKind.loading => _LoadingCompass(scheme: s, size: size),
      SJIllustrationKind.firstJourney => CustomPaint(
        size: Size.square(size),
        painter: _MountainsTrailPainter(s),
      ),
      SJIllustrationKind.noMemories => CustomPaint(
        size: Size.square(size),
        painter: _MoonStarsPainter(s),
      ),
      SJIllustrationKind.offline => CustomPaint(
        size: Size.square(size),
        painter: _OfflineCloudPainter(s),
      ),
      SJIllustrationKind.error => CustomPaint(
        size: Size.square(size),
        painter: _CompassPainter(s, broken: true),
      ),
      SJIllustrationKind.empty => CustomPaint(
        size: Size.square(size),
        painter: _CompassPainter(s, needleAngle: -math.pi / 9),
      ),
    };

    return Semantics(
      label: _semanticLabel,
      // `image` marca a natureza do nó para o leitor de tela; `container` isola
      // o rótulo (a arte não tem texto próprio que possa vazar).
      image: true,
      container: true,
      child: SizedBox.square(dimension: size, child: art),
    );
  }
}

// ---------------------------------------------------------------------------
// Ferramentas de traço compartilhadas
// ---------------------------------------------------------------------------

/// Espessura de traço proporcional ao tamanho — mantém a delicadeza constante
/// entre 120 e 160px. `shortestSide/60` dá ~2.4px a 144.
double _strokeWidth(Size size) => size.shortestSide / 60;

/// Fábrica de `Paint` de contorno com juntas arredondadas (traço "à mão", suave).
Paint _line(Color color, double width) => Paint()
  ..style = PaintingStyle.stroke
  ..color = color
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

/// Véu de preenchimento: o acento a alfa baixíssimo — dá "corpo" sem virar
/// mancha chapada (line-art continua sendo traço). Um pouco mais presente no
/// escuro, onde formas vazadas somem sobre o navy.
Paint _veil(SJScheme s) => Paint()
  ..style = PaintingStyle.fill
  ..color = s.accent.withValues(
    alpha: s.brightness == Brightness.dark ? 0.10 : 0.07,
  )
  ..isAntiAlias = true;

/// Percorre um `Path` desenhando tracejado — usado na trilha (linha "andada",
/// não sólida). Baseado nas métricas do próprio path (segue a curva fielmente).
void _drawDashed(
  Canvas canvas,
  Path path,
  Paint paint, {
  required double dash,
  required double gap,
}) {
  for (final metric in path.computeMetrics()) {
    double distance = 0;
    while (distance < metric.length) {
      final end = math.min(distance + dash, metric.length);
      canvas.drawPath(metric.extractPath(distance, end), paint);
      distance = end + gap;
    }
  }
}

/// Base dos painters: guarda o esquema e só repinta quando o tema muda (trocar
/// claro↔escuro). Painters com parâmetros próprios estendem e ampliam a checagem.
abstract class _SJArtPainter extends CustomPainter {
  const _SJArtPainter(this.scheme);

  final SJScheme scheme;

  @override
  bool shouldRepaint(covariant _SJArtPainter old) => old.scheme != scheme;
}

// ---------------------------------------------------------------------------
// Bússola (empty · error · base do loading)
// ---------------------------------------------------------------------------

/// Desenha uma bússola centrada. É o motivo-âncora da marca ("achar o rumo"):
/// - `needleAngle`: para onde a agulha aponta (0 = norte/topo, horário em rad).
/// - `broken`: modo erro — o anel abre uma fenda, a agulha pende torta e um
///   traço de rachadura em `danger` cruza o mostrador.
class _CompassPainter extends _SJArtPainter {
  const _CompassPainter(
    super.scheme, {
    this.needleAngle = 0,
    this.broken = false,
  });

  final double needleAngle;
  final bool broken;

  @override
  void paint(Canvas canvas, Size size) {
    final w = _strokeWidth(size);
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.40;

    final ring = _line(scheme.inkSoft, w);
    final tick = _line(scheme.inkSoft, w * 0.85);
    final needleStroke = _line(scheme.accent, w);
    final crackPaint = _line(scheme.danger, w);

    // Mostrador. Inteiro na bússola serena; com uma fenda no canto superior
    // direito quando quebrada (a falta de traço já "conta" o defeito).
    if (broken) {
      final rect = Rect.fromCircle(center: center, radius: r);
      // Arco que cobre o círculo MENOS uma fenda de ~35° no topo-direita.
      canvas.drawArc(
        rect,
        -math.pi / 3,
        math.pi * 2 - math.pi / 4.6,
        false,
        ring,
      );
    } else {
      canvas.drawCircle(center, r, ring);
    }

    // Marcas cardeais: quatro tracinhos curtos para dentro (N/E/S/O).
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final dir = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(
        center + dir * (r * 0.99),
        center + dir * (r * 0.82),
        tick,
      );
    }

    // Véu do mostrador (respiro interno suave).
    canvas.drawCircle(center, r * 0.80, _veil(scheme));

    // Agulha: losango cujo bojo fica no centro. Metade norte preenchida com o
    // acento (o "ponteiro"), metade sul só contornada.
    final a = needleAngle;
    final dir = Offset(math.sin(a), -math.cos(a));
    final perp = Offset(-dir.dy, dir.dx);
    final tipN = center + dir * (r * 0.66);
    final tipS = center - dir * (r * 0.66);
    final beam = r * 0.12;
    final left = center + perp * beam;
    final right = center - perp * beam;

    final north = Path()
      ..moveTo(tipN.dx, tipN.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    final south = Path()
      ..moveTo(tipS.dx, tipS.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    canvas.drawPath(
      north,
      Paint()
        ..style = PaintingStyle.fill
        ..color = scheme.accent.withValues(alpha: 0.85)
        ..isAntiAlias = true,
    );
    canvas.drawPath(north, needleStroke);
    canvas.drawPath(south, needleStroke);

    // Pino central.
    canvas.drawCircle(
      center,
      w * 0.9,
      Paint()
        ..style = PaintingStyle.fill
        ..color = scheme.inkSoft
        ..isAntiAlias = true,
    );

    // Rachadura do modo erro: uma linha em zigue-zague atravessando o mostrador.
    if (broken) {
      final crack = Path()
        ..moveTo(center.dx + r * 0.36, center.dy - r * 0.62)
        ..lineTo(center.dx + r * 0.10, center.dy - r * 0.14)
        ..lineTo(center.dx + r * 0.30, center.dy + r * 0.06)
        ..lineTo(center.dx + r * 0.06, center.dy + r * 0.52);
      canvas.drawPath(crack, crackPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) =>
      old.scheme != scheme ||
      old.needleAngle != needleAngle ||
      old.broken != broken;
}

/// Loading: a bússola com a agulha oscilando de leve, como quem "procura o
/// rumo". Movimento com propósito (doc §4) — nada de spinner genérico girando.
class _LoadingCompass extends StatefulWidget {
  const _LoadingCompass({required this.scheme, required this.size});

  final SJScheme scheme;
  final double size;

  @override
  State<_LoadingCompass> createState() => _LoadingCompassState();
}

class _LoadingCompassState extends State<_LoadingCompass>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _wobble;

  @override
  void initState() {
    super.initState();
    // Vai-e-volta lento e suave: a agulha varre um pequeno arco em torno do
    // norte, com desaceleração enfática nas pontas (sensação magnética).
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _wobble = Tween<double>(
      begin: -0.5,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _controller, curve: SJMotion.standard));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _wobble,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _CompassPainter(widget.scheme, needleAngle: _wobble.value),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Montanhas + trilha (firstJourney)
// ---------------------------------------------------------------------------

/// Duas cristas de montanha, um sol/lua discreto e uma trilha tracejada que
/// sobe serpenteando até o vale — a metáfora do começo da jornada.
class _MountainsTrailPainter extends _SJArtPainter {
  const _MountainsTrailPainter(super.scheme);

  @override
  void paint(Canvas canvas, Size size) {
    final w = _strokeWidth(size);
    final d = size.shortestSide;
    Offset p(double x, double y) => Offset(x * d, y * d);

    final ridge = _line(scheme.inkSoft, w);
    final accent = _line(scheme.accent, w);

    // Astro (sol de dia / lua de noite): um disco de acento no alto.
    canvas.drawCircle(
      p(0.74, 0.26),
      d * 0.075,
      Paint()
        ..style = PaintingStyle.fill
        ..color = scheme.accent.withValues(alpha: 0.85)
        ..isAntiAlias = true,
    );

    final horizon = 0.72;

    // Montanha de trás (mais alta, à direita) — véu suave para dar profundidade.
    final back = Path()
      ..moveTo(0.34 * d, horizon * d)
      ..lineTo(0.62 * d, 0.30 * d)
      ..lineTo(0.94 * d, horizon * d);
    canvas.drawPath(back, ridge);

    // Montanha da frente (à esquerda), com um pico nevado marcado por um "V".
    final front = Path()
      ..moveTo(0.06 * d, horizon * d)
      ..lineTo(0.36 * d, 0.42 * d)
      ..lineTo(0.66 * d, horizon * d)
      ..close();
    canvas.drawPath(front, _veil(scheme));
    canvas.drawPath(
      Path()
        ..moveTo(0.06 * d, horizon * d)
        ..lineTo(0.36 * d, 0.42 * d)
        ..lineTo(0.66 * d, horizon * d),
      ridge,
    );
    // Neve no cume (pequeno zigue-zague logo abaixo do pico).
    canvas.drawPath(
      Path()
        ..moveTo(0.28 * d, 0.50 * d)
        ..lineTo(0.32 * d, 0.47 * d)
        ..lineTo(0.36 * d, 0.50 * d)
        ..lineTo(0.40 * d, 0.47 * d)
        ..lineTo(0.44 * d, 0.50 * d),
      accent,
    );

    // Linha do horizonte discreta.
    canvas.drawLine(p(0.10, horizon), p(0.90, horizon), ridge);

    // Trilha sinuosa subindo até o vale — tracejada (o caminho ainda por andar).
    final trail = Path()
      ..moveTo(0.30 * d, 0.92 * d)
      ..cubicTo(0.46 * d, 0.86 * d, 0.34 * d, 0.80 * d, 0.50 * d, 0.76 * d)
      ..cubicTo(0.66 * d, 0.72 * d, 0.54 * d, 0.68 * d, 0.60 * d, 0.64 * d);
    _drawDashed(canvas, trail, accent, dash: d * 0.045, gap: d * 0.035);
  }
}

// ---------------------------------------------------------------------------
// Lua + estrelas (noMemories)
// ---------------------------------------------------------------------------

/// Uma lua crescente e algumas estrelas — a noite calma esperando as primeiras
/// histórias. Coerente com o "atlas noturno", mas legível também no papel quente.
class _MoonStarsPainter extends _SJArtPainter {
  const _MoonStarsPainter(super.scheme);

  @override
  void paint(Canvas canvas, Size size) {
    final w = _strokeWidth(size);
    final d = size.shortestSide;
    Offset p(double x, double y) => Offset(x * d, y * d);

    final stroke = _line(scheme.accent, w);

    // Crescente: círculo cheio MENOS um círculo deslocado (subtração de paths).
    final moonCenter = p(0.44, 0.46);
    final moonR = d * 0.22;
    final full = Path()
      ..addOval(Rect.fromCircle(center: moonCenter, radius: moonR));
    final bite = Path()
      ..addOval(
        Rect.fromCircle(
          center: moonCenter + Offset(d * 0.12, -d * 0.06),
          radius: moonR * 0.98,
        ),
      );
    final crescent = Path.combine(PathOperation.difference, full, bite);
    canvas.drawPath(crescent, _veil(scheme));
    canvas.drawPath(crescent, stroke);

    // Estrelas de quatro pontas, tamanhos variados, para dar ritmo ao céu.
    _star(canvas, p(0.74, 0.30), d * 0.055, stroke);
    _star(canvas, p(0.68, 0.62), d * 0.038, stroke);
    _star(canvas, p(0.30, 0.72), d * 0.030, stroke);

    // Poeira estelar: dois pontinhos preenchidos.
    final dot = Paint()
      ..style = PaintingStyle.fill
      ..color = scheme.accent.withValues(alpha: 0.7)
      ..isAntiAlias = true;
    canvas.drawCircle(p(0.82, 0.48), w * 0.8, dot);
    canvas.drawCircle(p(0.52, 0.24), w * 0.7, dot);
  }

  /// Estrela de 4 pontas: pontas externas em N/L/S/O, reentrâncias curtas nas
  /// diagonais (o "brilho" clássico, fininho e elegante).
  void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final inner = r * 0.32;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + inner, c.dy - inner)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx + inner, c.dy + inner)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - inner, c.dy + inner)
      ..lineTo(c.dx - r, c.dy)
      ..lineTo(c.dx - inner, c.dy - inner)
      ..close();
    canvas.drawPath(path, paint);
  }
}

// ---------------------------------------------------------------------------
// Nuvem offline (offline)
// ---------------------------------------------------------------------------

/// Uma nuvem cortada por um traço diagonal — "sem conexão". A silhueta vem da
/// união de alguns discos com uma base arredondada (contorno único e limpo).
class _OfflineCloudPainter extends _SJArtPainter {
  const _OfflineCloudPainter(super.scheme);

  @override
  void paint(Canvas canvas, Size size) {
    final w = _strokeWidth(size);
    final d = size.shortestSide;
    Offset p(double x, double y) => Offset(x * d, y * d);

    final stroke = _line(scheme.inkSoft, w);
    final slash = _line(scheme.danger, w);

    // Nuvem = união de três bolhas + uma base — depois contornamos o todo.
    Path circle(double x, double y, double r) =>
        Path()..addOval(Rect.fromCircle(center: p(x, y), radius: r * d));
    var cloud = circle(0.40, 0.52, 0.11);
    cloud = Path.combine(PathOperation.union, cloud, circle(0.56, 0.46, 0.14));
    cloud = Path.combine(PathOperation.union, cloud, circle(0.68, 0.54, 0.10));
    cloud = Path.combine(
      PathOperation.union,
      cloud,
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0.30 * d, 0.52 * d, 0.72 * d, 0.66 * d),
          Radius.circular(0.07 * d),
        ),
      ),
    );
    canvas.drawPath(cloud, _veil(scheme));
    canvas.drawPath(cloud, stroke);

    // Corte diagonal atravessando a nuvem: o sinal universal de "desligado".
    canvas.drawLine(p(0.30, 0.68), p(0.72, 0.40), slash);
  }
}
