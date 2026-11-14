/// Fotos da rede que não pesam: decodificadas no tamanho em que aparecem e
/// guardadas pelo CAMINHO, não pela URL.
///
/// Dois custos que o `Image.network` cobrava em silêncio:
///
/// 1. **A URL muda a cada resposta.** As fotos vêm assinadas: cada leitura da API
///    traz um token novo para o mesmo arquivo. O cache de imagens do Flutter usa
///    a URL inteira como chave — então cada recarga da timeline baixava e
///    decodificava de novo todas as fotos, que "piscavam" com o fade de chegada.
///    Aqui a chave é a URL sem a querystring: o mesmo arquivo é a mesma imagem,
///    seja qual for o token. (A carga em si usa a URL inteira, com o token.)
/// 2. **A foto era decodificada inteira.** Uma foto de 2048 px desenhada numa
///    miniatura de 84 px custava o mesmo que em tela cheia — em memória e em
///    tempo de decodificação, que é o que trava a rolagem. Aqui ela é
///    decodificada no tamanho do espaço que ocupa, vezes a densidade da tela.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A chave de cache de uma foto: a URL sem a querystring (onde mora o token).
@visibleForTesting
String chaveEstavel(String url) {
  final q = url.indexOf('?');
  return q < 0 ? url : url.substring(0, q);
}

/// Largura de decodificação para uma foto que ocupa [largura] × [altura]
/// pontos com o `fit` dado, numa tela de densidade [densidade].
///
/// Com `cover` o lado que manda depende da proporção da FOTO, que não se sabe
/// antes de baixar: uma foto deitada num quadro em pé é ampliada pela altura.
/// Por isso a conta usa o maior lado do quadro com folga de 1,6× — cobre fotos
/// até 16:10 sem perder nitidez e ainda decodifica uma fração da original.
/// Devolve null quando não há o que economizar (tamanho desconhecido).
@visibleForTesting
int? larguraDeDecodificacao({
  required double? largura,
  required double? altura,
  required BoxFit fit,
  required double densidade,
}) {
  final w = (largura != null && largura.isFinite) ? largura : null;
  final h = (altura != null && altura.isFinite) ? altura : null;
  if (w == null && h == null) return null;
  final lado = fit == BoxFit.cover
      ? math.max(w ?? 0, h ?? 0) * 1.6
      : (w ?? h!);
  if (lado <= 0) return null;
  return (lado * densidade).ceil();
}

/// O provedor de imagem com chave estável. Carrega pela URL completa (com o
/// token), mas é IGUAL a outro com o mesmo caminho — e é a igualdade que o
/// cache de imagens usa.
class StableNetworkImage extends ImageProvider<StableNetworkImage> {
  StableNetworkImage(this.url) : _rede = NetworkImage(url);

  final String url;
  final NetworkImage _rede;

  @override
  Future<StableNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<StableNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(StableNetworkImage key, ImageDecoderCallback decode) =>
      _rede.loadImage(_rede, decode);

  @override
  bool operator ==(Object other) =>
      other is StableNetworkImage && chaveEstavel(other.url) == chaveEstavel(url);

  @override
  int get hashCode => chaveEstavel(url).hashCode;

  @override
  String toString() => 'StableNetworkImage(${chaveEstavel(url)})';
}

/// O provedor para usar onde não há um widget `Image` — `DecorationImage` do
/// avatar, por exemplo. [lado] é o tamanho em pontos em que ela aparece.
ImageProvider sjFoto(BuildContext context, String url, {required double lado}) {
  final largura = larguraDeDecodificacao(
    largura: lado,
    altura: lado,
    fit: BoxFit.cover,
    densidade: MediaQuery.devicePixelRatioOf(context),
  );
  return ResizeImage.resizeIfNeeded(largura, null, StableNetworkImage(url));
}

/// `Image.network` com as duas economias acima. Mesmos parâmetros de
/// sempre; o tamanho de decodificação sai de [width]/[height] ou, sem eles, do
/// espaço que o layout der.
class SJNetworkImage extends StatelessWidget {
  const SJNetworkImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.frameBuilder,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final ImageFrameBuilder? frameBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final densidade = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final largura = larguraDeDecodificacao(
          largura: width ?? (c.hasBoundedWidth ? c.maxWidth : null),
          altura: height ?? (c.hasBoundedHeight ? c.maxHeight : null),
          fit: fit,
          densidade: densidade,
        );
        return Image(
          image: ResizeImage.resizeIfNeeded(largura, null, StableNetworkImage(url)),
          fit: fit,
          width: width,
          height: height,
          frameBuilder: frameBuilder,
          loadingBuilder: loadingBuilder,
          errorBuilder: errorBuilder,
          // Uma recarga que troca o token não troca a imagem: segue a mesma
          // na tela até a nova estar pronta, sem um quadro em branco no meio.
          gaplessPlayback: true,
        );
      },
    );
  }
}
