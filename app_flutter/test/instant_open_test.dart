// As telas abrem com o que já está na mão, e conferem depois.
//
// A timeline traz cada memória inteira. Tocar numa delas abria o detalhe em
// branco e buscava na rede exatamente o que a lista acabara de mostrar — meio
// segundo de espera por um dado que já estava ali. Estes testes seguram o
// servidor de propósito (ele só responde quando o teste manda) e afirmam o que
// a pessoa vê ANTES da resposta: é essa a diferença entre abrir na hora e
// abrir depois.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/features/sync/seen.dart';
import 'package:some_journey/screens/journey_detail.dart';
import 'package:some_journey/screens/memory_detail.dart';

Map<String, dynamic> _memoria(String id, {String titulo = 'Praia de Iracema'}) => {
      'id': id,
      'title': titulo,
      'text': 'O fim de tarde daqui.',
      'latitude': -3.72,
      'longitude': -38.51,
      'occurred_at': '2026-08-28T21:30:00Z',
      'created_at': '2026-08-28T21:30:00Z',
      'images': <dynamic>[],
      'music': <dynamic>[],
    };

Map<String, dynamic> _jornada(String id, {String titulo = 'Litoral'}) => {
      'id': id,
      'title': titulo,
      'is_private': true,
      'status': 'draft',
      'created_at': '2026-08-28T21:30:00Z',
      'points_count': 0,
      'points': <dynamic>[],
    };

http.Response _json(Object corpo, [int status = 200]) =>
    http.Response(jsonEncode(corpo), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  late http.Client anterior;

  /// "MÉTODO caminho" de cada pedido, na ordem em que SAIU.
  late List<String> pedidos;

  /// Cada pedido fica esperando aqui até o teste liberar.
  late Map<String, Completer<http.Response>> presos;

  setUp(() {
    pedidos = [];
    presos = {};
    Api.instance.debugSetToken('sessao-de-teste');
    anterior = Api.instance.swapClient(MockClient((r) {
      final chave = '${r.method} ${r.url.path}';
      pedidos.add(chave);
      return (presos[chave] = Completer<http.Response>()).future;
    }));
  });

  tearDown(() {
    Api.instance.swapClient(anterior);
    Api.instance.debugSetToken(null);
  });

  Future<void> responder(WidgetTester tester, String chave, http.Response r) async {
    presos[chave]!.complete(r);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> abrir(WidgetTester tester, Widget tela) async {
    await tester.pumpWidget(MaterialApp(
      home: tela,
      routes: {'/login': (_) => const Scaffold(body: Text('LOGIN'))},
    ));
    await tester.pump();
  }

  group('o que a API viu fica à mão', () {
    test('a lista de memórias deixa cada uma pronta para o detalhe', () async {
      final lista = Api.instance.listMemories();
      await pumpEventQueue();
      presos['GET /memories']!.complete(_json([_memoria('m1'), _memoria('m2')]));
      await lista;

      expect(memoriasVistas['m1']?.title, 'Praia de Iracema');
      expect(memoriasVistas['m2'], isNotNull);
    });

    test('apagar tira da mão', () async {
      memoriasVistas['m1'] = (await _ler('m1'));
      final apagar = Api.instance.deleteMemory('m1');
      await pumpEventQueue();
      presos['DELETE /memories/m1']!.complete(http.Response('', 204));
      await apagar;

      expect(memoriasVistas['m1'], isNull);
    });

    test('outra sessão não herda nada', () async {
      memoriasVistas['m1'] = (await _ler('m1'));
      expect(memoriasVistas['m1'], isNotNull);

      Api.instance.debugSetToken('outra-pessoa');

      expect(memoriasVistas['m1'], isNull);
      expect(memoriasVistas.length, 0);
    });

    test('sem sessão não guarda nada', () async {
      final m = await _ler('m1');
      Api.instance.debugSetToken(null);

      memoriasVistas['m1'] = m;

      expect(memoriasVistas['m1'], isNull);
    });

    test('o teto tira o que foi visto há mais tempo', () async {
      final cache = SeenCache<int>(capacidade: 3);
      for (var i = 0; i < 4; i++) {
        cache['id$i'] = i;
      }
      cache['id1'] = 11; // visto de novo: volta para o fim da fila

      cache['id9'] = 9;

      expect(cache['id0'], isNull);
      expect(cache['id2'], isNull, reason: 'era o mais antigo depois do id1 voltar');
      expect(cache['id1'], 11);
      expect(cache.length, 3);
    });
  });

  group('detalhe da memória', () {
    testWidgets('já vista: aparece ANTES de o servidor responder', (tester) async {
      memoriasVistas['m1'] = await _ler('m1');

      await abrir(tester, const MemoryDetailScreen(memoryId: 'm1'));

      expect(presos['GET /memories/m1']!.isCompleted, isFalse,
          reason: 'o servidor ainda não respondeu');
      expect(find.text('Praia de Iracema'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Libera o pedido que ficou no ar, para o teste terminar limpo.
      await responder(tester, 'GET /memories/m1', _json(_memoria('m1')));
    });

    testWidgets('e ainda assim relê: o que mudou no servidor chega à tela',
        (tester) async {
      memoriasVistas['m1'] = await _ler('m1');
      await abrir(tester, const MemoryDetailScreen(memoryId: 'm1'));

      await responder(tester, 'GET /memories/m1',
          _json(_memoria('m1', titulo: 'Praia do Futuro')));

      expect(find.text('Praia do Futuro'), findsOneWidget);
      expect(find.text('Praia de Iracema'), findsNothing);
    });

    testWidgets('releitura que falha não tira da tela o que a pessoa está lendo',
        (tester) async {
      memoriasVistas['m1'] = await _ler('m1');
      await abrir(tester, const MemoryDetailScreen(memoryId: 'm1'));

      await responder(tester, 'GET /memories/m1', _json({'detail': 'x'}, 503));

      expect(find.text('Praia de Iracema'), findsOneWidget);
      expect(find.textContaining('fora do ar'), findsNothing);
    });

    testWidgets('apagada noutro lugar: some da tela e da mão', (tester) async {
      memoriasVistas['m1'] = await _ler('m1');
      await abrir(tester, const MemoryDetailScreen(memoryId: 'm1'));

      await responder(tester, 'GET /memories/m1',
          _json({'detail': 'Memória não encontrada.'}, 404));

      expect(find.text('Praia de Iracema'), findsNothing);
      expect(find.text('Memória não encontrada.'), findsOneWidget);
      expect(memoriasVistas['m1'], isNull);
    });

    testWidgets('nunca vista: espera, como antes', (tester) async {
      await abrir(tester, const MemoryDetailScreen(memoryId: 'nova'));

      expect(find.text('Praia de Iracema'), findsNothing);

      await responder(tester, 'GET /memories/nova', _json(_memoria('nova')));

      expect(find.text('Praia de Iracema'), findsOneWidget);
    });
  });

  group('detalhe da jornada', () {
    testWidgets('os três pedidos saem JUNTOS, sem um esperar o outro',
        (tester) async {
      await abrir(tester, const JourneyDetailScreen(journeyId: 'j1'));

      // Nenhum foi respondido ainda, e os três já saíram.
      expect(pedidos.toSet(), {
        'GET /journeys/j1',
        'GET /journeys/j1/map',
        'GET /journeys/j1/tracks',
      });
      expect(presos.values.every((c) => !c.isCompleted), isTrue);

      presos['GET /journeys/j1/map']!.complete(_json(<String, dynamic>{}));
      presos['GET /journeys/j1/tracks']!.complete(_json(<dynamic>[]));
      await responder(tester, 'GET /journeys/j1', _json(_jornada('j1')));
      expect(find.text('Litoral'), findsOneWidget);
    });

    testWidgets('reaberta: aparece antes de o servidor responder', (tester) async {
      final ler = Api.instance.getJourney('j1');
      await tester.pump();
      presos['GET /journeys/j1']!.complete(_json(_jornada('j1')));
      await ler;
      pedidos.clear();
      presos.clear();

      await abrir(tester, const JourneyDetailScreen(journeyId: 'j1'));

      expect(find.text('Litoral'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(presos['GET /journeys/j1']!.isCompleted, isFalse);

      // Fecha os pedidos que ficaram no ar, para o teste terminar limpo.
      presos['GET /journeys/j1/map']!.complete(_json(<String, dynamic>{}));
      presos['GET /journeys/j1/tracks']!.complete(_json(<dynamic>[]));
      await responder(tester, 'GET /journeys/j1',
          _json(_jornada('j1', titulo: 'Litoral leste')));
      expect(find.text('Litoral leste'), findsOneWidget);
    });

    testWidgets('percurso que falha não segura a jornada', (tester) async {
      await abrir(tester, const JourneyDetailScreen(journeyId: 'j1'));

      presos['GET /journeys/j1/map']!.complete(_json({'detail': 'x'}, 503));
      presos['GET /journeys/j1/tracks']!.complete(_json({'detail': 'x'}, 503));
      await responder(tester, 'GET /journeys/j1', _json(_jornada('j1')));

      expect(find.text('Litoral'), findsOneWidget);
    });
  });
}

/// Uma memória como a API a devolveria, sem passar pela rede.
Future<dynamic> _ler(String id) async {
  final cliente = MockClient((_) async => _json(_memoria(id)));
  final anterior = Api.instance.swapClient(cliente);
  try {
    return await Api.instance.getMemory(id);
  } finally {
    Api.instance.swapClient(anterior);
  }
}
