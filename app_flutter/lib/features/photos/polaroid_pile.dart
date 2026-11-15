import 'dart:math' as math;

import 'package:flutter/material.dart' hide MemoryImage;

import '../../design/components.dart';
import '../../design/sj_theme.dart';
import '../../design/tokens.dart';
import '../../models.dart';
import '../../widgets/sj_image.dart';

/// # As fotos de uma memória, como polaroids sobre a mesa
///
/// **Por que existe:** no detalhe, cada foto ocupava a largura inteira, uma
/// embaixo da outra. Com duas ou três a página virava uma parede de imagens, e
/// o que vinha depois — o texto, a música — sumia lá embaixo: a seção da
/// música existia e ninguém a encontrava.
///
/// Agora elas são polaroids: pequenas, com a moldura de papel e a faixa larga
/// embaixo, cada uma um pouco torta, como fotos largadas numa mesa. Tocar numa
/// delas a faz CRESCER para a tela cheia (Hero), onde dá para ampliar com a
/// pinça e passar de uma para a outra — o zoom é o gesto, a pilha é o resumo.
///
/// A inclinação sai do id da foto, não de um sorteio: a mesma memória abre
/// sempre com as fotos na mesma posição, como uma mesa que ninguém mexeu.
class PolaroidPile extends StatelessWidget {
  const PolaroidPile({super.key, required this.images, required this.onOpen});

  final List<MemoryImage> images;

  /// Abre a foto de índice dado em tela cheia.
  final ValueChanged<int> onOpen;

  /// A moldura é PAPEL de fotografia, não tinta do tema: no atlas noturno ela
  /// continua clara, como uma polaroid de verdade numa mesa escura.
  static const Color papel = Color(0xFFFBF8F1);

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        // Uma foto só ganha mais espaço; a partir de duas, duas por linha.
        final sozinha = images.length == 1;
        final largura = sozinha
            ? math.min(240.0, c.maxWidth * 0.72)
            : math.min(168.0, (c.maxWidth - SJSpace.x4) / 2);
        return Padding(
          // Folga para as pontas inclinadas não encostarem no texto vizinho.
          padding: const EdgeInsets.symmetric(vertical: SJSpace.x3),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: SJSpace.x4,
            runSpacing: SJSpace.x5,
            children: [
              for (var i = 0; i < images.length; i++)
                _Polaroid(
                  key: ValueKey(images[i].id),
                  url: images[i].url,
                  largura: largura,
                  inclinacao: inclinacaoDe(images[i].id),
                  deslocamento: deslocamentoDe(images[i].id),
                  rotulo: 'Abrir foto ${i + 1} de ${images.length} em tela cheia',
                  onTap: () => onOpen(i),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Ângulo da polaroid, em radianos, entre −6° e +6°, e nunca reto demais
/// (|ângulo| ≥ 1,5°): uma foto perfeitamente alinhada no meio das tortas
/// parece erro, não estilo. Estável: sai do id, não de um sorteio.
@visibleForTesting
double inclinacaoDe(String id) {
  final h = _hash(id);
  final graus = 1.5 + (h % 46) / 10.0; // 1,5° a 6,0°
  final sinal = (h >> 7).isEven ? 1 : -1;
  return sinal * graus * math.pi / 180;
}

/// Um desalinhamento vertical pequeno (−6 a +6 pt), pelo mesmo motivo: fotos
/// largadas não caem todas na mesma linha.
@visibleForTesting
double deslocamentoDe(String id) => ((_hash(id) >> 3) % 13) - 6.0;

/// FNV-1a de 32 bits: o mesmo id dá o mesmo número em qualquer plataforma
/// (o `hashCode` de String do Dart não promete isso entre execuções).
int _hash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

class _Polaroid extends StatelessWidget {
  const _Polaroid({
    super.key,
    required this.url,
    required this.largura,
    required this.inclinacao,
    required this.deslocamento,
    required this.rotulo,
    required this.onTap,
  });

  final String url;
  final double largura;
  final double inclinacao;
  final double deslocamento;
  final String rotulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final claro = s.brightness == Brightness.light;
    final borda = largura * 0.055;
    return Transform.translate(
      offset: Offset(0, deslocamento),
      child: Transform.rotate(
        angle: inclinacao,
        child: SJPressable(
          onTap: onTap,
          semanticLabel: rotulo,
          pressedScale: 0.97,
          child: Container(
            width: largura,
            padding: EdgeInsets.fromLTRB(borda, borda, borda, borda * 4),
            decoration: BoxDecoration(
              color: PolaroidPile.papel,
              borderRadius: BorderRadius.circular(2),
              // No papel quente do modo claro, papel sobre papel quase some:
              // um fio e uma sombra mais firme dão a borda da foto. No atlas
              // noturno o contraste já vem do fundo.
              border: claro
                  ? Border.all(color: s.line, width: 0.8)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: s.shadow.withValues(alpha: claro ? 0.38 : 0.28),
                  blurRadius: claro ? 12 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: AspectRatio(
              aspectRatio: 1, // o quadrado clássico da polaroid
              child: Hero(
                tag: heroDaFoto(url),
                child: SJNetworkImage(
                  url,
                  fit: BoxFit.cover,
                  // A URL é assinada e expira: sem esta saída, uma foto que não
                  // carrega deixaria um buraco no meio da moldura.
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: const Color(0xFFE9E3D6),
                    child: Icon(Icons.photo_outlined,
                        size: largura * 0.22, color: const Color(0xFF9A8F7C)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
