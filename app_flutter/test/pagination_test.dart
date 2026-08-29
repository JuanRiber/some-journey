// Contrato de paginação por keyset entre o app e a API.
//
// Por que este teste existe: a API pagina desde sempre (30 por página, cursor no
// header `X-Next-Cursor`), e o cliente ignorava isso — pedia uma vez e mostrava
// o que viesse. A partir da 31ª memória o acervo simplesmente sumia da tela, sem
// erro nenhum. Num app cujo propósito é acumular memórias, é a pior falha
// possível: invisível, e pior quanto mais a pessoa usa.
//
// Os testes falam com um cliente HTTP falso — sem rede, sem backend de pé.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';

/// Uma memória mínima, no formato que a API devolve.
Map<String, dynamic> _memory(int i) => {
      'id': 'id-$i',
      'title': 'Memória $i',
      'text': 'registro $i',
      'latitude': -3.7,
      'longitude': -38.5,
      'occurred_at': '2026-06-${(i % 28) + 1}T12:00:00Z',
      'created_at': '2026-06-01T12:00:00Z',
      'images': <dynamic>[],
    };

void main() {
  late http.Client original;
  final chamadas = <Uri>[];

  setUp(() {
    chamadas.clear();
    Api.instance.debugSetToken('token-de-teste');
  });

  tearDown(() => Api.instance.swapClient(original));

  /// Instala um cliente falso que registra as URLs pedidas e responde
  /// [respostas] na ordem.
  void responder(List<http.Response> respostas) {
    var i = 0;
    original = Api.instance.swapClient(MockClient((req) async {
      chamadas.add(req.url);
      return respostas[i++];
    }));
  }

  http.Response pagina(List<int> indices, {String? proximo}) => http.Response(
        jsonEncode(indices.map(_memory).toList()),
        200,
        headers: {
          'content-type': 'application/json',
          'x-next-cursor': ?proximo,
        },
      );

  group('listMemories', () {
    test('lê o cursor do header e sinaliza que há mais', () async {
      responder([pagina([1, 2, 3], proximo: 'CURSOR-A')]);

      final p = await Api.instance.listMemories();

      expect(p.items, hasLength(3));
      expect(p.nextCursor, 'CURSOR-A');
      expect(p.hasMore, isTrue);
    });

    test('sem o header, a lista acabou', () async {
      responder([pagina([1, 2])]);

      final p = await Api.instance.listMemories();

      expect(p.nextCursor, isNull);
      expect(p.hasMore, isFalse);
    });

    test('manda o cursor de volta, codificado', () async {
      // Cursor real do backend: base64url, com '=' de padding. Concatenar na mão
      // corromperia o padding e a API responderia 400.
      const cursor = 'MjAyNi0wMy0wM1QwOTowMDowMHw0Yjcw=';
      responder([pagina([31])]);

      await Api.instance.listMemories(cursor: cursor);

      expect(chamadas.single.queryParameters['cursor'], cursor,
          reason: 'o cursor precisa chegar íntegro ao servidor');
      expect(chamadas.single.query, contains('%3D'),
          reason: 'o = do padding tem de ir percent-encoded');
    });

    test('limit vai na querystring quando pedido', () async {
      responder([pagina([1])]);

      await Api.instance.listMemories(limit: 50);

      expect(chamadas.single.queryParameters['limit'], '50');
    });

    test('sem limit nem cursor, a rota vai limpa', () async {
      responder([pagina([1])]);

      await Api.instance.listMemories();

      expect(chamadas.single.path, '/memories');
      expect(chamadas.single.hasQuery, isFalse);
    });

    test('percorre TODAS as páginas — a 31ª memória não se perde', () async {
      final primeira = List.generate(30, (i) => i + 1);
      responder([
        pagina(primeira, proximo: 'CURSOR-A'),
        pagina([31, 32, 33, 34, 35]),
      ]);

      final todas = <String>[];
      var page = await Api.instance.listMemories();
      todas.addAll(page.items.map((m) => m.id));
      while (page.hasMore) {
        page = await Api.instance.listMemories(cursor: page.nextCursor);
        todas.addAll(page.items.map((m) => m.id));
      }

      expect(todas, hasLength(35), reason: 'o acervo inteiro precisa chegar');
      expect(todas.toSet(), hasLength(35), reason: 'sem repetir nenhuma');
      expect(todas, contains('id-31'), reason: 'a memória que o bug escondia');
      expect(chamadas, hasLength(2));
      expect(chamadas.first.hasQuery, isFalse);
      expect(chamadas.last.queryParameters['cursor'], 'CURSOR-A');
    });
  });

  group('listJourneys', () {
    test('pagina pelo mesmo contrato', () async {
      original = Api.instance.swapClient(MockClient((req) async {
        chamadas.add(req.url);
        return http.Response(
          jsonEncode([
            {
              'id': 'j1',
              'title': 'Uma jornada',
              'status': 'draft',
              'points_count': 0,
              'created_at': '2026-06-01T12:00:00Z',
            }
          ]),
          200,
          headers: {'content-type': 'application/json', 'x-next-cursor': 'C1'},
        );
      }));

      final p = await Api.instance.listJourneys();

      expect(p.items, hasLength(1));
      expect(p.nextCursor, 'C1');
    });
  });
}
