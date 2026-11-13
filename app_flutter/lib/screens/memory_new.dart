import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../features/photos/photo_picker.dart';
import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../features/phases/phase_domain.dart';
import '../features/phases/phase_store.dart';
import '../features/phases/phase_widgets.dart';
import '../widgets/common.dart';
import '../widgets/date_field.dart';
import '../widgets/location_picker.dart';

/// Itálico serifado da linha de abertura — a "voz de diário" que apresenta o
/// formulário. Composto só a partir dos tokens: tamanho e entrelinha saem da
/// escala, para uma mudança na escala não deixar esta tela para trás.
TextStyle _diarioItalico(SJScheme s) => TextStyle(
      fontFamily: SJType.serif,
      fontFamilyFallback: SJType.serifFallback,
      fontSize: SJType.bodySmSize,
      height: SJType.bodySmLine / SJType.bodySmSize,
      fontStyle: FontStyle.italic,
      color: s.inkSoft,
    );

/// Criar memória. `journeyId` opcional: quando presente, a memória já nasce
/// vinculada à jornada (modo jornada — o ponto entra em sequência no rastro).
class MemoryNewScreen extends StatefulWidget {
  final String? journeyId;
  const MemoryNewScreen({super.key, this.journeyId});

  @override
  State<MemoryNewScreen> createState() => _MemoryNewScreenState();
}

class _MemoryNewScreenState extends State<MemoryNewScreen> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  String _date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  double? _lat;
  double? _lng;
  final List<XFile> _picks = [];
  bool _loading = false;
  String _error = '';

  /// A fase escolhida para a memória; null é nenhuma (o normal).
  String? _phaseId;

  /// O seletor de fase só existe fora do modo jornada. Dentro dela a memória
  /// já entra na fase da jornada pela regra da lente, e perguntar de novo
  /// seria pedir uma decisão que já foi tomada — quem quiser uma fase própria
  /// para ela marca na edição.
  bool get _choosesPhase => widget.journeyId == null;

  @override
  void initState() {
    super.initState();
    if (_choosesPhase) PhaseStore.instance.refresh();
  }

  Future<void> _pickPhotos() async {
    final imgs = await SJPhoto.escolher(
      restantes: SJPhoto.maxPorMemoria - _picks.length,
    );
    if (imgs.isNotEmpty) setState(() => _picks.addAll(imgs));
  }

  Future<void> _onSave() async {
    setState(() => _error = '');
    if (_lat == null || _lng == null) {
      setState(() => _error = 'Escolha um local: busque ou toque no mapa.');
      return;
    }
    setState(() => _loading = true);
    final payload = {
      'title': _title.text.trim(),
      'text': _text.text.trim(),
      'latitude': _lat,
      'longitude': _lng,
      'occurred_at': '${_date}T12:00:00Z',
      if (_choosesPhase) 'life_phase_id': ?_phaseId,
    };
    try {
      String? memId;
      if (widget.journeyId != null) {
        final detail = await Api.instance.createMemoryInJourney(widget.journeyId!, payload);
        memId = detail.points.isNotEmpty ? detail.points.last.memoryId : null;
      } else {
        final mem = await Api.instance.createMemory(payload);
        memId = mem.id;
      }
      if (memId != null) {
        for (final p in _picks) {
          final bytes = await p.readAsBytes();
          await Api.instance
              .addMemoryImage(memId, bytes, p.name, p.mimeType ?? 'image/jpeg');
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Text('← Voltar',
                    style: TextStyle(
                        color: s.ink, fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 12),
              Text('Nova memória', style: SJText.h1(color: s.ink)),
              const SizedBox(height: 6),
              Text('Um acontecimento, um lugar, um momento.',
                  style: _diarioItalico(s)),
              const FieldLabel('Título'),
              TextField(
                controller: _title,
                decoration: const InputDecoration(hintText: 'Ex.: Fim de tarde em Jericoacoara'),
              ),
              const FieldLabel('O que aconteceu (opcional)'),
              TextField(
                controller: _text,
                maxLines: 5,
                decoration: const InputDecoration(hintText: 'Conte a memória...'),
              ),
              // O SJDateField já desenha a própria overline ("QUANDO FOI") —
              // não repetir um FieldLabel aqui.
              const SizedBox(height: 20),
              SJDateField(value: _date, onChange: (v) => setState(() => _date = v)),
              const FieldLabel('Localização'),
              LocationPicker(
                latitude: _lat,
                longitude: _lng,
                onChange: (lat, lng, _) => setState(() {
                  _lat = lat;
                  _lng = lng;
                }),
              ),
              const FieldLabel('Fotos (opcional, até 5)'),
              _photoGrid(s),
              if (_choosesPhase)
                ValueListenableBuilder<List<LifePhase>>(
                  valueListenable: PhaseStore.instance,
                  builder: (context, phases, _) => phases.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: PhasePicker(
                            phases: phases,
                            selected: _phaseId,
                            onChanged: (id) => setState(() => _phaseId = id),
                          ),
                        ),
                ),
              InlineError(_error),
              const SizedBox(height: 20),
              PrimaryButton(
                  label: _loading ? 'Salvando...' : 'Salvar memória',
                  onPressed: _onSave,
                  busy: _loading),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoGrid(SJScheme s) {
    final remaining = 5 - _picks.length;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < _picks.length; i++)
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(_picks[i].path,
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                        width: 84, height: 84, color: s.surfaceAlt)),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => setState(() => _picks.removeAt(i)),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration:
                        BoxDecoration(color: s.danger, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('×',
                        style: TextStyle(
                            color: s.ink, fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        if (remaining > 0)
          GestureDetector(
            onTap: _pickPhotos,
            child: DottedTile(label: _picks.isEmpty ? 'Foto' : '$remaining'),
          ),
      ],
    );
  }
}
