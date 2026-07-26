import 'package:flutter/material.dart';

import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';

/// # Widgets compartilhados (ponte para o design system).
///
/// Estes nomes são usados por várias telas que ainda não foram reescritas uma a
/// uma. Em vez de duplicar estilo, cada um aqui DELEGA para o componente
/// equivalente de `lib/design/` e lê a paleta ativa via `SJTheme.of(context)`.
/// Assim as telas legadas ganham o sistema (e o modo escuro) sem alteração, e a
/// API pública destes widgets permanece intacta — nada quebra.
///
/// Para código NOVO: importe `design/components.dart` direto.

/// A arte de marca (o viajante de primeira classe) emoldurada em couro.
class HeroArt extends StatelessWidget {
  const HeroArt({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SJSpace.screenX,
            SJSpace.x6,
            SJSpace.screenX,
            0,
          ),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              // Moldura da paleta ativa (couro no papel, ouro na noite).
              color: s.frame,
              borderRadius: BorderRadius.circular(3),
              boxShadow: SJElevation.e1(s),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: AspectRatio(
                aspectRatio: 2.25,
                child: Image.asset(
                  'assets/images/first-class-art.jpg',
                  fit: BoxFit.cover,
                  semanticLabel:
                      'Ilustração: viajante lendo o atlas num vagão de primeira classe',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Overline mono do acento ("E-MAIL", "TÍTULO"...) — o mesmo rótulo dos campos
/// do sistema, para o formulário ter uma só voz.
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: SJSpace.x5, bottom: SJSpace.x2),
        child: Text(
          text.toUpperCase(),
          style: SJText.overline(color: SJTheme.of(context).accent),
        ),
      );
}

/// Botão primário do sistema, em largura cheia (mantém a API antiga `busy`).
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => SJButton(
        label: label,
        loading: busy,
        expand: true,
        onPressed: busy ? null : onPressed,
      );
}

/// Mensagem de erro inline (centrada, na cor de perigo da paleta ativa).
class InlineError extends StatelessWidget {
  final String message;
  const InlineError(this.message, {super.key});

  @override
  Widget build(BuildContext context) => message.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: SJSpace.x3),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: SJText.caption(color: SJTheme.of(context).danger),
          ),
        );
}

/// Tile "+ foto" da galeria: convite discreto, tracejado no hairline do tema.
class DottedTile extends StatelessWidget {
  final String label;
  const DottedTile({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        color: s.surfaceAlt,
        borderRadius: BorderRadius.circular(SJRadius.sm),
        border: Border.all(color: s.line),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add, size: 22, color: s.secondary),
          const SizedBox(height: SJSpace.x1),
          Text(label, style: SJText.caption(color: s.secondary)),
        ],
      ),
    );
  }
}

/// Selo de status da jornada — delega ao SJBadge, com a cor do papel semântico:
/// rascunho = tinta suave, ativa = ação (vinho), pausada = mostarda, concluída =
/// musgo (o capítulo virou parte permanente do atlas).
class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge(this.status, {super.key});

  static const _labels = {
    'draft': 'Rascunho',
    'active': 'Ativa',
    'paused': 'Pausada',
    'finished': 'Concluída',
  };

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final color = switch (status) {
      'active' => s.primary,
      'paused' => s.highlight,
      'finished' => s.moss,
      _ => s.inkSoft,
    };
    return SJBadge(_labels[status] ?? status, color: color);
  }
}
