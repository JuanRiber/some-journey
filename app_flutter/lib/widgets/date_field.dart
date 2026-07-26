import 'package:flutter/material.dart';

import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';

const _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

/// Campo de data do sistema: abre o calendário nativo, mas VESTIDO com a paleta
/// ativa (antes ele forçava um `ColorScheme.dark` — um calendário escuro
/// aparecendo sobre o papel claro).
///
/// O valor trafega como "AAAA-MM-DD" (o formato do resto do app), mas o que a
/// pessoa LÊ é a data escrita ("14 de junho de 2025") — a memória tem data de
/// diário, não de banco de dados. `lastDate` = hoje: não se registra um momento
/// que ainda não aconteceu.
class SJDateField extends StatelessWidget {
  final String value; // AAAA-MM-DD
  final void Function(String) onChange;
  final String label;

  const SJDateField({
    super.key,
    required this.value,
    required this.onChange,
    this.label = 'Quando foi',
  });

  /// "2025-06-14" -> "14 de junho de 2025". Lê as PARTES da string (sem fuso),
  /// então a data mostrada é exatamente a escolhida.
  String get _pretty {
    if (value.isEmpty) return '';
    final parts = value.split('-');
    if (parts.length != 3) return value;
    final month = int.tryParse(parts[1]);
    if (month == null || month < 1 || month > 12) return value;
    final day = int.tryParse(parts[2]);
    if (day == null) return value;
    return '$day de ${_meses[month - 1]} de ${parts[0]}';
  }

  Future<void> _pick(BuildContext context, SJScheme s) async {
    final now = DateTime.now();
    final initial = value.isEmpty ? now : (DateTime.tryParse(value) ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Quando isso aconteceu?',
      // O calendário herda a paleta ATIVA (claro ou escuro), nunca uma fixa.
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme(
            brightness: s.brightness,
            primary: s.primary,
            onPrimary: s.onPrimary,
            secondary: s.secondary,
            onSecondary: s.onPrimary,
            surface: s.surface,
            onSurface: s.ink,
            error: s.danger,
            onError: s.onPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      onChange(picked.toIso8601String().substring(0, 10));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final empty = value.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mesma overline dos outros campos, para o formulário ter UMA voz.
        Text(label.toUpperCase(), style: SJText.overline(color: s.accent)),
        const SizedBox(height: SJSpace.x2),
        Semantics(
          button: true,
          label: empty ? 'Escolher data' : 'Data: $_pretty',
          child: InkWell(
            onTap: () => _pick(context, s),
            borderRadius: BorderRadius.circular(SJRadius.md),
            child: Container(
              // Altura confortável de toque (>=44pt) com o padding do sistema.
              padding: const EdgeInsets.symmetric(
                horizontal: SJSpace.x4,
                vertical: SJSpace.x4,
              ),
              decoration: BoxDecoration(
                color: s.surfaceAlt,
                borderRadius: BorderRadius.circular(SJRadius.md),
                border: Border.all(color: s.line),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      empty ? 'Escolher data' : _pretty,
                      style: SJText.body(color: empty ? s.inkFaint : s.ink),
                    ),
                  ),
                  Icon(Icons.calendar_today, size: 18, color: s.inkSoft),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
