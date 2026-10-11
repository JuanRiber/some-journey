// A capa da jornada, do cliente até a tela de edição.
//
// Por que este teste existe: a capa era o único campo da jornada que o app
// DESENHAVA sem nunca ter sabido escrever. `journeys.dart` já mostrava
// `cover_image_url` com espera e saída de erro, as rotas
// `POST/DELETE /journeys/{id}/cover` já estavam no ar e cobertas no backend — e
// nenhum cliente as chamava. Na prática o campo só podia chegar nulo, e a
// metade bonita da lista era código que nunca rodava.
//
// O que fica travado aqui: o caminho e o método de cada chamada (errar a rota
// responderia 404, que a tela traduz como "jornada não encontrada" — mensagem
// que mente), o nome do campo multipart que o backend lê (`file`), a jornada
// devolvida com a URL assinada (é ela que a tela passa a mostrar, sem segunda
// leitura) e a classificação da falha, que decide se o app oferece "tentar de
// novo" ou pede outra foto.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/screens/journey_edit.dart';

/// Começo de um JPEG de verdade: o backend decide o tipo pelos magic bytes do
/// conteúdo, não pelo mime que o cliente promete.
const _jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0x30, 0x30, 0x30, 0x30];

const _comCapa = {
  'id': 'j1',
  'title': 'Mochilão',
  'description': 'Três meses de estrada',
  'mood': 'leve',
  'status': 'active',
  'is_private': true,
  'points_count': 3,
  'created_at': '2026-06-01T12:00:00Z',
  'cover_image_url': 'https://assinada.exemplo/j1/capa.jpg',
  'points': <dynamic>[],
};

const _semCapa = {
  'id': 'j1',
  'title': 'Mochilão',
  'description': 'Três meses de estrada',
  'mood': 'leve',
  'status': 'active',
  'is_private': true,
  'points_count': 3,
  'created_at': '2026-06-01T12:00:00Z',
  'cover_image_url': null,
  'points': <dynamic>[],
};

http.Response _json(Object corpo, [int status = 200]) => http.Response(
      jsonEncode(corpo),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  late http.Client original;
  final chamadas = <http.Request>[];

  setUp(() {
    chamadas.clear();
    Api.instance.debugSetToken('token-de-teste');
  });

  tearDown(() => Api.instance.swapClient(original));

  /// Registra cada requisição e responde o que [resposta] disser.
  void servir(http.Response Function(http.Request) resposta) {
    original = Api.instance.swapClient(MockClient((req) async {
      chamadas.add(req);
      return resposta(req);
    }));
  }

  /// O corpo multipart carrega bytes binários: `req.body` tentaria decodificar
  /// em UTF-8 e estouraria. latin1 nunca falha e preserva os cabeçalhos da
  /// parte, que é o que interessa ler.
  String corpoLegivel(http.Request req) => latin1.decode(req.bodyBytes);

  /// Roda [acao] esperando que ela falhe, e devolve o erro.
  Future<ApiError> erroAo(Future<void> Function() acao) async {
    try {
      await acao();
      fail('a chamada deveria ter falhado');
    } on ApiError catch (e) {
      return e;
    }
  }

  group('cliente', () {
    test('definir a capa é um POST multipart na rota da jornada', () async {
      servir((_) => _json(_comCapa));

      final jornada = await Api.instance
          .setJourneyCover('j1', _jpeg, 'capa.jpg', 'image/jpeg');

      expect(chamadas, hasLength(1));
      final req = chamadas.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/journeys/j1/cover');
      expect(req.headers['authorization'], 'Bearer token-de-teste');
      expect(req.headers['content-type'], startsWith('multipart/form-data'));
      final corpo = corpoLegivel(req);
      expect(corpo, contains('name="file"'),
          reason: 'o backend lê o campo `file`; outro nome vira 422');
      expect(corpo, contains('filename="capa.jpg"'));
      expect(corpo, contains('content-type: image/jpeg'));
      expect(jornada.coverImageUrl, 'https://assinada.exemplo/j1/capa.jpg',
          reason: 'a URL assinada vem na resposta — a tela não relê a jornada');
    });

    test('remover a capa é um DELETE na mesma rota', () async {
      servir((_) => _json(_semCapa));

      final jornada = await Api.instance.removeJourneyCover('j1');

      expect(chamadas.single.method, 'DELETE');
      expect(chamadas.single.url.path, '/journeys/j1/cover');
      expect(chamadas.single.headers['authorization'], 'Bearer token-de-teste');
      expect(jornada.coverImageUrl, isNull);
    });

    test('remover devolve a capa automática quando o rastro tem foto', () async {
      // Sem capa própria o backend volta ao fallback (primeira foto do rastro).
      // Quem assumisse `null` depois do DELETE mostraria um buraco onde ainda
      // existe imagem.
      servir((_) => _json(_comCapa));

      final jornada = await Api.instance.removeJourneyCover('j1');

      expect(jornada.coverImageUrl, 'https://assinada.exemplo/j1/capa.jpg');
    });

    test('tipo recusado é falha de requisição, com o texto do servidor',
        () async {
      servir((_) => _json(
          {'detail': 'Unsupported image type. Use JPEG, PNG or WebP.'}, 400));

      final erro = await erroAo(() =>
          Api.instance.setJourneyCover('j1', _jpeg, 'capa.gif', 'image/gif'));

      expect(erro.kind, ApiFailure.request);
      expect(erro.isOutage, isFalse,
          reason: 'trocar a foto é com a pessoa; "tentar de novo" não resolve');
      expect(erro.message, contains('Unsupported image type'));
    });

    test('servidor fora do ar no upload é indisponibilidade', () async {
      servir((_) => http.Response('<html>502 Bad Gateway</html>', 502,
          headers: {'content-type': 'text/html'}));

      final erro = await erroAo(() =>
          Api.instance.setJourneyCover('j1', _jpeg, 'capa.jpg', 'image/jpeg'));

      expect(erro.kind, ApiFailure.unavailable);
      expect(erro.isOutage, isTrue);
      expect(erro.message, isNot(contains('html')),
          reason: 'página de proxy não é notícia para quem usa o app');
    });

    test('capa grande demais é recusada como requisição, não como queda',
        () async {
      servir((_) => _json({'detail': 'Image too large.'}, 413));

      final erro = await erroAo(() =>
          Api.instance.setJourneyCover('j1', _jpeg, 'capa.jpg', 'image/jpeg'));

      expect(erro.kind, ApiFailure.request);
      expect(erro.status, 413);
    });
  });

  group('tela de edição', () {
    /// Abre a edição empilhada. A lista devolvida recebe, quando a tela sair, o
    /// valor que ela entrega ao detalhe.
    Future<List<Object?>> abrir(WidgetTester tester) async {
      final aoVoltar = <Object?>[];
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              aoVoltar.add(await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const JourneyEditScreen(journeyId: 'j1'),
              )));
            },
            child: const Text('abrir'),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return aoVoltar;
    }

    /// A superfície de teste (800x600) é menor que a tela real: o que está
    /// abaixo da dobra precisa ser trazido para dentro antes do toque.
    Future<void> tocar(WidgetTester tester, Finder alvo) async {
      await tester.ensureVisible(alvo);
      await tester.pumpAndSettle();
      await tester.tap(alvo);
      await tester.pumpAndSettle();
    }

    final voltar = find.byIcon(Icons.arrow_back);

    testWidgets('com capa, a tela oferece trocar e remover', (tester) async {
      servir((_) => _json(_comCapa));

      await abrir(tester);

      expect(find.text('Trocar capa'), findsOneWidget);
      expect(find.text('Remover'), findsOneWidget);
    });

    testWidgets('sem capa, não há o que remover', (tester) async {
      servir((_) => _json(_semCapa));

      await abrir(tester);

      expect(find.text('Escolher capa'), findsOneWidget);
      expect(find.text('Remover'), findsNothing,
          reason: 'botão aceso para uma ação que não faz nada é promessa falsa');
    });

    testWidgets('remover chama a rota da capa e a tela acompanha',
        (tester) async {
      servir((req) => _json(req.method == 'DELETE' ? _semCapa : _comCapa));

      await abrir(tester);
      await tocar(tester, find.text('Remover'));

      final apagou = chamadas.where((r) => r.method == 'DELETE');
      expect(apagou, hasLength(1));
      expect(apagou.single.url.path, '/journeys/j1/cover');
      expect(find.text('Remover'), findsNothing,
          reason: 'a tela mostra a jornada que o servidor devolveu');
      expect(find.text('Escolher capa'), findsOneWidget);
    });

    testWidgets('voltar depois de mexer na capa pede recarga ao detalhe',
        (tester) async {
      // O detalhe só recarrega quando a edição devolve `true`, e a capa não
      // passa pelo PATCH: sem este aviso, quem só trocou a foto continuaria
      // vendo a antiga.
      servir((req) => _json(req.method == 'DELETE' ? _semCapa : _comCapa));

      final aoVoltar = await abrir(tester);
      await tocar(tester, find.text('Remover'));
      await tocar(tester, voltar);

      expect(aoVoltar.single, isTrue);
    });

    testWidgets('voltar sem tocar na capa não pede recarga', (tester) async {
      servir((_) => _json(_comCapa));

      final aoVoltar = await abrir(tester);
      await tocar(tester, voltar);

      expect(aoVoltar.single, isFalse,
          reason: 'abrir e sair não pode custar uma requisição ao detalhe');
    });
  });
}
