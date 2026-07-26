import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/features/music/itunes_music_provider.dart';
import 'package:some_journey/features/music/music_provider.dart';

/// Testes do adapter de música: a tradução do catálogo da Apple para o nosso
/// domínio é a única parte que conhece o formato externo, então é onde um teste
/// paga mais. Usa um cliente HTTP falso — nada de rede real.
void main() {
  final sample = jsonEncode({
    'resultCount': 1,
    'results': [
      {
        'trackId': 12345,
        'trackName': 'Águas de Março',
        'artistName': 'Elis Regina',
        'collectionName': 'Elis & Tom',
        'artworkUrl100': 'https://cdn.example/a/100x100bb.jpg',
        'previewUrl': 'https://cdn.example/p.m4a',
        'trackViewUrl': 'https://music.apple.com/track/12345',
        'trackTimeMillis': 222000,
      },
      // Item incompleto: deve ser DESCARTADO, não exibido quebrado.
      {'trackName': 'Sem id nem artista'},
    ],
  });

  test('traduz a resposta da Apple para MusicTrack (e amplia a capa)', () async {
    final provider = ItunesMusicProvider(
      client: MockClient((_) async => http.Response.bytes(
            utf8.encode(sample),
            200,
            headers: {'content-type': 'text/javascript; charset=utf-8'},
          )),
    );

    final tracks = await provider.search('elis');

    expect(tracks, hasLength(1), reason: 'o item incompleto é descartado');
    final t = tracks.single;
    expect(t.provider, 'itunes');
    expect(t.externalId, '12345');
    expect(t.title, 'Águas de Março'); // acentos preservados (UTF-8)
    expect(t.artist, 'Elis Regina');
    expect(t.album, 'Elis & Tom');
    expect(t.artworkUrl, contains('600x600bb'), reason: 'capa ampliada');
    expect(t.externalUrl, 'https://music.apple.com/track/12345');
    expect(t.durationLabel, '3:42');
  });

  test('consulta curta não vai à rede', () async {
    var called = false;
    final provider = ItunesMusicProvider(
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    expect(await provider.search(' a '), isEmpty);
    expect(called, isFalse);
  });

  test('falha de rede vira MusicSearchError (não vaza exceção de transporte)',
      () async {
    final provider = ItunesMusicProvider(
      client: MockClient((_) async => throw const HttpException$('boom')),
    );

    expect(
      () => provider.search('qualquer'),
      throwsA(isA<MusicSearchError>()),
    );
  });

  test('status de erro vira MusicSearchError', () async {
    final provider = ItunesMusicProvider(
      client: MockClient((_) async => http.Response('nope', 503)),
    );

    expect(() => provider.search('qualquer'), throwsA(isA<MusicSearchError>()));
  });

  test('MusicTrack faz ida e volta em JSON', () {
    const t = MusicTrack(
      provider: 'itunes',
      externalId: '9',
      title: 'T',
      artist: 'A',
      album: 'Al',
      durationMs: 61000,
    );
    final back = MusicTrack.fromJson(t.toJson());
    expect(back, t, reason: 'igualdade por provedor + id externo');
    expect(back.durationLabel, '1:01');
  });
}

/// Exceção mínima para simular falha de transporte no cliente falso.
class HttpException$ implements Exception {
  const HttpException$(this.message);
  final String message;
}
