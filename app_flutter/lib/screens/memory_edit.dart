import 'package:flutter/material.dart' hide MemoryImage;
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../features/photos/photo_picker.dart';
import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/date_field.dart';
import '../widgets/location_picker.dart';

/// Itálico serifado da linha de abertura — a mesma "voz de diário" da tela de
/// criar, para editar e criar soarem como a mesma página. Composto só a partir
/// dos tokens, nunca com tamanho escrito solto.
TextStyle _diarioItalico(SJScheme s) => TextStyle(
      fontFamily: SJType.serif,
      fontFamilyFallback: SJType.serifFallback,
      fontSize: SJType.bodySmSize,
      height: SJType.bodySmLine / SJType.bodySmSize,
      fontStyle: FontStyle.italic,
      color: s.inkSoft,
    );

/// Editar memória: espelha a tela de criar, mas pré-carrega pelo id e salva com
/// PATCH. 404/422 (inexistente, de outro dono ou UUID malformado) viram
/// "Memória não encontrada." (anti-enumeração).
class MemoryEditScreen extends StatefulWidget {
  final String memoryId;
  const MemoryEditScreen({super.key, required this.memoryId});

  @override
  State<MemoryEditScreen> createState() => _MemoryEditScreenState();
}

class _MemoryEditScreenState extends State<MemoryEditScreen> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  String _date = '';
  double? _lat;
  double? _lng;
  List<MemoryImage> _saved = [];
  final List<XFile> _picks = [];
  bool _loaded = false;
  String _loadError = '';
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await Api.instance.getMemory(widget.memoryId);
      if (!mounted) return;
      setState(() {
        _title.text = m.title;
        _text.text = m.text;
        _date = m.occurredAt.substring(0, 10);
        _lat = m.latitude;
        _lng = m.longitude;
        _saved = m.images;
        _loaded = true;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() => _loadError = e.isNotFound ? 'Memória não encontrada.' : e.message);
    }
  }

  Future<void> _removeSaved(String imageId) async {
    try {
      await Api.instance.deleteMemoryImage(widget.memoryId, imageId);
      setState(() => _saved = _saved.where((x) => x.id != imageId).toList());
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _pickPhotos() async {
    final total = _saved.length + _picks.length;
    final imgs = await SJPhoto.escolher(
      restantes: SJPhoto.maxPorMemoria - total,
    );
    if (imgs.isNotEmpty) setState(() => _picks.addAll(imgs));
  }

  Future<void> _onSave() async {
    setState(() => _error = '');
    if (_lat == null || _lng == null) {
      setState(() => _error = 'Escolha um local.');
      return;
    }
    setState(() => _saving = true);
    try {
      await Api.instance.updateMemory(widget.memoryId, {
        'title': _title.text.trim(),
        'text': _text.text.trim(),
        'latitude': _lat,
        'longitude': _lng,
        'occurred_at': '${_date}T12:00:00Z',
      });
      for (final p in _picks) {
        final bytes = await p.readAsBytes();
        await Api.instance
            .addMemoryImage(widget.memoryId, bytes, p.name, p.mimeType ?? 'image/jpeg');
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
        _error = e.isNotFound ? 'Memória não encontrada.' : e.message;
        _saving = false;
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
              Text('Editar memória', style: SJText.h1(color: s.ink)),
              const SizedBox(height: 6),
              Text('Ajuste o que precisar.', style: _diarioItalico(s)),
              if (_loadError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Text(_loadError,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: s.danger, fontSize: 15)),
                )
              else if (!_loaded)
                const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: Center(child: CircularProgressIndicator()))
              else ...[
                const FieldLabel('Título'),
                TextField(controller: _title, decoration: const InputDecoration()),
                const FieldLabel('O que aconteceu (opcional)'),
                TextField(
                  controller: _text,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: 'Conte a memória...'),
                ),
                // O SJDateField já desenha a própria overline ("QUANDO FOI").
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
                InlineError(_error),
                const SizedBox(height: 20),
                PrimaryButton(
                    label: _saving ? 'Salvando...' : 'Salvar alterações',
                    onPressed: _onSave,
                    busy: _saving),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoGrid(SJScheme s) {
    final total = _saved.length + _picks.length;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final img in _saved)
          _thumb(s, Image.network(img.url, width: 84, height: 84, fit: BoxFit.cover),
              onRemove: () => _removeSaved(img.id)),
        for (var i = 0; i < _picks.length; i++)
          _thumb(
            s,
            Image.network(_picks[i].path,
                width: 84,
                height: 84,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Container(width: 84, height: 84, color: s.surfaceAlt)),
            onRemove: () => setState(() => _picks.removeAt(i)),
          ),
        if (total < 5)
          GestureDetector(
            onTap: _pickPhotos,
            child: DottedTile(label: total == 0 ? 'Foto' : '${5 - total}'),
          ),
      ],
    );
  }

  Widget _thumb(SJScheme s, Widget image, {required VoidCallback onRemove}) => Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(4), child: image),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: s.danger, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('×',
                    style: TextStyle(
                        color: s.ink, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      );
}
