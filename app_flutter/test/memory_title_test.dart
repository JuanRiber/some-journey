// Memória sem título.
//
// A regra de produto (docs/01-regras-negocio.md) sempre quis o título opcional
// e a API é que exigia: para guardar uma lembrança a pessoa tinha de inventar
// um rótulo. Agora o título pode faltar — e o que estes testes guardam não é a
// permissão, é a CONSEQUÊNCIA dela na tela.
//
// Porque o risco de soltar a obrigatoriedade não está no backend: está em cada
// lugar que desenhava o título sem perguntar se ele existe. Um `Text('')` não
// quebra nada e não aparece em teste nenhum — vira uma linha em branco que
// parece defeito, e ninguém descobre até olhar.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/design/components.dart';
import 'package:some_journey/models.dart';
import 'package:some_journey/screens/timeline.dart';

Map<String, dynamic> _memoria({String title = 'Praia', String text = ''}) => {
      'id': 'm1',
      'title': title,
      'text': text,
      'latitude': -3.7,
      'longitude': -38.5,
      'occurred_at': '2026-08-14T00:00:00Z',
      'created_at': '2026-08-14T10:00:00Z',
      'images': <dynamic>[],
      'music': <dynamic>[],
    };

void main() {
  group('o modelo sabe dizer se há título', () {
    test('título escrito conta', () {
      expect(Memory.fromJson(_memoria(title: 'Praia')).hasTitle, isTrue);
    });

    test('vazio não conta', () {
      expect(Memory.fromJson(_memoria(title: '')).hasTitle, isFalse);
    });

    test('só espaço não conta — senão a linha em branco voltaria disfarçada',
        () {
      expect(Memory.fromJson(_memoria(title: '   ')).hasTitle, isFalse);
    });

    test('o ponto da jornada responde igual', () {
      final p = JourneyPoint.fromJson({
        'memory_id': 'm1',
        'title': '',
        'latitude': -3.7,
        'longitude': -38.5,
        'occurred_at': '2026-08-14T00:00:00Z',
      });
      expect(p.hasTitle, isFalse);
    });
  });

  group('a timeline com uma memória sem título', () {
    late http.Client original;

    setUp(() {
      Api.instance.debugSetToken('token');
    });
    tearDown(() => Api.instance.swapClient(original));

    Future<void> montar(WidgetTester tester, {required String title}) async {
      original = Api.instance.swapClient(MockClient((_) async => http.Response(
            jsonEncode([_memoria(title: title, text: 'o mar estava frio')]),
            200,
            headers: {'content-type': 'application/json'},
          )));
      await tester.pumpWidget(const MaterialApp(home: TimelineScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('o cartão aparece, com a data e o trecho do texto',
        (tester) async {
      await montar(tester, title: '');

      expect(find.byType(SJCard), findsOneWidget,
          reason: 'sem título a memória continua existindo');
      expect(find.text('14 AGO'), findsOneWidget,
          reason: 'a data é o que identifica a memória agora');
      expect(find.textContaining('o mar estava frio'), findsOneWidget);
    });

    testWidgets('com título, ele continua na tela', (tester) async {
      await montar(tester, title: 'Praia');
      expect(find.text('Praia'), findsOneWidget);
    });
  });
}
