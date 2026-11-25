/// As paradas do roteiro de uma jornada — as peças que DESENHAM.
///
/// Não decidem nada: recebem uma [JourneyStop] pronta (quem junta ponto e
/// memória é `itineraryStops`, no domínio) e os gestos como callbacks. A tela
/// da jornada só escolhe qual das duas formas mostrar — a parada para LER ou a
/// linha para ARRUMAR.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../design/components.dart';
import '../../design/sj_theme.dart';
import '../../design/tokens.dart';
import '../../widgets/sj_image.dart';
import '../places/place_domain.dart';
import 'journey_domain.dart';

/// Uma parada do roteiro, para ler. Na goteira, o número dela num pin igual ao
/// do mapa e o fio tracejado do rastro ligando à próxima; ao lado, a memória —
/// foto protagonista quando existe, nota tipográfica quando não.
class JourneyStopTile extends StatelessWidget {
  const JourneyStopTile({
    super.key,
    required this.stop,
    required this.first,
    required this.last,
    required this.onOpen,
  });

  final JourneyStop stop;

  /// Primeira e última parada: o fio vai de pin a pin, não nasce antes do
  /// primeiro nem sobra depois do último.
  final bool first;
  final bool last;

  /// Abrir a memória desta parada.
  final VoidCallback onOpen;

  /// Largura da goteira — o diâmetro do pin.
  static const double rail = 28;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    const centro = SJSpace.x4 + rail / 2;
    return Stack(
      children: [
        if (!(first && last))
          Positioned(
            left: (rail - 1) / 2,
            top: first ? centro : 0,
            bottom: last ? null : 0,
            height: last ? centro : null,
            child: CustomPaint(
              size: const Size(1, double.infinity),
              painter: _DashedRail(s.frame),
            ),
          ),
        Positioned(left: 0, top: SJSpace.x4, child: _pin(s)),
        Padding(
          padding: EdgeInsets.only(
            left: rail + SJSpace.x3,
            bottom: last ? 0 : SJSpace.x5,
          ),
          child: stop.hasPhoto ? _photo(s) : _note(s),
        ),
      ],
    );
  }

  /// O pin numerado: o mesmo disco vinho com anel de papel que marca a memória
  /// no mapa, agora dizendo qual é a parada.
  Widget _pin(SJScheme s) => ExcludeSemantics(
        child: Container(
          width: rail,
          height: rail,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: s.primary,
            shape: BoxShape.circle,
            border: Border.all(color: s.bg, width: 2),
          ),
          child: Text(
            '${stop.number}',
            style: SJText.overline(color: s.onPrimary, weight: FontWeight.w700)
                .copyWith(letterSpacing: 0),
          ),
        ),
      );

  Widget _photo(SJScheme s) => SJPhotoCard(
        title: stop.title,
        overline: stopDateLabel(stop.occurredAt),
        subtitle: placeLine(stop.placeLabel, stop.latitude, stop.longitude),
        aspectRatio: 3 / 2,
        onTap: onOpen,
        trailing: stop.photoCount > 1 ? _photoCount(stop.photoCount) : null,
        imageChild: SJNetworkImage(
          stop.photoUrl!,
          fit: BoxFit.cover,
          // A foto "revela" ao chegar (fade curto) em vez de estalar na tela.
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
              AnimatedOpacity(
            opacity: frame == null && !wasSynchronouslyLoaded ? 0 : 1,
            duration: SJMotion.base,
            curve: SJMotion.standard,
            child: child,
          ),
          errorBuilder: (context, _, _) => ColoredBox(
            color: s.surfaceAlt,
            child: Center(
              child: Text(
                'FOTO INDISPONÍVEL',
                style: SJText.overline(color: s.inkFaint),
              ),
            ),
          ),
        ),
      );

  /// O aviso de que a memória guarda mais fotos do que a parada mostra.
  Widget _photoCount(int n) => Semantics(
        label: '$n fotos',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SJSpace.x2,
            vertical: SJSpace.x1,
          ),
          decoration: BoxDecoration(
            color: SJOnPhoto.scrim,
            borderRadius: BorderRadius.circular(SJRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.photo_library_outlined,
                size: 13,
                color: SJOnPhoto.inkSoft,
              ),
              const SizedBox(width: SJSpace.x1),
              Text('$n', style: SJText.overline(color: SJOnPhoto.inkSoft)),
            ],
          ),
        ),
      );

  /// Parada sem foto: a palavra é a protagonista. Data, título, um gosto do
  /// texto e o lugar — a mesma anatomia da nota tipográfica da timeline.
  Widget _note(SJScheme s) {
    final data = stopDateLabel(stop.occurredAt);
    return SJCard(
      padding: const EdgeInsets.all(SJSpace.x5),
      onTap: onOpen,
      semanticLabel: stop.hasTitle ? '${stop.title}, $data' : data,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SJOverline(data),
          const SizedBox(height: SJSpace.x2),
          if (stop.hasTitle)
            Text(
              stop.title,
              style: SJText.h2(color: s.ink),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (stop.excerpt.isNotEmpty) ...[
            const SizedBox(height: SJSpace.x2),
            Text(
              stop.excerpt,
              style: SJText.bodySm(color: s.inkSoft),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: SJSpace.x3),
          Text(
            placeLine(stop.placeLabel, stop.latitude, stop.longitude),
            style: SJText.caption(color: s.inkFaint),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// A parada em modo de arrumação: uma linha, com subir, descer e tirar.
///
/// Sem título, a data entra no lugar — aqui a linha existe para ser ESCOLHIDA
/// entre outras, e uma linha anônima vira sorteio. Um gesto nulo desliga o
/// botão dele (a primeira não sobe, a última não desce, nada anda enquanto
/// outra ação está no ar).
class JourneyArrangeRow extends StatelessWidget {
  const JourneyArrangeRow({
    super.key,
    required this.stop,
    this.onUp,
    this.onDown,
    this.onRemove,
  });

  final JourneyStop stop;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  /// Tirar a memória DESTA jornada. A memória não é apagada.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final nome = stop.hasTitle ? stop.title : stopDateLabel(stop.occurredAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: SJSpace.x2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          SJSpace.x4,
          SJSpace.x2,
          SJSpace.x1,
          SJSpace.x2,
        ),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(SJRadius.md),
          border: Border.all(color: s.line),
        ),
        child: Row(
          children: [
            SizedBox(
              width: SJSpace.x6,
              child: Text(
                '${stop.number}',
                textAlign: TextAlign.center,
                style: SJText.title(color: s.secondary),
              ),
            ),
            const SizedBox(width: SJSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Duas linhas: os três controles levam um terço da largura
                  // de um celular, e com uma linha só o nome era cortado no
                  // meio — justo onde ele serve para escolher a memória.
                  Text(
                    nome,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SJText.title(color: s.ink),
                  ),
                  Text(
                    placeLine(stop.placeLabel, stop.latitude, stop.longitude),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SJText.caption(color: s.inkSoft),
                  ),
                ],
              ),
            ),
            SJIconButton(
              icon: Icons.arrow_upward,
              semanticLabel: 'Subir $nome',
              color: s.secondary,
              onTap: onUp,
            ),
            SJIconButton(
              icon: Icons.arrow_downward,
              semanticLabel: 'Descer $nome',
              color: s.secondary,
              onTap: onDown,
            ),
            SJIconButton(
              icon: Icons.close,
              semanticLabel: 'Tirar $nome desta jornada',
              color: s.danger,
              onTap: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// O fio do rastro entre duas paradas: tracejado, como a linha que o mapa
/// desenha para um caminho que foi lembrado, não medido.
class _DashedRail extends CustomPainter {
  const _DashedRail(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const dash = 5.0;
    const gap = 5.0;
    for (double y = 0; y < size.height; y += dash + gap) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, (y + dash).clamp(0, size.height)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRail old) => old.color != color;
}
