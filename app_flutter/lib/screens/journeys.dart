import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

String _monthYear(String iso) {
  const meses = [
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
    'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
  ];
  final d = DateTime.parse(iso).toUtc();
  return '${meses[d.month - 1]} de ${d.year}';
}

String _periodLabel(Journey j) {
  if (j.startedAt != null && j.endedAt != null) {
    final a = _monthYear(j.startedAt!);
    final b = _monthYear(j.endedAt!);
    return a == b ? a : '$a — $b';
  }
  if (j.startedAt != null) return 'desde ${_monthYear(j.startedAt!)}';
  return _monthYear(j.createdAt);
}

/// Lista das jornadas do usuário — cada card é uma entrada de atlas.
class JourneysScreen extends StatefulWidget {
  const JourneysScreen({super.key});

  @override
  State<JourneysScreen> createState() => _JourneysScreenState();
}

class _JourneysScreenState extends State<JourneysScreen> {
  List<Journey>? _journeys;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = '');
    try {
      final data = await Api.instance.listJourneys();
      if (mounted) setState(() => _journeys = data);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
        return;
      }
      setState(() => _error = e.message);
    }
  }

  Future<void> _openNew() async {
    await Navigator.of(context).pushNamed('/journey-new');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: SJColors.cyan,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Text('← Voltar',
                    style: TextStyle(color: SJColors.ink, fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Jornadas', style: serif(32)),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                    onPressed: _openNew,
                    child: const Text('+ NOVA', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Capítulos da sua vida, reunidos em mapas vivos.',
                  style: serif(14.5, color: SJColors.inkSoft, style: FontStyle.italic)),
              const SizedBox(height: 20),
              if (_error.isNotEmpty)
                Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: SJColors.danger))
              else if (_journeys == null)
                const Padding(
                    padding: EdgeInsets.only(top: 48), child: Center(child: CircularProgressIndicator()))
              else if (_journeys!.isEmpty)
                Column(
                  children: [
                    const SizedBox(height: 40),
                    Text('Você ainda não criou nenhuma jornada.',
                        style: serif(20), textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    const Text(
                      'Uma jornada reúne memórias, lugares e momentos em um mapa vivo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: SJColors.inkSoft, fontSize: 14.5, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(label: 'Criar primeira jornada', onPressed: _openNew),
                  ],
                )
              else
                ..._journeys!.map(_card),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(Journey j) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).pushNamed('/journey', arguments: j.id);
            _load();
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: SJColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: SJColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _coverBand(j),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(j.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(21)),
                      if ((j.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(j.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(color: SJColors.inkSoft, fontSize: 13.5, height: 1.5)),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        '${j.pointsCount} ${j.pointsCount == 1 ? 'MEMÓRIA' : 'MEMÓRIAS'} · ${_periodLabel(j).toUpperCase()}',
                        style: monoLabel(11),
                      ),
                      if (j.mood != null || !j.isPrivate) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (j.mood != null) _chip(j.mood!, SJColors.chip, SJColors.cyan),
                            if (!j.isPrivate) _chip('pública', const Color(0x1F25B2C6), SJColors.cyan),
                          ],
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

  /// Faixa de capa: a foto da jornada quando existe; senão o campo noturno
  /// com gravuras douradas (arcos + trilha tracejada + pin).
  Widget _coverBand(Journey j) {
    final Widget content;
    if (j.coverImageUrl != null) {
      content = Image.network(j.coverImageUrl!, height: 86, width: double.infinity, fit: BoxFit.cover);
    } else {
      content = SizedBox(
        height: 86,
        child: Stack(
          children: [
            Positioned(top: -46, right: -30, child: _arc(120)),
            Positioned(top: -28, right: -12, child: _arc(84)),
            Positioned(top: -12, right: 4, child: _arc(52)),
            Positioned(
              bottom: 22,
              left: 168,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: SJColors.wine,
                  shape: BoxShape.circle,
                  border: Border.all(color: SJColors.wineDeep, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Stack(
      children: [
        Container(color: SJColors.sand, width: double.infinity, child: content),
        Positioned(top: 12, right: 12, child: StatusBadge(j.status)),
      ],
    );
  }

  Widget _arc(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x59E3B04B), width: 1.5),
        ),
      );

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w500)),
      );
}
