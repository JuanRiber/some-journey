// O app "travado": o que estes testes seguram.
//
// O pior era invisível no código: o shell de abas recriava a timeline E o
// atlas a cada toque (uma chave nova no AnimatedSwitcher), relendo tudo da rede
// e redesenhando o mapa. O teste das abas conta pedidos — trocar de aba não
// pode custar nenhum. Os outros seguram o que tornou a recarga barata: só
// escrita avisa mudança, a releitura é silenciosa, a foto é a mesma seja qual
// for o token da URL, e é decodificada no tamanho em que aparece.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/features/phases/phase_store.dart';
import 'package:some_journey/features/sync/session_cache.dart';
import 'package:some_journey/screens/tabs.dart';
import 'package:some_journey/screens/timeline.dart';
import 'package:some_journey/widgets/sj_image.dart';

http.Response _json(Object corpo, {int status = 200}) => http.Response(
    jsonEncode(corpo), status,
    headers: {'content-type': 'application/json'});

Map<String, dynamic> _memoria(String id) => {
      'id': id,
      'title': 'Memória $id',
      'text': '',
      'latitude': -3.7,
      'longitude': -38.5,
      'occurred_at': '2024-05-01T12:00:00Z',
      'created_at': '2024-05-01T12:00:00Z',
      'images': <dynamic>[],
      'music': <dynamic>[],
    };

void main() {
  late http.Client original;
  final pedidos = <http.Request>[];

  setUp(() {
    pedidos.clear();
    PhaseStore.instance.debugSet(const []);
    Api.instance.debugSetToken('token');
  });
  tearDown(() => Api.instance.swapClient(original));

  void servidor(http.Response Function(http.Request) responde) {
    original = Api.instance.swapClient(MockClient((req) async {
      pedidos.add(req);
      return responde(req);
    }));
  }

  int contar(String caminho) =>
      pedidos.where((r) => r.method == 'GET' && r.url.path == caminho).length;

  group('o shell de abas', () {
    testWidgets('trocar de aba não relê nada nem recria as telas', (tester) async {
      servidor((req) => switch (req.url.path) {
            '/map' => _json({'loose_points': <dynamic>[], 'journeys': <dynamic>[]}),
            '/memories' => _json([_memoria('m1')]),
            _ => _json(<dynamic>[]),
          });
      await tester.pumpWidget(const MaterialApp(home: TabsScreen()));
      await tester.pumpAndSettle();
      expect(contar('/memories'), 1);
      expect(contar('/map'), 1);

      for (final aba in ['TEMPO', 'ATLAS', 'TEMPO', 'ATLAS']) {
        await tester.tap(find.text(aba));
        await tester.pumpAndSettle();
      }

      // Antes: cada troca destruía e recriava as duas abas — 5 leituras de
      // cada, com esqueleto e mapa do zero a cada toque.
      expect(contar('/memories'), 1, reason: 'a timeline foi recriada na troca');
      expect(contar('/map'), 1, reason: 'o atlas foi recriado na troca');
    });
  });

  group('o aviso de mudança', () {
    test('só escrita bem-sucedida avisa — e entrar na conta não conta', () async {
      servidor((req) {
        if (req.url.path == '/life-phases' && req.method == 'POST') {
          return _json({'detail': 'nome repetido'}, status: 409);
        }
        if (req.url.path == '/auth/login') return _json({'access_token': 't'});
        if (req.method == 'DELETE') return http.Response('', 204);
        return _json(<dynamic>[]);
      });
      final antes = Api.instance.changes.value;

      await Api.instance.listMemories();
      await Api.instance.listPhases();
      expect(Api.instance.changes.value, antes, reason: 'leitura não muda nada');

      await Api.instance.login('a@t.com', 'x' * 10);
      expect(Api.instance.changes.value, antes, reason: 'entrar não muda o acervo');

      await expectLater(Api.instance.createPhase({'name': 'X'}), throwsA(isA<ApiError>()));
      expect(Api.instance.changes.value, antes, reason: 'escrita recusada não mudou nada');

      await Api.instance.deleteMemory('m1');
      expect(Api.instance.changes.value, antes + 1);
    });

    testWidgets('a timeline se relê sozinha, sem voltar ao esqueleto', (tester) async {
      var lista = [_memoria('m1')];
      servidor((req) => req.url.path == '/memories' ? _json(lista) : _json(<dynamic>[]));
      await tester.pumpWidget(const MaterialApp(home: TimelineScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Memória m1'), findsOneWidget);

      // Uma memória gravada noutra tela (o botão central, por exemplo).
      lista = [_memoria('m2'), _memoria('m1')];
      Api.instance.changes.value++;
      await tester.pump(const Duration(milliseconds: 200));
      // Durante a espera e a releitura, o álbum antigo continua na tela.
      expect(find.bySemanticsLabel('Carregando seu álbum'), findsNothing);
      expect(find.text('Memória m1'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(contar('/memories'), 2);
      expect(find.text('Memória m2'), findsOneWidget);
    });
  });

  group('a foto', () {
    test('a chave é o arquivo, não o token da URL assinada', () {
      final a = StableNetworkImage('https://x.supabase.co/obj/memories/u/1.jpg?token=AAA');
      final b = StableNetworkImage('https://x.supabase.co/obj/memories/u/1.jpg?token=BBB');
      final c = StableNetworkImage('https://x.supabase.co/obj/memories/u/2.jpg?token=AAA');
      expect(a, b, reason: 'mesmo arquivo, token novo: mesma imagem no cache');
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      // A carga continua usando a URL inteira, com o token.
      expect(b.url, endsWith('token=BBB'));
    });

    test('decodificada no tamanho em que aparece', () {
      // Miniatura de 84 pt numa tela 3x, com `cover`: 1,6 × 84 × 3.
      expect(
        larguraDeDecodificacao(largura: 84, altura: 84, fit: BoxFit.cover, densidade: 3),
        404,
      );
      // Quadro 4:5 de 360 × 450: o maior lado manda, com folga para foto deitada.
      expect(
        larguraDeDecodificacao(largura: 360, altura: 450, fit: BoxFit.cover, densidade: 2),
        1440,
      );
      // Sem tamanho conhecido não há o que economizar.
      expect(
        larguraDeDecodificacao(largura: null, altura: double.infinity, fit: BoxFit.cover, densidade: 2),
        isNull,
      );
    });

    testWidgets('o widget pede a imagem já reduzida', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: SJNetworkImage('https://x.test/f.jpg?t=1', width: 84, height: 84)),
      ));
      final imagem = tester.widget<Image>(find.byType(Image));
      expect(imagem.image, isA<ResizeImage>());
      final r = imagem.image as ResizeImage;
      expect(r.width, isNotNull);
      expect(r.width! < 1000, isTrue, reason: 'uma miniatura não decodifica a foto inteira');
      expect(r.imageProvider, StableNetworkImage('https://x.test/f.jpg?t=2'));
    });
  });

  group('o cache de tela', () {
    test('vale só para a sessão em que foi guardado', () {
      final cache = SessionCache<String>();
      Api.instance.debugSetToken('sessao-1');
      cache.valor = 'perfil da pessoa 1';
      expect(cache.valor, 'perfil da pessoa 1');

      Api.instance.debugSetToken('sessao-2');
      expect(cache.valor, isNull, reason: 'outra conta não vê o cache da anterior');

      Api.instance.debugSetToken(null);
      expect(cache.valor, isNull, reason: 'sem sessão, nada');
    });
  });
}
