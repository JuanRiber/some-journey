// A abertura de um capítulo: o que a pessoa vê e o que ela pode fazer.
//
// A tela antiga tinha, na jornada em curso, três botões cheios do mesmo peso —
// e o primeiro deles encerrava o capítulo. As memórias eram linhas de
// administração, sem foto, com subir/descer/tirar sempre à vista. Estes testes
// seguram o que mudou: UMA ação principal por estado, o roteiro ilustrado, a
// arrumação recolhida atrás de "Organizar", e os estados de espera e de erro
// no vocabulário do design system (nada de widget cru do Material).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/design/components.dart';
import 'package:some_journey/design/tokens.dart';
import 'package:some_journey/screens/journey_detail.dart';
import 'package:some_journey/widgets/atlas_map.dart';

Map<String, dynamic> _ponto(String id, int posicao, {String titulo = 'Parada'}) => {
      'memory_id': id,
      'position': posicao,
      'title': titulo,
      'text': '',
      'latitude': 38.71,
      'longitude': -9.13,
      'occurred_at': '2019-03-0${posicao}T12:00:00Z',
      'created_at': '2019-03-0${posicao}T12:00:00Z',
      'place_label': 'Lisboa',
    };

Map<String, dynamic> _memoria(
  String id, {
  String titulo = 'Parada',
  String texto = '',
  List<String> fotos = const [],
}) =>
    {
      'id': id,
      'title': titulo,
      'text': texto,
      'latitude': 38.71,
      'longitude': -9.13,
      'occurred_at': '2019-03-02T12:00:00Z',
      'created_at': '2019-03-02T12:00:00Z',
      'images': [
        for (var i = 0; i < fotos.length; i++) {'id': '$id-$i', 'url': fotos[i]},
      ],
      'music': <dynamic>[],
      'image_url': fotos.isEmpty ? null : fotos.first,
      'place_label': 'Lisboa',
    };

http.Response _json(Object corpo, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  late http.Client anterior;

  /// Cada pedido que SAIU, na ordem.
  late List<http.Request> pedidos;

  /// A jornada como o servidor a tem agora. As ações mexem nela.
  late Map<String, dynamic> jornada;
  late List<Map<String, dynamic>> memorias;

  /// Resposta forçada para a leitura da jornada (erro), quando o teste quer.
  http.Response? Function()? aoLer;
  var sessao = 0;

  Map<String, dynamic> nova({
    String status = 'active',
    List<Map<String, dynamic>> pontos = const [],
    String? capa,
  }) =>
      {
        'id': 'j1',
        'title': 'Lisboa, um semestre',
        'description': 'Seis meses de intercâmbio.',
        'mood': 'saudade em azulejo',
        'is_private': true,
        'cover_image_url': capa,
        'status': status,
        'started_at': '2019-02-10T12:00:00Z',
        'ended_at': status == 'finished' ? '2019-07-20T12:00:00Z' : null,
        'created_at': '2019-02-10T12:00:00Z',
        'points_count': pontos.length,
        'points': pontos,
        'route': null,
      };

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    pedidos = [];
    memorias = [];
    jornada = nova();
    aoLer = null;
    // Uma sessão por teste: o que um teste leu não fica na mão do seguinte.
    Api.instance.debugSetToken('abertura-${sessao++}');
    anterior = Api.instance.swapClient(MockClient((r) async {
      pedidos.add(r);
      final caminho = r.url.path;
      if (caminho.endsWith('/map')) {
        return _json({'journey': jornada, 'tracks': <String, dynamic>{}, 'distance_m': 0});
      }
      if (caminho.endsWith('/tracks')) return _json(<dynamic>[]);
      if (caminho.endsWith('/memories')) return _json(memorias);
      if (r.method == 'POST') {
        const transicoes = {
          'start': 'active',
          'pause': 'paused',
          'resume': 'active',
          'finish': 'finished',
        };
        final acao = caminho.split('/').last;
        if (transicoes.containsKey(acao)) jornada['status'] = transicoes[acao];
        return _json(jornada);
      }
      if (r.method == 'PATCH' && caminho.endsWith('/points/reorder')) {
        final ordem = (jsonDecode(r.body)['memory_ids'] as List).cast<String>();
        final porId = {
          for (final p in jornada['points'] as List) p['memory_id'] as String: p
        };
        jornada['points'] = [
          for (var i = 0; i < ordem.length; i++)
            {...porId[ordem[i]] as Map<String, dynamic>, 'position': i + 1},
        ];
        return _json(jornada);
      }
      if (r.method == 'DELETE') {
        if (caminho.contains('/points/')) {
          final id = caminho.split('/').last;
          (jornada['points'] as List).removeWhere((p) => p['memory_id'] == id);
        }
        return http.Response('', 204);
      }
      return aoLer?.call() ?? _json(jornada);
    }));
  });

  tearDown(() {
    Api.instance.swapClient(anterior);
    Api.instance.debugSetToken(null);
  });

  /// A superfície é ALTA de propósito: a página é uma lista preguiçosa, e num
  /// celular de verdade o roteiro só é montado quando se rola até ele. Aqui
  /// interessa o que a página TEM, não o que cabe acima da dobra.
  Future<void> abrir(WidgetTester tester, {Size tamanho = const Size(390, 2800)}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = tamanho;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: const JourneyDetailScreen(journeyId: 'j1'),
      onGenerateRoute: (s) => MaterialPageRoute<void>(
        settings: s,
        builder: (_) => Scaffold(body: Text('ROTA ${s.name} ${s.arguments}')),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Os botões CHEIOS que estão na tela, pelo rótulo.
  List<String> cheios(WidgetTester tester) => [
        for (final b in tester.widgetList<SJButton>(find.byType(SJButton)))
          if (b.variant == SJButtonVariant.primary) b.label,
      ];

  Iterable<String> saidos(String metodo) =>
      pedidos.where((r) => r.method == metodo).map((r) => r.url.path);

  group('uma ação principal por estado', () {
    testWidgets('em curso: guardar uma memória lidera; pausar e finalizar são links',
        (tester) async {
      jornada = nova(status: 'active');
      await abrir(tester);

      // A ação principal é o "+" flutuante: está na tela sem rolar, e é a
      // única peça cheia — nenhum botão disputa com ela.
      expect(find.byType(SJFab), findsOneWidget);
      expect(find.bySemanticsLabel('Nova memória nesta jornada'), findsWidgets);
      expect(cheios(tester), isEmpty);
      // Links não gritam: não vêm em caixa alta.
      expect(find.text('Pausar'), findsOneWidget);
      expect(find.text('Finalizar jornada'), findsOneWidget);
      expect(find.text('FINALIZAR'), findsNothing);
      // Gravar o percurso existe, e é apoio.
      expect(find.text('GRAVAR PERCURSO'), findsOneWidget);
    });

    testWidgets('em curso: os dois links ficam lado a lado, à esquerda',
        (tester) async {
      jornada = nova(status: 'active');
      // Largura folgada (ainda de coluna): a fonte de teste é bem mais larga
      // que a Inter, e num celular estreito os dois links quebrariam só aqui.
      await abrir(tester, tamanho: const Size(700, 2800));

      final pausar = tester.getRect(find.text('Pausar'));
      final finalizar = tester.getRect(find.text('Finalizar jornada'));
      expect(pausar.center.dy, closeTo(finalizar.center.dy, 0.5));
      // A 700pt a coluna de leitura já recuou para a medida da folha: a
      // margem do texto é a sobra dividida por dois.
      expect(pausar.left, closeTo((700 - SJLayout.sheet) / 2, 0.5),
          reason: 'o texto do link alinha com a margem do resto da página');
    });

    testWidgets('em curso: o "+" abre a memória nova já dentro da jornada',
        (tester) async {
      jornada = nova(status: 'active');
      await abrir(tester);

      await tester.tap(find.byType(SJFab));
      await tester.pumpAndSettle();

      expect(find.text('ROTA /memory-new j1'), findsOneWidget);
    });

    testWidgets('rascunho: iniciar lidera, e a memória nova recua para apoio',
        (tester) async {
      jornada = nova(status: 'draft');
      await abrir(tester);

      expect(cheios(tester), ['Iniciar jornada']);
      expect(find.byType(SJFab), findsNothing,
          reason: 'quem lidera aqui é começar; dois cheios disputariam');
      expect(find.text('NOVA MEMÓRIA NESTA JORNADA'), findsOneWidget);
      expect(find.text('GRAVAR PERCURSO'), findsNothing,
          reason: 'capítulo que não começou não grava caminho');
    });

    testWidgets('em pausa: retomar lidera, finalizar é link', (tester) async {
      jornada = nova(status: 'paused');
      await abrir(tester);

      expect(cheios(tester), ['Retomar jornada']);
      expect(find.byType(SJFab), findsNothing);
      expect(find.text('Finalizar jornada'), findsOneWidget);
      expect(find.text('Pausar'), findsNothing);
    });

    testWidgets('concluída: nenhuma ação, e o capítulo não oferece memória nova',
        (tester) async {
      jornada = nova(status: 'finished');
      await abrir(tester);

      expect(cheios(tester), isEmpty);
      expect(find.byType(SJFab), findsNothing);
      expect(find.text('NOVA MEMÓRIA NESTA JORNADA'), findsNothing);
      expect(find.text('Trazer uma memória que já existe'), findsNothing);
      expect(find.text('CONCLUÍDA'), findsOneWidget);
    });

    testWidgets('pausar vai ao servidor e a tela passa a oferecer retomar',
        (tester) async {
      jornada = nova(status: 'active');
      await abrir(tester);

      await tester.tap(find.text('Pausar'));
      await tester.pumpAndSettle();

      expect(saidos('POST'), ['/journeys/j1/pause']);
      expect(cheios(tester), ['Retomar jornada']);
      expect(find.text('EM PAUSA'), findsOneWidget);
    });

    testWidgets('o estado tem o mesmo nome que a estante dá', (tester) async {
      jornada = nova(status: 'active');
      await abrir(tester);

      expect(find.text('EM CURSO'), findsOneWidget);
      expect(find.text('ATIVA'), findsNothing);
    });
  });

  group('a abertura', () {
    testWidgets('conta o capítulo numa frase, com o que a pessoa escreveu',
        (tester) async {
      jornada = nova(
        status: 'finished',
        pontos: [_ponto('a', 1), _ponto('b', 2)],
      );
      await abrir(tester);

      expect(find.text('2 momentos registrados, entre fevereiro e julho de 2019.'),
          findsOneWidget);
      expect(find.text('Seis meses de intercâmbio.'), findsOneWidget);
      expect(find.text('saudade em azulejo'), findsOneWidget);
      expect(find.text('FEVEREIRO — JULHO DE 2019'), findsOneWidget);
    });

    testWidgets('com capa, o nome vai na tinta de foto; sem capa, na do tema',
        (tester) async {
      jornada = nova(capa: 'https://x.test/capa.jpg?token=1');
      await abrir(tester);
      expect(
        tester.widget<Text>(find.text('Lisboa, um semestre')).style!.color,
        SJOnPhoto.ink,
      );

      Api.instance.debugSetToken('abertura-sem-capa');
      jornada = nova();
      await tester.pumpWidget(const SizedBox());
      await abrir(tester);
      expect(
        tester.widget<Text>(find.text('Lisboa, um semestre')).style!.color,
        sjLight.ink,
      );
    });
  });

  group('o roteiro', () {
    setUp(() {
      jornada = nova(
        status: 'finished',
        pontos: [
          _ponto('a', 1, titulo: 'Miradouro'),
          _ponto('b', 2, titulo: 'Sintra'),
        ],
      );
      memorias = [
        _memoria('a', titulo: 'Miradouro', fotos: [
          'https://x.test/a1.jpg?token=1',
          'https://x.test/a2.jpg?token=1',
        ]),
        _memoria('b', titulo: 'Sintra', texto: 'O palácio sumia\n e voltava.'),
      ];
    });

    testWidgets('com foto, a parada é um cartão de foto; sem, uma nota',
        (tester) async {
      await abrir(tester);

      expect(find.byType(SJPhotoCard), findsOneWidget);
      expect(find.text('Miradouro'), findsOneWidget);
      expect(find.text('02 MAR 2019'), findsOneWidget);
      // A memória guarda duas fotos, e a parada avisa.
      expect(find.bySemanticsLabel(RegExp('2 fotos')), findsOneWidget);

      expect(find.text('Sintra'), findsOneWidget);
      expect(find.text('O palácio sumia e voltava.'), findsOneWidget);
    });

    testWidgets('tocar numa parada abre a memória', (tester) async {
      await abrir(tester);

      await tester.ensureVisible(find.text('Sintra'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sintra'));
      await tester.pumpAndSettle();

      expect(find.text('ROTA /memory b'), findsOneWidget);
    });

    testWidgets('lida sem arrumação: nenhum controle de gestão à vista',
        (tester) async {
      await abrir(tester);

      expect(find.byIcon(Icons.arrow_upward), findsNothing);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text('Organizar'), findsOneWidget);
    });

    testWidgets('Organizar mostra os controles, e subir manda a ordem trocada',
        (tester) async {
      await abrir(tester);

      await tester.ensureVisible(find.text('Organizar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Organizar'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_upward), findsNWidgets(2));
      expect(find.text('Concluir'), findsOneWidget);
      expect(find.byType(SJPhotoCard), findsNothing,
          reason: 'arrumando, a parada vira uma linha');

      await tester.tap(find.bySemanticsLabel('Subir Sintra'));
      await tester.pumpAndSettle();

      final troca = pedidos.singleWhere((r) => r.method == 'PATCH');
      expect(troca.url.path, '/journeys/j1/points/reorder');
      expect(jsonDecode(troca.body)['memory_ids'], ['b', 'a']);
    });

    testWidgets('a primeira não sobe e a última não desce', (tester) async {
      await abrir(tester);
      await tester.ensureVisible(find.text('Organizar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Organizar'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Subir Miradouro'));
      await tester.tap(find.bySemanticsLabel('Descer Sintra'));
      await tester.pumpAndSettle();

      expect(saidos('PATCH'), isEmpty);
    });

    testWidgets('tirar da jornada desvincula a memória, sem apagá-la',
        (tester) async {
      await abrir(tester);
      await tester.ensureVisible(find.text('Organizar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Organizar'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Tirar Sintra desta jornada'));
      await tester.pumpAndSettle();

      expect(saidos('DELETE'), ['/journeys/j1/points/b']);
      expect(find.text('Sintra'), findsNothing);
      expect(find.text('Miradouro'), findsOneWidget);
    });

    testWidgets('arrumando, a memória sem título é chamada pela data',
        (tester) async {
      jornada = nova(pontos: [_ponto('a', 1, titulo: ''), _ponto('b', 2)]);
      memorias = [];
      await abrir(tester);
      await tester.ensureVisible(find.text('Organizar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Organizar'));
      await tester.pumpAndSettle();

      expect(find.text('01 MAR 2019'), findsOneWidget);
      expect(find.bySemanticsLabel('Descer 01 MAR 2019'), findsOneWidget);
    });

    testWidgets('memórias que não chegam deixam o roteiro inteiro, sem foto',
        (tester) async {
      memorias = [];
      await abrir(tester);

      expect(find.byType(SJPhotoCard), findsNothing);
      expect(find.text('Miradouro'), findsOneWidget);
      expect(find.text('Sintra'), findsOneWidget);
    });
  });

  group('capítulo em branco', () {
    testWidgets('aberto: ensina o primeiro passo e deixa os dois caminhos',
        (tester) async {
      jornada = nova(status: 'active');
      await abrir(tester);

      expect(find.text('Guarde o primeiro momento.'), findsOneWidget);
      expect(find.text('Na ordem do rastro'), findsNothing,
          reason: 'sem memória não há seção para intitular');
      expect(find.text('NOVA MEMÓRIA NESTA JORNADA'), findsOneWidget);
      expect(find.text('Trazer uma memória que já existe'), findsOneWidget);
      expect(find.text('Organizar'), findsNothing);
    });

    testWidgets('concluído: só o fato, sem convite que não pode ser aceito',
        (tester) async {
      jornada = nova(status: 'finished');
      await abrir(tester);

      expect(find.text('Este capítulo fechou sem memórias.'), findsOneWidget);
      expect(find.text('NOVA MEMÓRIA NESTA JORNADA'), findsNothing);
    });

    testWidgets('o botão do fim do roteiro também leva o id da jornada',
        (tester) async {
      jornada = nova(status: 'draft');
      await abrir(tester);

      await tester.ensureVisible(find.text('NOVA MEMÓRIA NESTA JORNADA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NOVA MEMÓRIA NESTA JORNADA'));
      await tester.pumpAndSettle();

      expect(find.text('ROTA /memory-new j1'), findsOneWidget);
    });
  });

  group('quando não abre', () {
    testWidgets('sem conexão e nada na mão: a notícia e um jeito de tentar',
        (tester) async {
      var fora = true;
      aoLer = () => fora ? _json({'detail': 'x'}, 503) : null;
      await abrir(tester);

      expect(find.text('O servidor está fora do ar.'), findsOneWidget);
      expect(find.text('Lisboa, um semestre'), findsNothing);

      fora = false;
      await tester.tap(find.text('TENTAR DE NOVO'));
      await tester.pumpAndSettle();

      expect(find.text('Lisboa, um semestre'), findsOneWidget);
      expect(find.text('O servidor está fora do ar.'), findsNothing);
    });

    testWidgets('jornada que não existe mais: diz isso e oferece a volta',
        (tester) async {
      aoLer = () => _json({'detail': 'Jornada não encontrada.'}, 404);
      await abrir(tester);

      expect(find.text('Este capítulo não está mais aqui.'), findsOneWidget);
      expect(find.text('TENTAR DE NOVO'), findsNothing,
          reason: 'repetir não traz de volta o que foi excluído');
      expect(find.text('VOLTAR'), findsOneWidget);
    });

    testWidgets('releitura que falha com a jornada na tela não a apaga',
        (tester) async {
      jornada = nova(status: 'active');
      await abrir(tester);
      expect(find.text('Lisboa, um semestre'), findsOneWidget);

      aoLer = () => _json({'detail': 'x'}, 503);
      await tester.tap(find.text('Pausar'));
      await tester.pumpAndSettle();

      expect(find.text('Lisboa, um semestre'), findsOneWidget);
      expect(find.textContaining('fora do ar'), findsOneWidget,
          reason: 'o aviso fica junto das ações, não no lugar da página');
    });
  });

  group('excluir', () {
    testWidgets('pede confirmação, e a ação em destaque é a que não destrói',
        (tester) async {
      jornada = nova(status: 'finished');
      await abrir(tester);

      await tester.ensureVisible(find.text('Excluir jornada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir jornada'));
      await tester.pumpAndSettle();

      expect(find.text('Excluir esta jornada? As memórias não são apagadas.'),
          findsOneWidget);
      expect(cheios(tester), ['Manter jornada']);

      await tester.tap(find.text('MANTER JORNADA'));
      await tester.pumpAndSettle();
      expect(saidos('DELETE'), isEmpty);
      expect(find.text('Excluir jornada'), findsOneWidget);
    });

    testWidgets('confirmar apaga no servidor', (tester) async {
      jornada = nova(status: 'finished');
      await abrir(tester);

      await tester.ensureVisible(find.text('Excluir jornada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir jornada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SIM, EXCLUIR'));
      await tester.pumpAndSettle();

      expect(saidos('DELETE'), ['/journeys/j1']);
    });
  });

  group('duas composições', () {
    setUp(() => jornada = nova(
          status: 'finished',
          pontos: [_ponto('a', 1), _ponto('b', 2)],
        ));

    testWidgets('celular: o mapa é uma prancha dentro da página', (tester) async {
      await abrir(tester, tamanho: const Size(390, 844));

      final mapa = tester.widget<AtlasMap>(find.byType(AtlasMap));
      expect(mapa.framed, isTrue);
      expect(mapa.height, 300);
    });

    testWidgets('tela larga: o mapa sangra e o capítulo é uma folha sobre ele',
        (tester) async {
      await abrir(tester, tamanho: const Size(1440, 900));

      final mapa = tester.widget<AtlasMap>(find.byType(AtlasMap));
      expect(mapa.framed, isFalse);
      expect(mapa.height, isNull);
      expect(tester.getSize(find.byType(AtlasMap)), const Size(1440, 900));
      // A câmera enquadra o rastro no que a folha deixa à vista.
      expect(mapa.covered.left, greaterThan(SJLayout.sheet));

      // A folha tem largura fixa: o texto não estica com a janela.
      final titulo = tester.getRect(find.text('Lisboa, um semestre'));
      expect(titulo.right, lessThan(SJSpace.x6 + SJLayout.sheet));
    });

    testWidgets('tablet em pé: a capa sangra, o texto fica na medida de leitura',
        (tester) async {
      await abrir(tester, tamanho: const Size(768, 2800));

      // Ainda é coluna (abaixo do corte), e o mapa é prancha.
      expect(tester.widget<AtlasMap>(find.byType(AtlasMap)).framed, isTrue);
      // O texto não acompanha a largura do tablet…
      final texto = tester.getRect(find.text('Seis meses de intercâmbio.'));
      expect(texto.left, closeTo((768 - SJLayout.sheet) / 2, 0.5));
      // …a capa vai de borda a borda…
      expect(tester.getSize(find.byType(SJCover)).width, 768);
      // …e voltar continua junto da borda da tela.
      expect(tester.getRect(find.byIcon(Icons.arrow_back)).left,
          lessThan(SJSpace.x10));
    });

    testWidgets('o corte é o mesmo do login', (tester) async {
      await abrir(tester, tamanho: const Size(899, 900));
      expect(tester.widget<AtlasMap>(find.byType(AtlasMap)).framed, isTrue);

      Api.instance.debugSetToken('abertura-no-corte');
      await tester.pumpWidget(const SizedBox());
      await abrir(tester, tamanho: const Size(900, 900));
      expect(tester.widget<AtlasMap>(find.byType(AtlasMap)).framed, isFalse);
    });
  });

  group('dentro do design system', () {
    testWidgets('nenhum widget cru do Material, em nenhum estado',
        (tester) async {
      void semMaterialCru() {
        expect(find.byType(ElevatedButton), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(find.byType(IconButton), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }

      // Carregando, sem nada na mão.
      jornada = nova(status: 'active', pontos: [_ponto('a', 1), _ponto('b', 2)]);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 2800);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          const MaterialApp(home: JourneyDetailScreen(journeyId: 'j1')));
      semMaterialCru();
      expect(find.bySemanticsLabel('Carregando a jornada'), findsOneWidget);

      // Carregada, lendo.
      await tester.pumpAndSettle();
      semMaterialCru();

      // Arrumando.
      await tester.ensureVisible(find.text('Organizar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Organizar'));
      await tester.pumpAndSettle();
      semMaterialCru();
    });
  });
}
