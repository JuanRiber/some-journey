// A foto da memória — o upload mais usado do app — visto de ponta a ponta.
//
// Por que este teste existe: havia dois envios multipart quase idênticos no
// cliente. Um passava pelo cliente injetável e por isso avatar e capa da
// jornada podiam ser testados; o outro, o das fotos da memória, chamava
// `req.send()`, que fabrica um cliente próprio lá dentro — fora do alcance de
// `swapClient`. O caminho mais percorrido do produto era justamente o único
// invisível, e a cópia garantia que qualquer conserto fosse aplicado pela
// metade. Os dois viraram um só, e o que segue é o que esse um precisa cumprir.
//
// O que fica travado aqui: a requisição sai PELO cliente injetável (se voltar a
// `req.send()`, nenhuma chamada é registrada e o teste cai), a rota e o método,
// o nome do campo multipart que o backend lê (`file`), a classificação de cada
// falha — que decide se a tela oferece "tentar de novo" ou pede outra foto — e
// o teto de espera, que é o do upload e não o de leitura.

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';

/// Começo de um JPEG de verdade: o backend decide o tipo pelos magic bytes do
/// conteúdo, não pelo mime que o cliente promete.
const _jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0x30, 0x30, 0x30, 0x30];

/// O que `POST /memories/{id}/images` devolve: a memória inteira (MemoryRead).
/// Quem anexa a foto descarta esse corpo — mas ele passa pelo decode do mesmo
/// jeito, e é por isso que ele aparece aqui como JSON de verdade.
const _memoria = {
  'id': 'm1',
  'title': 'Chegada',
  'text': 'O trem parou e a serra apareceu inteira.',
  'latitude': -3.73,
  'longitude': -38.52,
  'occurred_at': '2026-05-01T12:00:00Z',
  'created_at': '2026-05-01T12:00:00Z',
  'images': <dynamic>[],
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

  Future<void> anexar({String mime = 'image/jpeg', String nome = 'foto.jpg'}) =>
      Api.instance.addMemoryImage('m1', _jpeg, nome, mime);

  group('a foto sobe pelo cliente do app', () {
    test('é um POST multipart na rota de imagens da memória', () async {
      servir((_) => _json(_memoria));

      await anexar();

      expect(chamadas, hasLength(1),
          reason: 'nenhuma chamada registrada significa que o envio voltou a '
              'fabricar o próprio cliente, fora do alcance do teste');
      final req = chamadas.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/memories/m1/images');
      expect(req.headers['authorization'], 'Bearer token-de-teste');
      expect(req.headers['content-type'], startsWith('multipart/form-data'));
    });

    test('o arquivo viaja no campo que o backend lê', () async {
      servir((_) => _json(_memoria));

      await anexar(nome: 'serra.jpg');

      final corpo = corpoLegivel(chamadas.single);
      expect(corpo, contains('name="file"'),
          reason: 'o backend lê o campo `file`; outro nome vira 422');
      expect(corpo, contains('filename="serra.jpg"'));
      expect(corpo, contains('content-type: image/jpeg'));
      expect(corpo, contains(latin1.decode(_jpeg)),
          reason: 'os bytes da foto precisam chegar inteiros, não o nome dela');
    });

    test('a memória devolvida é descartada sem quebrar nada', () async {
      // O corpo é decodificado mesmo quando ninguém o lê. Uma resposta vazia
      // (204, ou um proxy que corta o corpo) não pode virar erro de parse.
      servir((_) => http.Response('', 200));

      await anexar();

      expect(chamadas, hasLength(1));
    });
  });

  group('o que fazer quando falha', () {
    test('tipo recusado é falha de requisição, com o texto do servidor',
        () async {
      servir((_) => _json(
          {'detail': 'Unsupported image type. Use JPEG, PNG or WebP.'}, 400));

      final erro = await erroAo(() => anexar(mime: 'image/gif', nome: 'f.gif'));

      expect(erro.kind, ApiFailure.request);
      expect(erro.isOutage, isFalse,
          reason: 'trocar a foto é com a pessoa; "tentar de novo" não resolve');
      expect(erro.message, contains('Unsupported image type'));
    });

    test('o teto de fotos por memória também é coisa de quem pede', () async {
      servir((_) => _json(
          {'detail': 'This memory already has the maximum number of photos.'},
          409));

      final erro = await erroAo(anexar);

      expect(erro.status, 409);
      expect(erro.kind, ApiFailure.request);
      expect(erro.isOutage, isFalse);
    });

    test('foto grande demais é recusa de requisição, não queda', () async {
      servir((_) => _json({'detail': 'Image too large.'}, 413));

      final erro = await erroAo(anexar);

      expect(erro.status, 413);
      expect(erro.kind, ApiFailure.request);
    });

    test('armazenamento fora do ar é indisponibilidade, e vale tentar de novo',
        () async {
      // 502 é o que a rota devolve quando o bucket não aceita o arquivo: o
      // pedido estava certo, a foto também — só não dá para guardar agora.
      servir((_) => http.Response('<html>502 Bad Gateway</html>', 502,
          headers: {'content-type': 'text/html'}));

      final erro = await erroAo(anexar);

      expect(erro.kind, ApiFailure.unavailable);
      expect(erro.isOutage, isTrue);
      expect(erro.message, isNot(contains('html')),
          reason: 'página de proxy não é notícia para quem usa o app');
    });

    test('conexão que nem sai vira offline', () async {
      original = Api.instance.swapClient(
          MockClient((_) async => throw http.ClientException('sem rota')));

      final erro = await erroAo(anexar);

      expect(erro.kind, ApiFailure.offline);
      expect(erro.status, 0, reason: 'não houve resposta para ter status');
    });
  });

  group('o relógio do upload', () {
    /// Um servidor que existe e responde 200 — só depois de [atraso]. É o
    /// formato do envio lento: ninguém recusa nada, os bytes é que estão
    /// subindo por um uplink ruim, e isso pode somar ao cold start.
    void servidorQueDemora(Duration atraso) {
      original = Api.instance.swapClient(MockClient(
        (req) => Future.delayed(atraso, () {
          chamadas.add(req);
          return _json(_memoria);
        }),
      ));
    }

    /// Anexa uma foto sob o relógio falso e devolve o desfecho depois de
    /// [espera]: `true` se subiu, o ApiError se falhou, null se segue pendente.
    ///
    /// O relógio é falso porque provar um teto de 3 minutos esperando 3 minutos
    /// de verdade tornaria a suíte inutilizável.
    Object? desfechoApos(Duration espera) {
      Object? desfecho;
      fakeAsync((relogio) {
        unawaited(() async {
          try {
            await anexar();
            desfecho = true;
          } on ApiError catch (e) {
            desfecho = e;
          }
        }());
        relogio.elapse(espera);
        relogio.flushMicrotasks();
      });
      return desfecho;
    }

    /// Folga para o relógio passar do evento que está sendo observado.
    const depois = Duration(seconds: 5);

    test('uma foto mais lenta que o teto de leitura ainda sobe', () {
      // O caso que separa os dois tetos: com [apiTimeout] aqui, este envio
      // seria cancelado quando estava indo bem — e a pessoa perderia a foto
      // por uma espera que o upload tem direito de gastar.
      servidorQueDemora(apiTimeout + const Duration(seconds: 30));

      expect(desfechoApos(apiTimeout + const Duration(seconds: 30) + depois),
          isTrue,
          reason: 'o envio de arquivo espera por [apiUploadTimeout]');
    });

    test('antes do teto do upload a foto segue subindo, sem erro', () {
      servidorQueDemora(apiUploadTimeout + const Duration(minutes: 10));

      expect(desfechoApos(apiUploadTimeout - const Duration(seconds: 1)), isNull,
          reason: 'desistir antes da hora é o que se está evitando');
    });

    test('passar do teto do upload vira timeout, com a notícia do upload', () {
      servidorQueDemora(apiUploadTimeout + const Duration(seconds: 1));

      final desfecho = desfechoApos(apiUploadTimeout + depois);

      expect(desfecho, isA<ApiError>());
      final erro = desfecho as ApiError;
      expect(erro.kind, ApiFailure.timeout,
          reason: 'offline diria "você está sem rede", que é outra conversa');
      expect(erro.message, contains('upload'),
          reason: 'quem mandou uma foto precisa saber que foi a foto que '
              'demorou, e não uma leitura qualquer');
    });
  });
}
