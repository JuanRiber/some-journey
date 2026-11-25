// A estante de jornadas: o que vem primeiro, e o que ela faz quando a rede cai.
//
// A ordem era a de criação — um rascunho em branco abria a estante só por ter
// sido o último a nascer, e a jornada que a pessoa estava VIVENDO ficava no
// meio da lista. E qualquer releitura que falhasse trocava a estante inteira
// por "sem conexão", com o "+" de criar flutuando por cima do aviso.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/design/components.dart';
import 'package:some_journey/design/tokens.dart';
import 'package:some_journey/features/phases/phase_store.dart';
import 'package:some_journey/screens/journeys.dart';

Map<String, dynamic> _jornada(
  String id,
  String titulo,
  String status, {
  String? capa,
  int momentos = 2,
}) =>
    {
      'id': id,
      'title': titulo,
      'description': null,
      'mood': id == 'viva' ? 'vento e sal' : null,
      'is_private': true,
      'cover_image_url': capa,
      'status': status,
      'started_at': status == 'draft' ? null : '2026-10-30T12:00:00Z',
      'ended_at': status == 'finished' ? '2026-11-10T12:00:00Z' : null,
      'created_at': '2026-10-30T12:00:00Z',
      'points_count': momentos,
    };

http.Response _json(Object corpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  late http.Client anterior;
  late List<Map<String, dynamic>> estante;
  late bool fora;
  var sessao = 0;

  setUp(() {
    PhaseStore.instance.debugSet(const []);
    fora = false;
    // Na ordem em que a API devolve: a mais recente primeiro.
    estante = [
      _jornada('rascunho', 'Patagônia, um dia', 'draft', momentos: 0),
      _jornada('viva', 'Litoral do Ceará', 'active',
          capa: 'https://x.test/c1.jpg?token=1'),
      _jornada('lisboa', 'Lisboa, um semestre', 'finished',
          capa: 'https://x.test/c2.jpg?token=1'),
      _jornada('chapada', 'Chapada Diamantina', 'finished'),
    ];
    Api.instance.debugSetToken('estante-${sessao++}');
    anterior = Api.instance.swapClient(MockClient((r) async {
      if (r.url.path == '/life-phases') return _json(<dynamic>[]);
      if (r.method == 'DELETE') return http.Response('', 204);
      if (fora) return _json({'detail': 'x'}, 503);
      return _json(estante);
    }));
  });

  tearDown(() {
    Api.instance.swapClient(anterior);
    Api.instance.debugSetToken(null);
  });

  Future<void> abrir(WidgetTester tester, {Size tamanho = const Size(390, 844)}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = tamanho;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: const JourneysScreen(),
      onGenerateRoute: (s) => MaterialPageRoute<void>(
        settings: s,
        builder: (_) => Scaffold(body: Text('ROTA ${s.name} ${s.arguments}')),
      ),
    ));
    await tester.pumpAndSettle();
  }

  double altura(WidgetTester tester, String titulo) =>
      tester.getTopLeft(find.text(titulo)).dy;

  group('a ordem', () {
    testWidgets('o capítulo em curso abre a estante; o rascunho fecha',
        (tester) async {
      await abrir(tester, tamanho: const Size(390, 3000));

      final viva = altura(tester, 'Litoral do Ceará');
      final lisboa = altura(tester, 'Lisboa, um semestre');
      final chapada = altura(tester, 'Chapada Diamantina');
      final rascunho = altura(tester, 'Patagônia, um dia');

      expect(viva, lessThan(lisboa));
      expect(lisboa, lessThan(chapada), reason: 'entre as guardadas, a ordem da API');
      expect(chapada, lessThan(rascunho));
    });

    testWidgets('o capítulo em curso ganha a capa mais alta', (tester) async {
      await abrir(tester, tamanho: const Size(390, 3000));

      final capas = tester.widgetList<SJPhotoCard>(find.byType(SJPhotoCard));
      final viva = capas.firstWhere((c) => c.title == 'Litoral do Ceará');
      final lisboa = capas.firstWhere((c) => c.title == 'Lisboa, um semestre');
      // Proporção menor = mais alta para a mesma largura.
      expect(viva.aspectRatio, lessThan(lisboa.aspectRatio));
    });

    testWidgets('sem numeral: a posição na lista não numera capítulo nenhum',
        (tester) async {
      await abrir(tester, tamanho: const Size(390, 3000));

      for (final n in ['01', '02', '03', '04']) {
        expect(find.textContaining(RegExp('^$n\\b')), findsNothing);
      }
      // O que rotula a capa é o período do capítulo.
      expect(find.text('OUTUBRO — NOVEMBRO DE 2026'), findsWidgets);
    });

    testWidgets('tocar numa capa abre o capítulo', (tester) async {
      await abrir(tester, tamanho: const Size(390, 3000));

      await tester.tap(find.text('Lisboa, um semestre'));
      await tester.pumpAndSettle();

      expect(find.text('ROTA /journey lisboa'), findsOneWidget);
    });
  });

  group('quando a rede cai', () {
    testWidgets('releitura que falha deixa a estante na tela, com um aviso',
        (tester) async {
      await abrir(tester, tamanho: const Size(390, 3000));
      expect(find.text('Lisboa, um semestre'), findsOneWidget);

      // Algo foi gravado por este app: a estante relê sozinha — e a rede caiu.
      fora = true;
      await Api.instance.deleteMemory('qualquer');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Lisboa, um semestre'), findsOneWidget,
          reason: 'o que a pessoa estava lendo continua lá');
      expect(find.textContaining('Não deu para atualizar agora'), findsOneWidget);
      expect(find.text('O servidor está fora do ar.'), findsNothing);
      expect(find.byType(SJFab), findsOneWidget);
    });

    testWidgets('sem nada na mão, a notícia toma a página — e o "+" não aparece',
        (tester) async {
      fora = true;
      await abrir(tester);

      expect(find.text('O servidor está fora do ar.'), findsOneWidget);
      expect(find.byType(SJFab), findsNothing,
          reason: 'criar sem conexão é um convite a falhar de novo');

      fora = false;
      await tester.tap(find.text('TENTAR DE NOVO'));
      await tester.pumpAndSettle();
      expect(find.text('O servidor está fora do ar.'), findsNothing);
      expect(find.byType(SJFab), findsOneWidget);
    });
  });

  group('duas composições', () {
    testWidgets('celular: uma coluna, cada capa na largura da página',
        (tester) async {
      await abrir(tester, tamanho: const Size(390, 3000));

      final capa = tester.getSize(find.byType(SJPhotoCard).first);
      expect(capa.width, 390 - 2 * SJSpace.screenX);
      expect(find.text('CONTINUAR JORNADA'), findsNothing);
    });

    testWidgets('tela larga: nenhuma capa passa da altura da janela',
        (tester) async {
      await abrir(tester, tamanho: const Size(1440, 900));

      // A estante tem um teto e fica no meio.
      final esquerda = tester.getTopLeft(find.text('Jornadas')).dx;
      expect(esquerda, closeTo((1440 - SJLayout.page) / 2, 0.5));

      for (final capa in tester.widgetList<SJPhotoCard>(find.byType(SJPhotoCard))) {
        final tamanho = tester.getSize(find.byWidget(capa));
        expect(tamanho.height, lessThan(900 * 0.5),
            reason: '${capa.title}: a capa crescia com a janela');
      }
    });

    testWidgets('tela larga: o capítulo em curso vira uma faixa com a porta',
        (tester) async {
      await abrir(tester, tamanho: const Size(1440, 900));

      expect(find.text('CONTINUAR JORNADA'), findsOneWidget);
      expect(find.text('vento e sal'), findsOneWidget);
      // A faixa não é um cartão de foto esticado: o texto fica ao lado da capa.
      final faixa = tester.getSize(find
          .ancestor(
              of: find.text('CONTINUAR JORNADA'),
              matching: find.byType(SJPressable))
          .last);
      expect(faixa.width, SJLayout.page);

      await tester.tap(find.text('CONTINUAR JORNADA'));
      await tester.pumpAndSettle();
      expect(find.text('ROTA /journey viva'), findsOneWidget);
    });

    testWidgets('tela larga: as outras capas se arrumam em três por fileira',
        (tester) async {
      await abrir(tester, tamanho: const Size(1440, 900));

      final lisboa = tester.getRect(find.ancestor(
          of: find.text('Lisboa, um semestre'),
          matching: find.byType(SJPhotoCard)));
      final terco = (SJLayout.page - 2 * SJSpace.x6) / 3;
      expect(lisboa.width, closeTo(terco, 1));
    });
  });
}
