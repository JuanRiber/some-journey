import 'package:flutter/material.dart';

import '../design/components.dart';
import '../design/tokens.dart';

/// # Visualizador de foto em TELA CHEIA.
///
/// **Por que existe:** a foto é a protagonista da memória. Numa lista ela vive
/// recortada; aqui ela ocupa tudo, sem moldura nem interface competindo — é o
/// momento em que a pessoa realmente OLHA a lembrança.
///
/// **O que o usuário sente:** imersão. Fundo quase preto (mesmo no modo papel: um
/// chão neutro faz a cor da foto valer), zoom por pinça, troca por deslize.
///
/// **Sem atrito:** abre no toque da própria foto, fecha por gesto (arrastar para
/// baixo) ou pelo × — nada de menu.
///
/// Abre com [showSJPhotoViewer]; o `initialIndex` casa com a foto tocada, então
/// a transição parece continuar a mesma imagem.
Future<void> showSJPhotoViewer(
  BuildContext context, {
  required List<String> urls,
  int initialIndex = 0,
}) {
  if (urls.isEmpty) return Future.value();
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: SJMotion.base,
      reverseTransitionDuration: SJMotion.fast,
      // Fade + leve escala: a foto "cresce" para a tela cheia em vez de aparecer
      // do nada (movimento que EXPLICA a transição, não enfeita).
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: SJMotion.enter);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (context, _, _) => _PhotoViewer(urls: urls, initialIndex: initialIndex),
    ),
  );
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.urls, required this.initialIndex});

  final List<String> urls;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  // Zoom ativo trava o deslize entre fotos (senão arrastar a foto ampliada
  // trocaria de página em vez de mover a imagem).
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.urls.length;
    return Scaffold(
      // Chão neutro escuro: é o que faz a fotografia valer, em qualquer tema.
      backgroundColor: const Color(0xF2100D0B),
      body: Stack(
        children: [
          // Arrastar para baixo fecha (gesto natural de galeria).
          GestureDetector(
            onVerticalDragEnd: (details) {
              if (!_zoomed && (details.primaryVelocity ?? 0) > 220) {
                Navigator.of(context).maybePop();
              }
            },
            child: PageView.builder(
              controller: _pages,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: total,
              itemBuilder: (context, i) => _Zoomable(
                url: widget.urls[i],
                onZoomChanged: (z) {
                  if (z != _zoomed) setState(() => _zoomed = z);
                },
              ),
            ),
          ),
          // Fechar: alvo de 44pt, com rótulo para leitores de tela.
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(SJSpace.x2),
                child: Semantics(
                  button: true,
                  label: 'Fechar foto',
                  child: IconButton(
                    iconSize: 26,
                    color: const Color(0xFFF7F1E7),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ),
          ),
          // Contador discreto ("2 / 5") — só quando há mais de uma foto.
          if (total > 1)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: SJSpace.x5),
                  child: Center(
                    child: Text(
                      '${_index + 1} / $total',
                      style: SJText.overline(color: const Color(0xCCF7F1E7)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Uma foto com zoom por pinça (e duplo toque). Informa ao pai quando está
/// ampliada, para o PageView não roubar o arraste.
class _Zoomable extends StatefulWidget {
  const _Zoomable({required this.url, required this.onZoomChanged});

  final String url;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_Zoomable> createState() => _ZoomableState();
}

class _ZoomableState extends State<_Zoomable> {
  final _controller = TransformationController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // Escala > 1.01 = ampliada (tolerância evita ruído de ponto flutuante).
      widget.onZoomChanged(_controller.value.getMaxScaleOnAxis() > 1.01);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Duplo toque alterna entre encaixado e 2,5× — atalho esperado numa galeria.
  void _toggleZoom() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.01;
    _controller.value = zoomed ? Matrix4.identity() : (Matrix4.identity()..scaleByDouble(2.5, 2.5, 2.5, 1));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            semanticLabel: 'Foto da memória em tela cheia',
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(child: SJSpinner(color: Color(0xFFF7F1E7))),
            errorBuilder: (context, _, _) => Center(
              child: Text(
                'Não foi possível carregar a foto.',
                style: SJText.bodySm(color: const Color(0xFFF7F1E7)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
