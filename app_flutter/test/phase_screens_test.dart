// Fases da vida na tela: a lente, o seletor, a etiqueta e o formulário.
//
// O que estes testes guardam é o que a pessoa SENTE — e o primeiro item é o
// que ela não sente: quem nunca criou uma fase não vê controle nenhum. Depois,
// os gestos que têm regra própria: tocar de novo na fase da lente volta para a
// vida toda; esvaziar a data de fim REABRE a fase (manda null); apagar pede
// confirmação e diz que as memórias ficam.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/design/components.dart';
import 'package:some_journey/features/phases/phase_domain.dart';
import 'package:some_journey/features/phases/phase_store.dart';
import 'package:some_journey/features/phases/phase_widgets.dart';
import 'package:some_journey/screens/journey_edit.dart';
import 'package:some_journey/screens/journey_new.dart';
import 'package:some_journey/screens/journeys.dart';
import 'package:some_journey/screens/phases.dart';
import 'package:some_journey/screens/timeline.dart';

const _infancia = LifePhase(id: 'a', name: 'Infância', color: PhaseColor.highlight);
const _faculdade = LifePhase(
  id: 'b',
  name: 'Faculdade',
  color: PhaseColor.moss,
  startedOn: '2015-03-01',
  endedOn: '2019-12-01',
);

Map<String, dynamic> _faseJson(LifePhase f) => {
      'id': f.id,
      'name': f.name,
      'description': f.description,
      'color': f.color.name,
      'started_at': f.startedOn == null ? null : '${f.startedOn}T12:00:00Z',
      'ended_at': f.endedOn == null ? null : '${f.endedOn}T12:00:00Z',
    };

http.Response _json(Object corpo, {int status = 200}) => http.Response(
    jsonEncode(corpo), status,
    headers: {'content-type': 'application/json'});

Future<void> _montar(WidgetTester tester, Widget filho) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: filho)));
  await tester.pump();
}

void main() {
  setUp(() => PhaseStore.instance.debugSet(const []));

  group('a lente', () {
    testWidgets('sem fase cadastrada, não aparece', (tester) async {
      await _montar(
        tester,
        PhaseLens(phases: const [], selected: null, onChanged: (_) {}),
      );
      expect(find.text('A vida toda'), findsNothing);
      expect(find.byType(SJChip), findsNothing);
    });

    testWidgets('escolher uma fase e tocar de novo volta para a vida toda',
        (tester) async {
      String? escolhida;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PhaseLens(
              phases: const [_infancia, _faculdade],
              selected: escolhida,
              onChanged: (id) => setState(() => escolhida = id),
            ),
          ),
        ),
      ));

      expect(find.text('A vida toda'), findsOneWidget);
      await tester.tap(find.text('Faculdade'));
      await tester.pump();
      expect(escolhida, 'b');

      await tester.tap(find.text('Faculdade'));
      await tester.pump();
      expect(escolhida, isNull,
          reason: 'tocar no filtro ativo é o gesto de tirá-lo');
    });
  });

  group('o seletor', () {
    testWidgets('tocar na escolhida não desfaz; "Nenhuma" desfaz',
        (tester) async {
      final recebidos = <String?>[];
      await _montar(
        tester,
        PhasePicker(
          phases: const [_infancia],
          selected: 'a',
          onChanged: recebidos.add,
        ),
      );

      await tester.tap(find.text('Infância'));
      await tester.tap(find.text('Nenhuma'));
      expect(recebidos, ['a', null]);
    });

    testWidgets('sem fase cadastrada, o formulário fica como era',
        (tester) async {
      await _montar(
        tester,
        PhasePicker(phases: const [], selected: null, onChanged: (_) {}),
      );
      expect(find.text('Nenhuma'), findsNothing);
      expect(find.textContaining('FASE DA VIDA'), findsNothing);
    });
  });

  group('a etiqueta', () {
    testWidgets('lê o nome da lista e acompanha uma fase renomeada',
        (tester) async {
      PhaseStore.instance.debugSet(const [_infancia]);
      await _montar(tester, const PhaseTag(phaseId: 'a'));
      expect(find.text('Infância'), findsOneWidget);

      PhaseStore.instance.debugSet(const [
        LifePhase(id: 'a', name: 'Primeiros anos', color: PhaseColor.highlight),
      ]);
      await tester.pump();
      expect(find.text('Primeiros anos'), findsOneWidget);
    });

    testWidgets('fase desconhecida não desenha nada', (tester) async {
      await _montar(tester, const PhaseTag(phaseId: 'sumiu'));
      expect(find.byType(PhaseDot), findsNothing);
    });
  });

  group('o formulário da fase', () {
    late http.Client original;
    final pedidos = <http.Request>[];

    setUp(() {
      pedidos.clear();
      Api.instance.debugSetToken('token');
      original = Api.instance.swapClient(MockClient((req) async {
        pedidos.add(req);
        if (req.method == 'DELETE') return http.Response('', 204);
        return _json(_faseJson(_faculdade), status: req.method == 'POST' ? 201 : 200);
      }));
    });

    tearDown(() => Api.instance.swapClient(original));

    /// Empilha o formulário sobre uma tela qualquer, para o `pop` funcionar
    /// como no app, e devolve o que ele devolveu ao sair.
    Future<List<bool?>> abrir(WidgetTester tester, {LifePhase? fase}) async {
      final resultados = <bool?>[];
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => resultados.add(await Navigator.of(context)
                .push<bool>(MaterialPageRoute(
                    builder: (_) => PhaseEditScreen(phase: fase)))),
            child: const Text('abrir'),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return resultados;
    }

    Future<void> tocar(WidgetTester tester, String texto) async {
      final alvo = find.text(texto);
      await tester.ensureVisible(alvo);
      await tester.pumpAndSettle();
      await tester.tap(alvo);
      await tester.pumpAndSettle();
    }

    testWidgets('criar só com o nome', (tester) async {
      final saidas = await abrir(tester);

      final criar = tester.widget<SJButton>(
          find.widgetWithText(SJButton, 'CRIAR FASE'));
      expect(criar.onPressed, isNull, reason: 'sem nome não há fase');

      await tester.enterText(find.byType(EditableText).first, '  Recomeços ');
      await tester.pump();
      await tocar(tester, 'CRIAR FASE');

      expect(pedidos.single.method, 'POST');
      expect(jsonDecode(pedidos.single.body), {'name': 'Recomeços', 'color': 'accent'});
      expect(saidas, [true]);
    });

    testWidgets('deixar o fim em branco reabre a fase (manda null)',
        (tester) async {
      await abrir(tester, fase: _faculdade);

      // As duas datas têm o botão; o segundo é o da data de fim.
      final limpar = find.text('Deixar em branco');
      expect(limpar, findsNWidgets(2));
      await tester.ensureVisible(limpar.last);
      await tester.pumpAndSettle();
      await tester.tap(limpar.last);
      await tester.pump();
      await tocar(tester, 'SALVAR ALTERAÇÕES');

      expect(pedidos.single.method, 'PATCH');
      expect(pedidos.single.url.path, '/life-phases/b');
      expect(jsonDecode(pedidos.single.body), {'ended_at': null});
    });

    testWidgets('apagar pede confirmação e diz que as memórias ficam',
        (tester) async {
      final saidas = await abrir(tester, fase: _faculdade);

      await tocar(tester, 'Apagar esta fase');
      expect(pedidos, isEmpty, reason: 'o primeiro toque só pergunta');
      expect(find.textContaining('continuam onde estão'), findsOneWidget);

      await tocar(tester, 'APAGAR');
      expect(pedidos.single.method, 'DELETE');
      expect(saidas, [true]);
    });
  });

  group('a timeline com fases', () {
    late http.Client original;
    final pedidos = <Uri>[];

    setUp(() {
      pedidos.clear();
      Api.instance.debugSetToken('token');
    });
    tearDown(() => Api.instance.swapClient(original));

    void servidor({required List<Map<String, dynamic>> fases}) {
      original = Api.instance.swapClient(MockClient((req) async {
        pedidos.add(req.url);
        if (req.url.path == '/life-phases') {
          return _json(fases);
        }
        return _json(<dynamic>[]);
      }));
    }

    testWidgets('sem fase, nenhuma lente — a timeline é a de sempre',
        (tester) async {
      servidor(fases: const []);
      await tester.pumpWidget(const MaterialApp(home: TimelineScreen()));
      await tester.pumpAndSettle();
      expect(find.text('A vida toda'), findsNothing);
    });

    testWidgets('escolher a fase relê o álbum com o filtro e troca o vazio',
        (tester) async {
      servidor(fases: [_faseJson(_infancia)]);
      await tester.pumpWidget(const MaterialApp(home: TimelineScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Infância'));
      await tester.pumpAndSettle();

      final memorias = pedidos.where((u) => u.path == '/memories').toList();
      expect(memorias.first.queryParameters.containsKey('life_phase_id'), isFalse);
      expect(memorias.last.queryParameters['life_phase_id'], 'a');
      expect(find.text('Nada guardado nesta fase ainda.'), findsOneWidget,
          reason: 'vazio com lente é uma fase sem página, não um álbum vazio');
    });

    testWidgets('a fase da lente apagada noutra tela devolve a vida toda',
        (tester) async {
      servidor(fases: [_faseJson(_infancia)]);
      await tester.pumpWidget(const MaterialApp(home: TimelineScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Infância'));
      await tester.pumpAndSettle();

      PhaseStore.instance.debugSet(const []);
      await tester.pumpAndSettle();

      final ultima = pedidos.where((u) => u.path == '/memories').last;
      expect(ultima.queryParameters.containsKey('life_phase_id'), isFalse);
    });
  });

  group('editar jornada com fase', () {
    late http.Client original;
    final patches = <Map<String, dynamic>>[];

    setUp(() {
      patches.clear();
      Api.instance.debugSetToken('token');
      original = Api.instance.swapClient(MockClient((req) async {
        if (req.url.path == '/life-phases') return _json([_faseJson(_infancia)]);
        if (req.method == 'PATCH') {
          patches.add(jsonDecode(req.body) as Map<String, dynamic>);
        }
        return _json({
          'id': 'j1',
          'title': 'Mochilão',
          'status': 'draft',
          'is_private': true,
          'points_count': 0,
          'created_at': '2026-06-01T12:00:00Z',
          'life_phase_id': 'a',
          'points': <dynamic>[],
        });
      }));
    });
    tearDown(() => Api.instance.swapClient(original));

    testWidgets('abre na fase gravada; "Nenhuma" solta com null explícito',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const JourneyEditScreen(journeyId: 'j1'))),
            child: const Text('abrir'),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      final salvar = find.widgetWithText(SJButton, 'SALVAR ALTERAÇÕES');
      expect(tester.widget<SJButton>(salvar).onPressed, isNull,
          reason: 'abrir na fase gravada não é mudança');

      await tester.ensureVisible(find.text('Nenhuma'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nenhuma'));
      await tester.pump();
      await tester.ensureVisible(salvar);
      await tester.pumpAndSettle();
      await tester.tap(salvar);
      await tester.pumpAndSettle();

      expect(patches.single.keys, ['life_phase_id']);
      expect(patches.single['life_phase_id'], isNull);
    });
  });


  // A lente chegou à estante de jornadas, e quem cria com a lente ligada já
  // nasce na fase que estava olhando — senão o capítulo novo sumiria da lista
  // filtrada que a pessoa acabou de deixar.
  group('a estante de jornadas com fases', () {
    late http.Client original;
    final pedidos = <http.Request>[];

    setUp(() {
      pedidos.clear();
      Api.instance.debugSetToken('token');
      original = Api.instance.swapClient(MockClient((req) async {
        pedidos.add(req);
        if (req.url.path == '/life-phases') return _json([_faseJson(_infancia)]);
        if (req.method == 'POST' && req.url.path == '/journeys') {
          return _json({
            'id': 'j-nova',
            'title': 'Casa da avó',
            'status': 'draft',
            'is_private': true,
            'points_count': 0,
            'created_at': '2026-06-01T12:00:00Z',
          }, status: 201);
        }
        return _json(<dynamic>[]);
      }));
    });
    tearDown(() => Api.instance.swapClient(original));

    testWidgets('escolher a fase relê a estante com o filtro e troca o vazio',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: JourneysScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Infância'));
      await tester.pumpAndSettle();

      final listas = pedidos.where((r) => r.url.path == '/journeys' && r.method == 'GET');
      expect(listas.first.url.queryParameters.containsKey('life_phase_id'), isFalse);
      expect(listas.last.url.queryParameters['life_phase_id'], 'a');
      expect(find.text('Nenhuma jornada nesta fase ainda.'), findsOneWidget);
    });

    testWidgets('jornada nova aberta com a fase já escolhida', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: const JourneyNewScreen(initialPhaseId: 'a'),
        onGenerateRoute: (s) => MaterialPageRoute(
          settings: s,
          builder: (_) => const Scaffold(body: Text('detalhe')),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText).first, 'Casa da avó');
      final criar = find.text('CRIAR JORNADA');
      await tester.ensureVisible(criar);
      await tester.pumpAndSettle();
      await tester.tap(criar);
      await tester.pumpAndSettle();

      final post = pedidos.singleWhere((r) => r.method == 'POST');
      expect(jsonDecode(post.body)['life_phase_id'], 'a');
    });
  });
}
