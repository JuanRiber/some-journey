/// Trechos de percurso gravados numa jornada — listar e remover.
///
/// Pausar e retomar a gravação gera vários trechos; juntos eles são UMA
/// experiência, e é assim que a lista os apresenta: partes de um caminho, não
/// arquivos soltos.
library;

import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/sj_theme.dart';
import '../../design/tokens.dart';
import '../../models.dart';
import '../atlas/atlas_domain.dart';

const _meses = [
  'JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN',
  'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ',
];

/// Momento do trecho no fuso de QUEM GRAVOU.
///
/// Diferente da data de uma memória, que a timeline formata em UTC porque lá o
/// canônico é o DIA. Um trecho é um instante do relógio de parede: mostrar
/// 18:57 em UTC viraria 21:57 para quem caminhou em Fortaleza.
String _momento(String iso) {
  final d = DateTime.parse(iso).toLocal();
  final dia = d.day.toString().padLeft(2, '0');
  final hora = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$dia ${_meses[d.month - 1]} · $hora:$min';
}

/// Quanto durou o trecho. Nulo enquanto ele estiver aberto.
String? _duracao(JourneyTrack t) {
  final fim = t.endedAt;
  if (fim == null) return null;
  final d = DateTime.parse(fim).difference(DateTime.parse(t.startedAt));
  if (d.inMinutes < 1) return 'menos de um minuto';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
}

class TrackList extends StatefulWidget {
  const TrackList({
    super.key,
    required this.tracks,
    required this.onDelete,
  });

  final List<JourneyTrack> tracks;

  /// Remove o trecho. A tela recarrega o mapa depois.
  final Future<void> Function(JourneyTrack) onDelete;

  @override
  State<TrackList> createState() => _TrackListState();
}

class _TrackListState extends State<TrackList> {
  /// Trecho aguardando confirmação. Um de cada vez: pedir confirmação de vários
  /// ao mesmo tempo convida ao engano.
  String? _confirmando;
  String? _removendo;

  @override
  Widget build(BuildContext context) {
    if (widget.tracks.isEmpty) return const SizedBox.shrink();
    final s = SJTheme.of(context);
    final total = widget.tracks.fold<double>(0, (n, t) => n + t.distanceMeters);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SJOverline(widget.tracks.length == 1
            ? 'trecho gravado'
            : '${widget.tracks.length} trechos gravados'),
        const SizedBox(height: SJSpace.x2),
        Text(
          _resumo(total),
          style: SJText.bodySm(color: s.inkSoft),
        ),
        const SizedBox(height: SJSpace.x4),
        for (final t in widget.tracks) _linha(s, t),
      ],
    );
  }

  /// A soma é a leitura que importa: os trechos são partes de um caminho só.
  String _resumo(double total) {
    if (widget.tracks.length == 1) {
      return 'Um caminho de ${AtlasDomain.formatDistance(total)}.';
    }
    return 'Somados, ${AtlasDomain.formatDistance(total)} de caminho — pausar e '
        'retomar divide a gravação, não a jornada.';
  }

  Widget _linha(SJScheme s, JourneyTrack t) {
    final confirmando = _confirmando == t.id;
    final removendo = _removendo == t.id;
    final duracao = _duracao(t);

    return Container(
      margin: const EdgeInsets.only(bottom: SJSpace.x3),
      padding: const EdgeInsets.all(SJSpace.x4),
      decoration: BoxDecoration(
        color: s.surfaceAlt,
        borderRadius: BorderRadius.circular(SJRadius.md),
        border: Border.all(color: confirmando ? s.danger : s.line),
      ),
      child: confirmando
          ? _confirmacao(s, t, removendo)
          : _resumoDoTrecho(s, t, duracao),
    );
  }

  Widget _resumoDoTrecho(SJScheme s, JourneyTrack t, String? duracao) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(_momento(t.startedAt), style: SJText.bodySm(color: s.ink)),
                    if (t.isActive) ...[
                      const SizedBox(width: SJSpace.x2),
                      const SJBadge('gravando'),
                    ],
                  ],
                ),
                const SizedBox(height: SJSpace.x1),
                Text(
                  [
                    AtlasDomain.formatDistance(t.distanceMeters),
                    t.pointCount == 1 ? '1 ponto' : '${t.pointCount} pontos',
                    ?duracao,
                  ].join(' · '),
                  style: SJText.caption(color: s.inkFaint),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _confirmando = t.id),
            icon: Icon(Icons.close, size: 18, color: s.inkFaint),
            tooltip: 'Remover trecho',
          ),
        ],
      );

  Widget _confirmacao(SJScheme s, JourneyTrack t, bool removendo) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Remover este trecho? O caminho gravado some do mapa. '
            'As memórias da jornada ficam.',
            style: SJText.bodySm(color: s.ink),
          ),
          const SizedBox(height: SJSpace.x3),
          Row(
            children: [
              SJButton(
                label: removendo ? 'Removendo…' : 'Remover',
                variant: SJButtonVariant.primary,
                onPressed: removendo
                    ? null
                    : () async {
                        setState(() => _removendo = t.id);
                        await widget.onDelete(t);
                        if (!mounted) return;
                        setState(() {
                          _removendo = null;
                          _confirmando = null;
                        });
                      },
              ),
              const SizedBox(width: SJSpace.x3),
              SJButton(
                label: 'Manter',
                variant: SJButtonVariant.text,
                onPressed: removendo
                    ? null
                    : () => setState(() => _confirmando = null),
              ),
            ],
          ),
        ],
      );
}
