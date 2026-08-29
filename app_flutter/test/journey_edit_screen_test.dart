// A tela de editar jornada, de ponta a ponta com um servidor falso.
//
// O que importa aqui é o comportamento que protege a pessoa: a tela abre com o
// que já está escrito, o botão só acende quando há o que salvar, e sair sem
// mexer não gasta uma requisição.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/design/components.dart';
import 'package:some_journey/screens/journey_edit.dart';

const _jornada = {
  'id': 'j1',
  'title': 'Mochilão',
  'description': 'Três meses de estrada',
  'mood': 'leve',
  'status': 'active',
  'is_private': true,
  'points_count': 3,
  'created_at': '2026-06-01T12:00:00Z',
  'points': <dynamic>[],
};

void main() {
  late http.Client original;
  final patches = <Map<String, dynamic>>[];

  setUp(() {
    patches.clear();
    Api.instance.debugSetToken('token');
    original = Api.instance.swapClient(MockClient((req) async {
      if (req.method == 'PATCH') {
        patches.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode(_jornada), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode(_jornada), 200,
          headers: {'content-type': 'application/json'});
    }));
  });

  tearDown(() => Api.instance.swapClient(original));

  /// Monta a tela como uma rota empilhada, para que o `pop` do salvar funcione
  /// como funciona no app.
  Future<void> abrir(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const JourneyEditScreen(journeyId: 'j1'),
          )),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  /// Rola até o botão antes de tocar: a superfície de teste (800x600) é menor
  /// que a tela real, e o botão fica abaixo da dobra.
  Future<void> salvar(WidgetTester tester) async {
    final botao = find.text('Salvar alterações'.toUpperCase());
    await tester.ensureVisible(botao);
    await tester.pumpAndSettle();
    await tester.tap(botao);
  }

  testWidgets('abre com o que já está escrito', (tester) async {
    await abrir(tester);

    expect(find.text('Mochilão'), findsOneWidget);
    expect(find.text('Três meses de estrada'), findsOneWidget);
    expect(find.text('leve'), findsOneWidget);
  });

  testWidgets('sem mexer em nada, o botão fica apagado', (tester) async {
    await abrir(tester);

    final botao = tester.widget<SJButton>(
      find.widgetWithText(SJButton, 'Salvar alterações'.toUpperCase()),
    );
    expect(botao.onPressed, isNull,
        reason: 'nada a salvar não pode parecer clicável');
  });

  testWidgets('editar o título acende o botão e envia só ele', (tester) async {
    await abrir(tester);

    await tester.enterText(find.text('Mochilão'), 'Mochilão pela Europa');
    await tester.pump();

    await salvar(tester);
    await tester.pumpAndSettle();

    expect(patches, hasLength(1));
    expect(patches.single, {'title': 'Mochilão pela Europa'});
  });

  testWidgets('apagar a descrição envia string vazia, não null',
      (tester) async {
    await abrir(tester);

    await tester.enterText(find.text('Três meses de estrada'), '');
    await tester.pump();
    await salvar(tester);
    await tester.pumpAndSettle();

    expect(patches.single['description'], '',
        reason: 'null é ignorado pelo backend e o texto voltaria');
  });

  testWidgets('título vazio é recusado antes de sair da tela', (tester) async {
    await abrir(tester);

    await tester.enterText(find.text('Mochilão'), '');
    await tester.pump();
    await salvar(tester);
    await tester.pump();

    expect(find.text('Uma jornada precisa de um nome.'), findsOneWidget);
    expect(patches, isEmpty, reason: 'não gasta requisição com entrada inválida');
  });
}
