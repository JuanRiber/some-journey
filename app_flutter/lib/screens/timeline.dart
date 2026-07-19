import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';

const _meses = ['JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN', 'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ'];

/// occurred_at é canonicamente o DIA em UTC; formatamos pelas partes UTC para
/// a data não "vazar" para outro dia conforme o fuso do aparelho.
String _dayMonth(String iso) {
  final d = DateTime.parse(iso).toUtc();
  return '${d.day.toString().padLeft(2, '0')} ${_meses[d.month - 1]}';
}

int _yearOf(String iso) => DateTime.parse(iso).toUtc().year;

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<Memory>? _memories;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = '');
    try {
      final data = await Api.instance.listMemories();
      if (mounted) setState(() => _memories = data);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
        return;
      }
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      Text('Timeline', style: serif(32)),
      const SizedBox(height: 5),
      Text('As memórias do seu atlas em ordem viva.',
          style: serif(14.5, color: SJColors.inkSoft, style: FontStyle.italic)),
      const SizedBox(height: 12),
    ];

    if (_error.isNotEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: SJColors.danger)),
      ));
    } else if (_memories == null) {
      rows.add(const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(child: CircularProgressIndicator()),
      ));
    } else if (_memories!.isEmpty) {
      rows.addAll([
        const SizedBox(height: 44),
        Text('Seu atlas ainda não tem memórias.', style: serif(18), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('Toque no botão central para registrar a primeira.',
            textAlign: TextAlign.center, style: TextStyle(color: SJColors.inkSoft, fontSize: 14)),
      ]);
    } else {
      int? lastYear;
      var isFirstYear = true;
      for (final m in _memories!) {
        final year = _yearOf(m.occurredAt);
        if (year != lastYear) {
          rows.add(_yearHeader(year, note: isFirstYear ? 'atlas pessoal' : null));
          lastYear = year;
          isFirstYear = false;
        }
        rows.add(_entry(m));
      }
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: SJColors.cyan,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
          children: rows,
        ),
      ),
    );
  }

  Widget _yearHeader(int year, {String? note}) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 4, left: 28),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$year',
                style: TextStyle(
                  fontFamily: monoFamily,
                  fontFamilyFallback: monoFallback,
                  fontSize: 36,
                  letterSpacing: 2,
                  color: SJColors.gold,
                )),
            if (note != null) ...[
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(note, style: serif(14, color: SJColors.inkSoft, style: FontStyle.italic)),
              ),
            ],
          ],
        ),
      );

  Widget _entry(Memory m) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Trilho: espinha contínua + ponto vinho.
            SizedBox(
              width: 28,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned.fill(child: Center(child: Container(width: 2, color: const Color(0x29F3ECDC)))),
                  Padding(
                    padding: const EdgeInsets.only(top: 22),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(color: SJColors.wine, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 6),
                    child: Text(_dayMonth(m.occurredAt), style: monoLabel(11)),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pushNamed('/memory', arguments: m.id),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: SJColors.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: SJColors.line),
                      ),
                      child: Row(
                        children: [
                          _cover(m),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.title,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(16)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                            color: SJColors.wine, shape: BoxShape.circle)),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${m.latitude.toStringAsFixed(3)}, ${m.longitude.toStringAsFixed(3)}',
                                      style: const TextStyle(color: SJColors.inkSoft, fontSize: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                const Text('Abrir memória →',
                                    style: TextStyle(
                                        color: SJColors.cyan, fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  /// Capa: foto quando existe; senão o "livrinho" navy com lombada dourada.
  Widget _cover(Memory m) {
    const size = 54.0;
    if (m.imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.network(m.imageUrl!, width: size, height: size, fit: BoxFit.cover),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SJColors.card,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: SJColors.line),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: size * 0.5,
        height: size * 0.66,
        child: Stack(
          children: [
            Container(
              decoration:
                  BoxDecoration(color: SJColors.sand, borderRadius: BorderRadius.circular(2)),
            ),
            Positioned(
                left: 0, top: 0, bottom: 0, width: 5, child: Container(color: SJColors.goldDeep)),
            Positioned(
                top: -3,
                right: size * 0.5 * 0.22,
                child: Container(width: 6, height: 15, color: SJColors.wine)),
          ],
        ),
      ),
    );
  }
}
