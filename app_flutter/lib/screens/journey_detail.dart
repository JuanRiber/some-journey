import 'package:flutter/material.dart';

import '../api.dart';
import '../features/atlas/atlas_domain.dart';
import '../features/tracks/track_panel.dart';
import '../features/tracks/track_recorder.dart';
import '../models.dart';
import '../theme.dart';
import '../features/tracks/track_list.dart';
import '../widgets/atlas_map.dart';
import '../widgets/common.dart';

/// Detalhe e gestão de uma jornada: ciclo de vida (iniciar/pausar/retomar/
/// finalizar), pontos ordenados (reordenar/remover sem apagar a memória),
/// vincular um ponto solto e excluir a jornada.
class JourneyDetailScreen extends StatefulWidget {
  final String journeyId;
  const JourneyDetailScreen({super.key, required this.journeyId});

  @override
  State<JourneyDetailScreen> createState() => _JourneyDetailScreenState();
}

class _JourneyDetailScreenState extends State<JourneyDetailScreen> {
  JourneyDetail? _journey;
  String _error = '';
  bool _busy = false;

  /// Mapa da jornada (percurso real + distância). Carregado à parte do detalhe
  /// porque só ele conhece os trechos de GPS.
  JourneyMap? _map;

  /// Trechos gravados. Vêm da listagem, não do mapa: o mapa traz a geometria
  /// para desenhar, a listagem traz a identidade de cada trecho — que é o que
  /// permite remover um sem tocar nos outros.
  List<JourneyTrack> _tracks = const [];
  TrackRecorder? _recorder;
  bool _confirmDelete = false;
  List<JourneyPoint>? _loose; // pontos soltos para vincular (null = fechado)

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Busca o percurso real. Falha aqui NÃO derruba a tela: a jornada continua
  /// legível sem o traço de GPS.
  Future<void> _loadMap(String id) async {
    try {
      final m = await Api.instance.journeyMap(id);
      final t = await Api.instance.listTracks(id);
      if (mounted) {
        setState(() {
          _map = m;
          _tracks = t;
        });
      }
    } catch (_) {
      // sem percurso é um estado válido, não um erro
    }
  }

  /// Remove um trecho e recarrega o que depende dele.
  ///
  /// O traço some do mapa e a distância total encolhe; as memórias da jornada
  /// não são tocadas — o backend guarda percurso e memória em tabelas distintas
  /// justamente para que apagar um caminho não apague o que se viveu nele.
  /// Abre a edição e recarrega se algo mudou. A tela devolve `true` só quando
  /// gravou de fato — voltar sem mexer não custa uma requisição.
  Future<void> _openEdit(String id) async {
    final mudou =
        await Navigator.of(context).pushNamed('/journey-edit', arguments: id);
    if (!mounted || mudou != true) return;
    await _load();
  }

  Future<void> _deleteTrack(JourneyTrack t) async {
    try {
      await Api.instance.deleteTrack(t.journeyId, t.id);
      await _loadMap(t.journeyId);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      // Trecho que já não existe (toque duplo, lista desatualizada) não é falha:
      // o resultado que a pessoa queria já aconteceu. Só recarrega, em vez de
      // acusar um erro que ela não pode resolver.
      if (e.isNotFound) {
        await _loadMap(t.journeyId);
        return;
      }
      setState(() => _error = e.message);
    }
  }

  Future<void> _load() async {
    try {
      final data = await Api.instance.getJourney(widget.journeyId);
      // Pausar ou finalizar a jornada PARA a gravação. Antes, o painel apenas
      // sumia da tela e o gravador seguia vivo: GPS ligado e lotes subindo,
      // sem nenhum botão à vista para interromper.
      if (data.status != 'active' && (_recorder?.isRecording ?? false)) {
        await _recorder!.stop();
      }
      if (mounted) setState(() => _journey = data);
      await _loadMap(widget.journeyId);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() => _error = e.isNotFound ? 'Jornada não encontrada.' : e.message);
    }
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await fn();
      await _load();
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _recorder?.dispose();
    super.dispose();
  }

  Future<void> _openAdd() async {
    try {
      final map = await Api.instance.getMap();
      if (mounted) setState(() => _loose = map.loosePoints);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = _journey;
    return Scaffold(
      body: SafeArea(
        child: j == null
            ? (_error.isNotEmpty
                ? _errorView()
                : const Center(child: CircularProgressIndicator()))
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Text('← Voltar',
                        style: TextStyle(
                            color: SJColors.ink, fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(j.title, style: serif(27))),
                      const SizedBox(width: 10),
                      StatusBadge(j.status),
                      // Editar mora no cabeçalho, junto do que se edita. Antes,
                      // consertar um título só era possível apagando a jornada
                      // e refazendo — o que desfaz os vínculos com as memórias.
                      Semantics(
                        button: true,
                        label: 'Editar jornada',
                        child: IconButton(
                          onPressed: () => _openEdit(j.id),
                          icon: const Icon(Icons.edit_outlined,
                              size: 19, color: SJColors.inkSoft),
                          tooltip: 'Editar',
                        ),
                      ),
                    ],
                  ),
                  if ((j.description ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(j.description!,
                          style:
                              const TextStyle(color: SJColors.inkSoft, fontSize: 14, height: 1.5)),
                    ),
                  if ((j.mood ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(j.mood!,
                          style: serif(14.5, color: SJColors.bloom, style: FontStyle.italic)),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${j.pointsCount} ${j.pointsCount == 1 ? 'MEMÓRIA' : 'MEMÓRIAS'}${j.isPrivate ? '' : ' · PÚBLICA'}',
                      style: monoLabel(11),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _lifecycleActions(j),
                  InlineError(_error),
                  // Gravar percurso só faz sentido com a jornada em andamento:
                  // um capítulo encerrado não recebe caminho novo.
                  if (j.status == 'active') ...[
                    const SizedBox(height: 20),
                    TrackPanel(
                      recorder: _recorder ??= TrackRecorder(journeyId: j.id),
                      onFinished: () => _loadMap(j.id),
                    ),
                  ],
                  if (j.points.isNotEmpty || (_map?.hasRealTrack ?? false)) ...[
                    const SizedBox(height: 20),
                    AtlasMap(
                      data: MapResponse(loosePoints: const [], journeys: [
                        MapJourney(
                            id: j.id,
                            title: j.title,
                            status: j.status,
                            points: j.points,
                            route: j.route),
                      ]),
                      trackLines: _map?.trackLines,
                      onSelect: (id) => Navigator.of(context).pushNamed('/memory', arguments: id),
                      height: 300,
                    ),
                    if ((_map?.distanceMeters ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          '${AtlasDomain.formatDistance(_map!.distanceMeters)} percorridos',
                          style: monoLabel(11),
                        ),
                      ),
                  ],
                  // Fora do bloco do mapa de propósito: os trechos precisam ser
                  // vistos e removidos mesmo numa jornada encerrada, quando o
                  // painel de gravação já não aparece.
                  if (_tracks.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    TrackList(tracks: _tracks, onDelete: _deleteTrack),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(top: 26, bottom: 10),
                    child: Text('MEMÓRIAS (NA ORDEM DO RASTRO)', style: monoLabel(11)),
                  ),
                  if (j.points.isEmpty)
                    const Text(
                      'Esta jornada ainda está vazia. Adicione uma memória nova ou traga uma '
                      'memória que você já registrou para começar a construir este mapa.',
                      style: TextStyle(color: SJColors.inkSoft, fontSize: 14, height: 1.45),
                    )
                  else
                    ...List.generate(j.points.length, (i) => _pointRow(j, i)),
                  if (j.status != 'finished') ...[
                    const SizedBox(height: 22),
                    PrimaryButton(
                      label: '+ Nova memória nesta jornada',
                      onPressed: _busy
                          ? null
                          : () async {
                              await Navigator.of(context)
                                  .pushNamed('/memory-new', arguments: j.id);
                              _load();
                            },
                    ),
                    const SizedBox(height: 12),
                    if (_loose == null)
                      Center(
                        child: TextButton(
                          onPressed: _busy ? null : _openAdd,
                          child: const Text('Trazer uma memória que já existe',
                              style: TextStyle(
                                  color: SJColors.cyan,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ),
                      )
                    else
                      _looseBox(j),
                  ],
                  const SizedBox(height: 32),
                  _deleteSection(j),
                ],
              ),
      ),
    );
  }

  Widget _errorView() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Text('← Voltar',
                  style:
                      TextStyle(color: SJColors.ink, fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 40),
            Center(
                child:
                    Text(_error, style: const TextStyle(color: SJColors.danger, fontSize: 15))),
          ],
        ),
      );

  Widget _lifecycleActions(JourneyDetail j) {
    final buttons = <Widget>[];
    void add(String label, Future<Journey> Function(String) action, {bool outline = false}) {
      buttons.add(outline
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: SJColors.gold, width: 1.5),
                foregroundColor: SJColors.gold,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: TextStyle(
                    fontFamily: monoFamily,
                    fontFamilyFallback: monoFallback,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2),
              ),
              onPressed: _busy ? null : () => _run(() => action(j.id)),
              child: Text(label.toUpperCase()),
            )
          : ElevatedButton(
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11)),
              onPressed: _busy ? null : () => _run(() => action(j.id)),
              child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 12)),
            ));
    }

    switch (j.status) {
      case 'draft':
        add('Iniciar', Api.instance.startJourney);
      case 'active':
        add('Pausar', Api.instance.pauseJourney, outline: true);
        add('Finalizar', Api.instance.finishJourney);
      case 'paused':
        add('Retomar', Api.instance.resumeJourney);
        add('Finalizar', Api.instance.finishJourney, outline: true);
      case 'finished':
        return const Text('Jornada concluída.',
            style: TextStyle(
                color: SJColors.cyanDeep, fontSize: 14, fontWeight: FontWeight.w600));
    }
    return Wrap(spacing: 10, runSpacing: 10, children: buttons);
  }

  Widget _pointRow(JourneyDetail j, int i) {
    final p = j.points[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SJColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SJColors.line),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text('${p.position ?? i + 1}',
                  textAlign: TextAlign.center, style: serif(16, color: SJColors.cyan)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => Navigator.of(context).pushNamed('/memory', arguments: p.memoryId),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(16)),
                    const SizedBox(height: 2),
                    Text(
                      '${p.latitude.toStringAsFixed(3)}, ${p.longitude.toStringAsFixed(3)}',
                      style: const TextStyle(color: SJColors.inkSoft, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18, color: SJColors.cyan),
              onPressed: _busy || i == 0 ? null : () => _reorder(j, i, -1),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward, size: 18, color: SJColors.cyan),
              onPressed: _busy || i == j.points.length - 1 ? null : () => _reorder(j, i, 1),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: SJColors.danger),
              onPressed: _busy
                  ? null
                  : () => _run(() => Api.instance.unlinkJourneyPoint(j.id, p.memoryId)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reorder(JourneyDetail j, int index, int dir) {
    final ids = j.points.map((p) => p.memoryId).toList();
    final k = index + dir;
    final tmp = ids[index];
    ids[index] = ids[k];
    ids[k] = tmp;
    return _run(() => Api.instance.reorderJourneyPoints(j.id, ids));
  }

  Widget _looseBox(JourneyDetail j) {
    final loose = _loose!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1425B2C6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MEMÓRIAS SOLTAS', style: monoLabel(11)),
          const SizedBox(height: 10),
          if (loose.isEmpty)
            const Text('Nenhuma memória solta para trazer.',
                style: TextStyle(color: SJColors.inkSoft, fontSize: 14))
          else
            ...loose.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: SJColors.card, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(m.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(16)),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                    await Api.instance.addJourneyPoint(j.id, m.memoryId);
                                    setState(() => _loose = _loose!
                                        .where((x) => x.memoryId != m.memoryId)
                                        .toList());
                                  }),
                          child: const Text('+ Adicionar',
                              style: TextStyle(
                                  color: SJColors.gold,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                )),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _loose = null),
              child: const Text('Fechar',
                  style: TextStyle(color: SJColors.inkSoft, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deleteSection(JourneyDetail j) {
    if (!_confirmDelete) {
      return Center(
        child: TextButton(
          onPressed: () => setState(() => _confirmDelete = true),
          child: const Text('Excluir jornada',
              style: TextStyle(color: SJColors.danger, fontSize: 14)),
        ),
      );
    }
    return Column(
      children: [
        const Text('Excluir esta jornada? As memórias não são apagadas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SJColors.ink, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SJColors.danger,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11)),
              onPressed: _busy
                  ? null
                  : () async {
                      try {
                        await Api.instance.deleteJourney(j.id);
                        if (mounted) Navigator.of(context).pop();
                      } on ApiError catch (e) {
                        if (mounted) setState(() => _error = e.message);
                      }
                    },
              child: const Text('SIM, EXCLUIR', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 18),
            TextButton(
              onPressed: () => setState(() => _confirmDelete = false),
              child:
                  const Text('Cancelar', style: TextStyle(color: SJColors.inkSoft, fontSize: 14)),
            ),
          ],
        ),
      ],
    );
  }
}
