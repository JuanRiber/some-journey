import 'dart:convert';

import 'package:http/http.dart' as http;

import 'music_provider.dart';

/// # Adapter: iTunes Search API (catálogo da Apple, gratuito e SEM chave).
///
/// Traduz a resposta da Apple para o [MusicTrack] do nosso domínio. É o único
/// arquivo do app que conhece o formato da Apple — trocar para MusicKit,
/// Spotify ou Deezer significa escrever outro [MusicProvider] e não tocar em
/// mais nada.
///
/// Detalhes que valem registrar:
/// - `entity=song` + `media=music` para não voltar álbum/podcast/vídeo.
/// - A capa vem como `artworkUrl100` (100px). Trocamos por `600x600` na URL —
///   truque conhecido e estável do CDN da Apple — porque no Some Journey a FOTO
///   e a capa são protagonistas e uma miniatura de 100px ficaria borrada.
/// - `trackViewUrl` é o link para ouvir (abre no Apple Music/iTunes).
/// - `previewUrl` (30s) é guardado para um player interno futuro.
/// - Sem chave e com CORS liberado, então funciona igual no web e no nativo.
class ItunesMusicProvider implements MusicProvider {
  ItunesMusicProvider({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 12);

  @override
  String get id => 'itunes';

  @override
  Future<List<MusicTrack>> search(String query, {int limit = 20}) async {
    final term = query.trim();
    // Busca com 1 caractere devolve ruído e gasta rede a cada tecla digitada.
    if (term.length < 2) return const [];

    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'media': 'music',
      'entity': 'song',
      'limit': '$limit',
    });

    late http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } catch (_) {
      throw MusicSearchError('Não foi possível buscar músicas agora.');
    }
    if (response.statusCode >= 400) {
      throw MusicSearchError('A busca de músicas falhou. Tente de novo.');
    }

    try {
      // A API responde text/javascript; decodificamos os bytes como UTF-8 para
      // acentos (Sabiá, Águas de Março) não chegarem corrompidos.
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final results = (body is Map ? body['results'] : null);
      if (results is! List) return const [];
      return results
          .whereType<Map<String, dynamic>>()
          .map(_toTrack)
          .whereType<MusicTrack>()
          .toList();
    } catch (_) {
      throw MusicSearchError('Resposta inesperada da busca de músicas.');
    }
  }

  /// Um item da Apple -> nossa faixa. Devolve null quando falta o essencial
  /// (id/título/artista), para a lista nunca exibir um resultado quebrado.
  MusicTrack? _toTrack(Map<String, dynamic> j) {
    final externalId = j['trackId']?.toString();
    final title = j['trackName'] as String?;
    final artist = j['artistName'] as String?;
    if (externalId == null || title == null || artist == null) return null;

    final artwork = j['artworkUrl100'] as String?;
    return MusicTrack(
      provider: id,
      externalId: externalId,
      title: title,
      artist: artist,
      album: j['collectionName'] as String?,
      // 100px -> 600px: a capa é protagonista na página da memória.
      artworkUrl: artwork?.replaceFirst('100x100bb', '600x600bb'),
      previewUrl: j['previewUrl'] as String?,
      externalUrl: j['trackViewUrl'] as String?,
      durationMs: (j['trackTimeMillis'] as num?)?.toInt(),
    );
  }
}
