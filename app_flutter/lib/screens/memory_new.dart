import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/date_field.dart';
import '../widgets/location_picker.dart';

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

  Future<void> _pickPhotos() async {
    final imgs = await ImagePicker().pickMultiImage(limit: 5 - _picks.length);
    if (imgs.isNotEmpty) setState(() => _picks.addAll(imgs.take(5 - _picks.length)));
  }

  Future<void> _onSave() async {
    setState(() => _error = '');
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Dê um título à memória.');
      return;
    }
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
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
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
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Text('← Voltar',
                    style: TextStyle(
                        color: SJColors.ink, fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 12),
              Text('Nova memória', style: serif(28)),
              const SizedBox(height: 6),
              Text('Um acontecimento, um lugar, um momento.',
                  style: serif(14.5, color: SJColors.inkSoft, style: FontStyle.italic)),
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
              const FieldLabel('Quando'),
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
              _photoGrid(),
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

  Widget _photoGrid() {
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
                        width: 84, height: 84, color: SJColors.sand)),
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
                        const BoxDecoration(color: SJColors.danger, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const Text('×',
                        style: TextStyle(
                            color: SJColors.ink, fontSize: 15, fontWeight: FontWeight.w700)),
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
