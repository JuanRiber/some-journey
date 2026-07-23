import 'package:flutter/widgets.dart';

import '../sj_theme.dart';
import '../tokens.dart';
import 'buttons.dart' show SJPressable;
import 'overline.dart';
import 'type_styles.dart';

/// # Card = página de diário — `SJCard`
///
/// PORQUÊ: o card é a "folha" que levanta do papel — `surface` (um tom acima do
/// `bg`), raio `lg`, sombra `e1` (extremamente suave) e MUITO respiro interno.
/// É deliberadamente simples: só um recipiente com o padding e a elevação
/// certos. Se receber `onTap`, ganha o feedback de toque padrão (`SJPressable`).
class SJCard extends StatelessWidget {
  const SJCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SJSpace.x6),
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(SJRadius.lg),
        boxShadow: SJElevation.e1(s),
      ),
      child: child,
    );

    if (onTap == null) return box;
    return SJPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      pressedScale: 0.99, // card é grande: encolhe pouquíssimo
      child: box,
    );
  }
}

/// # Card foto-protagonista — `SJPhotoCard`
///
/// PORQUÊ: é a variante "a foto é a estrela" — a imagem sangra nas bordas
/// superiores (sem margem), um scrim (gradiente escuro sutil) desce sobre o pé
/// da foto para o texto sempre ficar legível, e o título em serifa vive SOBRE a
/// imagem. Texto só complementa. Um `overline` opcional (mono) rotula a foto
/// como "capítulo". Mantém raio `lg` e sombra `e1` como o card comum.
class SJPhotoCard extends StatelessWidget {
  const SJPhotoCard({
    super.key,
    required this.title,
    this.image,
    this.imageChild,
    this.overline,
    this.subtitle,
    this.aspectRatio = 3 / 4,
    this.onTap,
    this.trailing,
  });

  /// Título em serifa, sobreposto ao pé da imagem.
  final String title;

  /// Foto de fundo. Use `image` (ImageProvider) OU `imageChild` (ex.: um
  /// `Image.network` com loading próprio); `imageChild` tem prioridade.
  final ImageProvider? image;
  final Widget? imageChild;

  /// Overline mono opcional acima do título (ex.: "PORTUGAL · 2025").
  final String? overline;

  /// Linha de apoio abaixo do título (data, lugar). Discreta.
  final String? subtitle;

  /// Proporção da foto (default retrato 3:4, bom para viagem).
  final double aspectRatio;
  final VoidCallback? onTap;

  /// Selo/ação no canto superior direito (ex.: um `SJBadge`).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);

    // Fundo: o widget fornecido, ou a ImageProvider, ou um placeholder do frame.
    final Widget background =
        imageChild ??
        (image != null
            ? Image(image: image!, fit: BoxFit.cover)
            : DecoratedBox(decoration: BoxDecoration(color: s.frame)));

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(SJRadius.lg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: s.surface,
          boxShadow: SJElevation.e1(s),
        ),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              background,
              // Scrim: transparente no topo → escuro no pé, para o texto branco
              // "colar" sobre qualquer foto sem lavar as cores da imagem.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0xCC000000),
                    ],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
              ),
              if (trailing != null)
                Positioned(
                  top: SJSpace.x3,
                  right: SJSpace.x3,
                  child: trailing!,
                ),
              Positioned(
                left: SJSpace.x5,
                right: SJSpace.x5,
                bottom: SJSpace.x5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (overline != null) ...[
                      // Sobre foto, a overline fica em creme fixo (não no accent
                      // do tema) para legibilidade constante contra o scrim.
                      SJOverline(overline!, color: const Color(0xFFF3ECDC)),
                      const SizedBox(height: SJSpace.x2),
                    ],
                    Text(
                      title,
                      style: SJText.h2(color: const Color(0xFFFDFBF6)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: SJSpace.x1),
                      Text(
                        subtitle!,
                        style: SJText.bodySm(color: const Color(0xCCF3ECDC)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (onTap == null) return card;
    return SJPressable(
      onTap: onTap,
      semanticLabel: title,
      pressedScale: 0.99,
      child: card,
    );
  }
}
