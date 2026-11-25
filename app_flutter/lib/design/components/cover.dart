import 'package:flutter/widgets.dart';

import '../sj_theme.dart';
import '../tokens.dart';
import 'overline.dart';
import 'seal.dart';
import 'type_styles.dart';

/// # Capa — `SJCover`
///
/// A abertura de um capítulo: a imagem SANGRA até as bordas, um véu desce sobre
/// o pé dela e o nome do capítulo é escrito por cima, na tinta de foto
/// ([SJOnPhoto]). É a mesma gramática da faixa do login na coluna única — a
/// foto em cima, o título sobre ela, o papel começando logo abaixo.
///
/// PORQUÊ é componente e não um trecho de tela: toda abertura (jornada hoje;
/// memória e fase quando chegarem) precisa da mesma altura de véu, da mesma
/// tinta e do mesmo recuo, ou cada uma escreve sobre foto do seu jeito.
///
/// **Sem imagem** ([image] nulo) a capa é de PAPEL: uma faixa no tom recuado
/// (`bgDeep`), o carimbo sangrando no canto e o título na tinta do tema.
/// Capítulo sem foto não é capítulo com defeito — é uma página que ainda não
/// ganhou gravura, e não pode parecer um retângulo cinza à espera de algo.
///
/// **A altura é um piso** ([minHeight]), não uma medida: um título de três
/// linhas faz a capa crescer em vez de ser cortado. Cortar o nome do capítulo
/// na página que existe para apresentá-lo seria o pior lugar para economizar.
class SJCover extends StatelessWidget {
  const SJCover({
    super.key,
    required this.title,
    this.image,
    this.overline,
    this.badge,
    this.minHeight = 320,
    this.topInset = 0,
    this.gutter = SJSpace.screenX,
    this.sealLegend = 'SOME JOURNEY',
  });

  /// O nome do capítulo, em serifa de abertura.
  final String title;

  /// A fotografia. Quem chama entrega o widget pronto (com o próprio
  /// carregamento, ou dentro de um `Hero`); nulo desenha a capa de papel.
  final Widget? image;

  /// Rótulo mono acima do título (o período, o lugar).
  final String? overline;

  /// Selo acima da overline (o estado do capítulo).
  final Widget? badge;

  /// Altura mínima. Com imagem, é quanto da tela a foto ocupa.
  final double minHeight;

  /// Espaço reservado no topo — a área segura e a fileira de botões que a tela
  /// põe por cima. O texto nunca sobe até lá.
  final double topInset;

  /// Recuo lateral do texto: a margem da página onde a capa está.
  final double gutter;

  /// Legenda em arco do carimbo, na capa de papel.
  final String sealLegend;

  /// Um título longo desce um degrau na escala: 34pt em quatro linhas vira um
  /// bloco que tapa a foto inteira.
  TextStyle _titleStyle(Color color) => title.length > 44
      ? SJText.h1(color: color)
      : SJText.display(color: color);

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final emFoto = image != null;

    final texto = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (badge != null) ...[
          badge!,
          const SizedBox(height: SJSpace.x3),
        ],
        if (overline != null) ...[
          SJOverline(overline!, color: emFoto ? SJOnPhoto.inkSoft : null),
          const SizedBox(height: SJSpace.x2),
        ],
        Semantics(
          header: true,
          child: Text(
            title,
            style: _titleStyle(emFoto ? SJOnPhoto.ink : s.ink),
          ),
        ),
      ],
    );

    final caixa = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      alignment: Alignment.bottomLeft,
      padding: EdgeInsets.fromLTRB(
        gutter,
        topInset + SJSpace.x8,
        gutter,
        SJSpace.x6,
      ),
      child: texto,
    );

    if (!emFoto) {
      return ClipRect(
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: s.bgDeep)),
            // Marca d'água: sangra para fora do canto, como no cartão do login.
            Positioned(
              top: topInset - SJSpace.x4,
              right: -SJSpace.x16,
              child: SJSeal(size: 176, legend: sealLegend, opacity: 0.3),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(height: 1, color: s.line),
            ),
            caixa,
          ],
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: image!),
        // O véu: nada no topo (a foto fica inteira), cheio no pé (onde se lê).
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0x00000000), SJOnPhoto.scrim],
                stops: [0.0, 0.38, 1.0],
              ),
            ),
          ),
        ),
        caixa,
      ],
    );
  }
}
