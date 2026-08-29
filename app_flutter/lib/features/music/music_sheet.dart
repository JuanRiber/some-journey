/// Busca e escolha da canção que estava tocando.
///
/// **Por que uma folha e não uma tela.** Anexar música é um gesto DENTRO de uma
/// lembrança, não uma jornada própria: a memória continua atrás, visível, e a
/// pessoa volta para ela com um toque.
///
/// **O que a busca não faz.** Não busca a cada tecla. Um catálogo público
/// cobrado por requisição e uma pessoa digitando "caetano" produziriam sete
/// buscas para uma intenção. Aqui a consulta parte quando a digitação pausa.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/sj_theme.dart';
import '../../design/tokens.dart';
import 'itunes_music_provider.dart';
import 'music_provider.dart';

/// Abre a folha e devolve a faixa escolhida — ou nulo se a pessoa desistiu.
Future<MusicTrack?> escolherMusica(
  BuildContext context, {
  MusicProvider? provider,
}) =>
    showModalBottomSheet<MusicTrack>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MusicSheet(provider: provider ?? ItunesMusicProvider()),
    );

class _MusicSheet extends StatefulWidget {
  const _MusicSheet({required this.provider});

  final MusicProvider provider;

  @override
  State<_MusicSheet> createState() => _MusicSheetState();
}

class _MusicSheetState extends State<_MusicSheet> {
  final _campo = TextEditingController();
  Timer? _debounce;

  List<MusicTrack> _resultados = const [];
  bool _buscando = false;
  String _erro = '';

  /// Espera a digitação pausar antes de consultar. 350ms é o intervalo em que
  /// uma pausa deixa de ser hesitação e passa a ser "terminei de escrever".
  static const _pausa = Duration(milliseconds: 350);

  void _aoDigitar(String termo) {
    _debounce?.cancel();
    if (termo.trim().length < 2) {
      setState(() {
        _resultados = const [];
        _erro = '';
        _buscando = false;
      });
      return;
    }
    setState(() => _buscando = true);
    _debounce = Timer(_pausa, () => _buscar(termo));
  }

  Future<void> _buscar(String termo) async {
    try {
      final achados = await widget.provider.search(termo);
      if (!mounted) return;
      setState(() {
        _resultados = achados;
        _buscando = false;
        _erro = '';
      });
    } on MusicSearchError catch (e) {
      if (!mounted) return;
      // Música é enfeite da memória, nunca bloqueio: a falha é uma frase calma,
      // e a lembrança segue registrável sem ela.
      setState(() {
        _erro = e.message;
        _buscando = false;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _campo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(SJRadius.xl),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          SJSpace.screenX,
          SJSpace.x3,
          SJSpace.screenX,
          SJSpace.x6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: s.line,
                  borderRadius: BorderRadius.circular(SJRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: SJSpace.x5),
            const SJOverline('a trilha do momento'),
            const SizedBox(height: SJSpace.x2),
            Text('Que música tocava?', style: SJText.h2(color: s.ink)),
            const SizedBox(height: SJSpace.x4),
            SJTextField(
              label: 'Buscar',
              controller: _campo,
              hint: 'nome da música, artista ou álbum',
              autofocus: true,
              onChanged: _aoDigitar,
            ),
            const SizedBox(height: SJSpace.x4),
            SizedBox(height: 320, child: _corpo(s)),
          ],
        ),
      ),
    );
  }

  Widget _corpo(SJScheme s) {
    if (_erro.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SJSpace.x4),
          child: Text(
            _erro,
            textAlign: TextAlign.center,
            style: SJText.bodySm(color: s.inkSoft),
          ),
        ),
      );
    }
    if (_buscando) return const Center(child: SJSpinner());

    if (_campo.text.trim().length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SJSpace.x6),
          child: Text(
            'Escreva o nome da canção — ou do artista, se só isso ficou.',
            textAlign: TextAlign.center,
            style: SJText.bodySm(color: s.inkSoft).copyWith(
              fontFamily: SJType.serif,
              fontFamilyFallback: SJType.serifFallback,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    if (_resultados.isEmpty) {
      return Center(
        child: Text(
          'Nada com esse nome.',
          style: SJText.bodySm(color: s.inkSoft),
        ),
      );
    }

    return ListView.separated(
      itemCount: _resultados.length,
      separatorBuilder: (_, _) => const SizedBox(height: SJSpace.x1),
      itemBuilder: (_, i) => _linha(s, _resultados[i]),
    );
  }

  Widget _linha(SJScheme s, MusicTrack t) => SJPressable(
        onTap: () => Navigator.of(context).pop(t),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SJSpace.x2),
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
                      [t.artist, ?_ouNulo(t.album)].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SJText.caption(color: s.inkFaint),
                    ),
                  ],
                ),
              ),
              if (t.durationLabel.isNotEmpty) ...[
                const SizedBox(width: SJSpace.x2),
                Text(t.durationLabel, style: SJText.caption(color: s.inkFaint)),
              ],
            ],
          ),
        ),
      );

  static String? _ouNulo(String? v) => (v == null || v.isEmpty) ? null : v;

  /// Capa do álbum. Falha de imagem cai numa marca discreta em vez de um ícone
  /// de erro: a linha continua legível e clicável.
  Widget _capa(SJScheme s, MusicTrack t) {
    final url = t.artworkUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(SJRadius.sm),
      child: SizedBox(
        width: 44,
        height: 44,
        child: url == null
            ? _semCapa(s)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _semCapa(s),
              ),
      ),
    );
  }

  Widget _semCapa(SJScheme s) => ColoredBox(
        color: s.surfaceAlt,
        child: Icon(Icons.music_note, size: 18, color: s.inkFaint),
      );
}
