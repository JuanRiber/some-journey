import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../models.dart';
import '../features/music/memory_music_section.dart';
import '../features/phases/phase_widgets.dart';
import '../widgets/photo_viewer.dart';

const _mesesLong = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
];

String _formatFull(String iso) {
  final d = DateTime.parse(iso).toUtc();
  return '${d.day.toString().padLeft(2, '0')} de ${_mesesLong[d.month - 1]} de ${d.year}';
}

/// Itálico serifado da frase afetiva do rodapé — a "voz de diário" da tela.
///
/// Composto só a partir dos tokens (família serifada + escala de corpo): o
/// tamanho não pode ser escrito solto aqui, senão a próxima mudança de escala
/// passaria por esta tela sem avisar. A cor é o acento, que é o papel que a
/// paleta reserva ao caderno (couro no papel quente, ouro no atlas noturno).
TextStyle _diarioItalico(SJScheme s) => TextStyle(
      fontFamily: SJType.serif,
      fontFamilyFallback: SJType.serifFallback,
      fontSize: SJType.bodySize,
      height: SJType.bodyLine / SJType.bodySize,
      fontStyle: FontStyle.italic,
      color: s.accent,
    );

/// Detalhe de uma memória. Segurança (espelha o app Expo): id de outro usuário,
/// inexistente ou apagado vira 404; UUID malformado vira 422 — ambos aparecem
/// como "Memória não encontrada." (anti-enumeração).
class MemoryDetailScreen extends StatefulWidget {
  final String memoryId;
  const MemoryDetailScreen({super.key, required this.memoryId});

  @override
  State<MemoryDetailScreen> createState() => _MemoryDetailScreenState();
}

class _MemoryDetailScreenState extends State<MemoryDetailScreen> {
  Memory? _memory;
  String _error = '';
  bool _confirmDelete = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await Api.instance.getMemory(widget.memoryId);
      if (mounted) setState(() => _memory = m);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() => _error = e.isNotFound ? 'Memória não encontrada.' : e.message);
    }
  }

  Future<void> _onDelete() async {
    setState(() => _deleting = true);
    try {
      await Api.instance.deleteMemory(widget.memoryId);
      if (mounted) Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() {
        _error = e.message;
        _deleting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _memory;
    final s = SJTheme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _backButton(s),
              ),
            ),
            Expanded(
              child: _error.isNotEmpty
                  ? Center(
                      child: Text(_error,
                          style: TextStyle(color: s.danger, fontSize: 15)))
                  : m == null
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(28, 8, 28, 48),
                          children: [
                            if (m.hasTitle) ...[
                              Text(m.title, style: SJText.h1(color: s.ink)),
                              const SizedBox(height: 8),
                            ],
                            Row(
                              children: [
                                Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                        color: s.primary, shape: BoxShape.circle)),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    '${m.latitude.toStringAsFixed(3)}, ${m.longitude.toStringAsFixed(3)} • ${_formatFull(m.occurredAt)}',
                                    style: SJText.overline(color: s.accent),
                                  ),
                                ),
                              ],
                            ),
                            // A marca PRÓPRIA da memória. A fase herdada da
                            // jornada não aparece aqui: ela vale para a lente,
                            // mas a memória não foi marcada nela.
                            if (m.lifePhaseId != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: PhaseTag(phaseId: m.lifePhaseId),
                                ),
                              ),
                            // A foto é a protagonista: tocar abre em TELA CHEIA
                            // (zoom por pinça, deslize entre as fotos da memória).
                            for (final entry in m.images.asMap().entries)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Semantics(
                                  button: true,
                                  label: 'Abrir foto ${entry.key + 1} em tela cheia',
                                  child: GestureDetector(
                                    onTap: () => showSJPhotoViewer(
                                      context,
                                      urls: [for (final i in m.images) i.url],
                                      initialIndex: entry.key,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: Container(
                                        decoration: BoxDecoration(
                                            border: Border.all(
                                                color: s.frame, width: 3)),
                                        child: AspectRatio(
                                          aspectRatio: 4 / 3,
                                          child: Image.network(entry.value.url,
                                              fit: BoxFit.cover),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (m.text.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 18),
                                child: Text(m.text,
                                    style: TextStyle(
                                        color: s.ink, fontSize: 16, height: 1.55)),
                              ),
                            // A trilha vem DEPOIS do texto e das fotos: a
                            // música acompanha a lembrança, não a anuncia.
                            Padding(
                              padding: const EdgeInsets.only(top: 28),
                              child: Divider(color: s.line, height: 1),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 22),
                              child: MemoryMusicSection(
                                memoryId: m.id,
                                tracks: m.music,
                                onChanged: (atualizada) =>
                                    setState(() => _memory = atualizada),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 28),
                              child: Divider(color: s.line, height: 1),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: Text('“A vida deixa rastros.”',
                                  textAlign: TextAlign.center,
                                  style: _diarioItalico(s)),
                            ),
                            const SizedBox(height: 30),
                            if (_confirmDelete)
                              Column(
                                children: [
                                  Text('Apagar esta memória?',
                                      style: TextStyle(
                                          color: s.ink,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 14),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: s.danger,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 22, vertical: 11)),
                                        onPressed: _deleting ? null : _onDelete,
                                        child: Text(_deleting ? 'APAGANDO...' : 'SIM, APAGAR',
                                            style: const TextStyle(fontSize: 12)),
                                      ),
                                      const SizedBox(width: 18),
                                      TextButton(
                                        onPressed: _deleting
                                            ? null
                                            : () => setState(() => _confirmDelete = false),
                                        child: Text('Cancelar',
                                            style: TextStyle(
                                                color: s.inkSoft, fontSize: 14)),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            else ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 13)),
                                  onPressed: () async {
                                    await Navigator.of(context)
                                        .pushNamed('/memory-edit', arguments: m.id);
                                    _load();
                                  },
                                  child: const Text('EDITAR MEMÓRIA'),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Center(
                                child: TextButton(
                                  onPressed: () => setState(() => _confirmDelete = true),
                                  child: Text('Apagar memória',
                                      style: TextStyle(color: s.danger, fontSize: 14)),
                                ),
                              ),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _backButton(SJScheme s) => InkWell(
        onTap: () => Navigator.of(context).canPop()
            ? Navigator.of(context).pop()
            : Navigator.of(context).pushReplacementNamed('/tabs'),
        borderRadius: BorderRadius.circular(19),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: s.surface,
            shape: BoxShape.circle,
            border: Border.all(color: s.line),
          ),
          alignment: Alignment.center,
          child: Text('←', style: TextStyle(color: s.ink, fontSize: 20)),
        ),
      );
}
