import 'package:flutter/material.dart';

import '../theme.dart';

/// Campo de data: abre o calendário nativo do Flutter. Valor "AAAA-MM-DD"
/// (mesmo formato do resto do app). `max` = hoje (não permite data futura).
class SJDateField extends StatelessWidget {
  final String value; // AAAA-MM-DD
  final void Function(String) onChange;

  const SJDateField({super.key, required this.value, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final initial = value.isEmpty ? now : DateTime.parse(value);
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(1900),
          lastDate: now,
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: SJColors.wine,
                onPrimary: SJColors.ink,
                surface: SJColors.card,
                onSurface: SJColors.ink,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) {
          onChange(picked.toIso8601String().substring(0, 10));
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          color: SJColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x29F3ECDC)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(value.isEmpty ? 'Escolher data' : value,
                style: TextStyle(
                    color: value.isEmpty ? SJColors.placeholder : SJColors.ink, fontSize: 15)),
            const Icon(Icons.calendar_today, size: 18, color: SJColors.inkSoft),
          ],
        ),
      ),
    );
  }
}
