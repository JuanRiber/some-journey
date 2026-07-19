import 'package:flutter/material.dart';

import '../theme.dart';

/// A arte de marca (o viajante de primeira classe) emoldurada em ouro.
class HeroArt extends StatelessWidget {
  const HeroArt({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 0),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: SJColors.frame,
              borderRadius: BorderRadius.circular(3),
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

/// Overline mono dourada ("E-MAIL", "TÍTULO"...).
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 7),
        child: Text(text.toUpperCase(), style: monoLabel(11)),
      );
}

/// Botão primário vinho com texto creme em mono caixa alta.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  const PrimaryButton({super.key, required this.label, this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: busy ? null : onPressed,
          child: Text(busy ? '...' : label.toUpperCase()),
        ),
      );
}

/// Mensagem de erro inline (vermelho suave, centrada).
class InlineError extends StatelessWidget {
  final String message;
  const InlineError(this.message, {super.key});

  @override
  Widget build(BuildContext context) => message.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SJColors.danger, fontSize: 13),
          ),
        );
}

/// Tile pontilhado do "+ foto" na galeria (mesmo look do app Expo).
class DottedTile extends StatelessWidget {
  final String label;
  const DottedTile({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: SJColors.card,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0x29F3ECDC)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('+',
                style: TextStyle(color: SJColors.cyan, fontSize: 24, fontWeight: FontWeight.w700)),
            Text(label,
                style: const TextStyle(
                    color: SJColors.cyan, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// Selo de status (texto creme sobre preenchimento escuro o bastante).
class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge(this.status, {super.key});

  static const _labels = {
    'draft': 'Rascunho',
    'active': 'Ativa',
    'paused': 'Pausada',
    'finished': 'Concluída',
  };
  static const _colors = {
    'draft': Color(0xFF4A5364),
    'active': SJColors.wine,
    'paused': Color(0xFF8A5A1E),
    'finished': SJColors.cyanDeep,
  };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: _colors[status] ?? SJColors.inkSoft,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          (_labels[status] ?? status).toUpperCase(),
          style: monoLabel(10, color: SJColors.ink, weight: FontWeight.w700),
        ),
      );
}
