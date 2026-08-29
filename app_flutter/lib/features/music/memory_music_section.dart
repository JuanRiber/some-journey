/// A trilha de uma memória, dentro do detalhe da lembrança.
///
/// Mostra as faixas guardadas e oferece anexar mais. Fica DEPOIS do texto e das
/// fotos de propósito: a música acompanha a lembrança, não a anuncia.
library;

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../design/components.dart';
import '../../design/sj_theme.dart';
import '../../design/tokens.dart';
import '../../models.dart';
import 'music_provider.dart';
import 'music_sheet.dart';

class MemoryMusicSection extends StatefulWidget {
  const MemoryMusicSection({
    super.key,
    required this.memoryId,
    required this.tracks,
    required this.onChanged,
    this.provider,
  });

  final String memoryId;
  final List<SavedTrack> tracks;

  /// A memória atualizada volta por aqui — a tela dona é que guarda o estado.
  final void Function(Memory) onChanged;

  /// Injetável para teste; em produção é o catálogo do iTunes.
  final MusicProvider? provider;

  @override
  State<MemoryMusicSection> createState() => _MemoryMusicSectionState();
}

class _MemoryMusicSectionState extends State<MemoryMusicSection> {
  bool _ocupado = false;
  String _erro = '';
  String? _removendo;

  /// O mesmo teto do backend, para a UI não convidar a um 409.
  static const _maximo = 5;

  Future<void> _anexar() async {
    final faixa = await escolherMusica(context, provider: widget.provider);
    if (faixa == null || !mounted) return;

    setState(() {
      _ocupado = true;
      _erro = '';
    });
    try {
      final m = await Api.instance.addMemoryMusic(widget.memoryId, faixa.toJson());
      if (!mounted) return;
      widget.onChanged(m);
      setState(() => _ocupado = false);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        // 409 é a faixa repetida ou o teto — os dois já são explicados pelo
        // texto que o backend manda.
        _erro = e.message;
        _ocupado = false;
      });
    }
  }

  Future<void> _remover(SavedTrack t) async {
    setState(() {
      _removendo = t.id;
      _erro = '';
    });
    try {
      final m = await Api.instance.removeMemoryMusic(widget.memoryId, t.id);
      if (!mounted) return;
      widget.onChanged(m);
      setState(() => _removendo = null);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.message;
        _removendo = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final cheio = widget.tracks.length >= _maximo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SJOverline('o que tocava'),
        const SizedBox(height: SJSpace.x3),
        if (widget.tracks.isEmpty)
          Text(
            'Nenhuma música guardada — se alguma tocava, ela cabe aqui.',
            style: SJText.bodySm(color: s.inkSoft).copyWith(
              fontFamily: SJType.serif,
              fontFamilyFallback: SJType.serifFallback,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          for (final t in widget.tracks) _linha(s, t),
        if (_erro.isNotEmpty) ...[
          const SizedBox(height: SJSpace.x3),
          Text(_erro, style: SJText.caption(color: s.danger)),
        ],
        const SizedBox(height: SJSpace.x4),
        if (!cheio)
          SJButton(
            label: widget.tracks.isEmpty ? 'Escolher a música' : 'Outra música',
            variant: SJButtonVariant.secondary,
            loading: _ocupado,
            onPressed: _ocupado ? null : _anexar,
          )
        else
          Text(
            'Cinco faixas é o limite — uma lembrança tem trilha, não playlist.',
            style: SJText.caption(color: s.inkFaint),
          ),
      ],
    );
  }

  Widget _linha(SJScheme s, SavedTrack t) {
    final saindo = _removendo == t.id;
    return Opacity(
      opacity: saindo ? 0.45 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: SJSpace.x2),
        padding: const EdgeInsets.all(SJSpace.x3),
        decoration: BoxDecoration(
          color: s.surfaceAlt,
          borderRadius: BorderRadius.circular(SJRadius.md),
          border: Border.all(color: s.line),
        ),
        child: Row(
          children: [
            _capa(s, t),
            const SizedBox(width: SJSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SJText.bodySm(color: s.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [t.artist, ?_ouNulo(t.album), ?_ouNulo(t.durationLabel)]
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SJText.caption(color: s.inkFaint),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: saindo ? null : () => _remover(t),
              icon: Icon(Icons.close, size: 17, color: s.inkFaint),
              tooltip: 'Remover música',
            ),
          ],
        ),
      ),
    );
  }

  static String? _ouNulo(String? v) => (v == null || v.isEmpty) ? null : v;

  Widget _capa(SJScheme s, SavedTrack t) {
    final url = t.artworkUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(SJRadius.sm),
      child: SizedBox(
        width: 40,
        height: 40,
        child: url == null
            ? _semCapa(s)
            : Image.network(url,
                fit: BoxFit.cover, errorBuilder: (_, _, _) => _semCapa(s)),
      ),
    );
  }

  Widget _semCapa(SJScheme s) => ColoredBox(
        color: s.bgDeep,
        child: Icon(Icons.music_note, size: 16, color: s.inkFaint),
      );
}
