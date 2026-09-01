// O que o app diz quando a API não responde.
//
// Por que este teste existe: a tradução de erro do cliente HTTP nunca foi
// exercitada, e ela mentia de dois jeitos quando o servidor caía. Um 500 do
// FastAPI chega como {"detail":"Internal Server Error"} e ia inteiro para a
// tela — em inglês, para quem só queria ver o próprio álbum. E um 502, que é o
// que a borda devolve quando o contêiner não sobe, traz uma PÁGINA HTML no
// corpo: o parse falhava e sobrava "Erro inesperado (502)".
//
// Nada disso é notícia para uma pessoa. Estes testes fixam a fronteira: o texto
// do servidor vale em 4xx, onde a API escreve para quem usa o app; em 5xx a
// frase é nossa.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';

/// A página que um proxy devolve quando não há contêiner atrás dele.
const _htmlDoProxy = '<html><head><title>502 Bad Gateway</title></head>'
    '<body><center><h1>502 Bad Gateway</h1></center></body></html>';

void main() {
  late http.Client original;

  setUp(() => Api.instance.debugSetToken('token-de-teste'));
  tearDown(() => Api.instance.swapClient(original));

  /// Faz a API responder [r] a qualquer requisição.
  void responder(http.Response r) {
    original = Api.instance.swapClient(MockClient((_) async => r));
  }

  /// Faz o transporte falhar antes de qualquer resposta.
  void naoConectar() {
    original = Api.instance.swapClient(
        MockClient((_) async => throw http.ClientException('falhou')));
  }

  /// Dispara uma chamada qualquer e devolve o erro que ela levantou.
  Future<ApiError> erroAoListar() async {
    try {
      await Api.instance.listJourneys();
      fail('a chamada deveria ter falhado');
    } on ApiError catch (e) {
      return e;
    }
  }

  group('classificação por status', () {
    test('503 é indisponibilidade, não erro de requisição', () async {
      responder(http.Response('{"detail":"Service Unavailable"}', 503,
          headers: {'content-type': 'application/json'}));

      final e = await erroAoListar();

      expect(e.kind, ApiFailure.unavailable);
      expect(e.status, 503);
      expect(e.isOutage, isTrue);
    });

    test('502 e 504 contam como o servidor fora do ar', () async {
      for (final status in [502, 504]) {
        responder(http.Response(_htmlDoProxy, status));
        expect((await erroAoListar()).kind, ApiFailure.unavailable,
            reason: '$status é a borda de pé com o serviço fora');
      }
    });

    test('500 é quebra do servidor, e se separa da indisponibilidade', () async {
      responder(http.Response('{"detail":"Internal Server Error"}', 500,
          headers: {'content-type': 'application/json'}));

      final e = await erroAoListar();

      expect(e.kind, ApiFailure.serverError);
      expect(e.isOutage, isTrue);
    });

    test('4xx continua sendo falha da requisição', () async {
      responder(http.Response('{"detail":"Essa jornada já tem um trecho aberto."}', 409,
          headers: {'content-type': 'application/json'}));

      final e = await erroAoListar();

      expect(e.kind, ApiFailure.request);
      expect(e.isOutage, isFalse, reason: 'tentar de novo não resolve um 409');
    });

    test('sem conexão não tem status para classificar', () async {
      naoConectar();

      final e = await erroAoListar();

      expect(e.kind, ApiFailure.offline);
      expect(e.status, 0);
      expect(e.isOutage, isTrue);
    });
  });

  group('de quem é a frase', () {
    test('o texto do servidor sobrevive em 4xx', () async {
      responder(http.Response('{"detail":"Essa jornada já tem um trecho aberto."}', 409,
          headers: {'content-type': 'application/json'}));

      expect((await erroAoListar()).message, 'Essa jornada já tem um trecho aberto.');
    });

    test('"Internal Server Error" não chega na tela', () async {
      responder(http.Response('{"detail":"Internal Server Error"}', 500,
          headers: {'content-type': 'application/json'}));

      final e = await erroAoListar();

      expect(e.message, isNot(contains('Internal Server Error')));
      expect(e.message, contains('do nosso lado'));
    });

    test('a página HTML do proxy não vaza para a tela', () async {
      responder(http.Response(_htmlDoProxy, 502));

      final e = await erroAoListar();

      expect(e.message, isNot(contains('<html')));
      expect(e.message, isNot(contains('Bad Gateway')));
      expect(e.message, contains('fora do ar'));
    });
  });

  group('Retry-After', () {
    test('sem o header, a espera não é prometida', () async {
      responder(http.Response('', 503));

      final e = await erroAoListar();

      expect(e.retryAfter, isNull);
      expect(e.message, contains('em instantes'));
    });

    test('em segundos, vira a espera em palavras', () async {
      responder(http.Response('', 503, headers: {'retry-after': '120'}));

      final e = await erroAoListar();

      expect(e.retryAfter, const Duration(minutes: 2));
      expect(e.message, contains('em 2 minutos'));
    });

    test('um minuto não vira "1 minutos"', () async {
      responder(http.Response('', 503, headers: {'retry-after': '60'}));

      expect((await erroAoListar()).message, contains('em 1 minuto'));
    });

    test('uma data HTTP é ignorada em vez de virar promessa errada', () async {
      // O header também admite data, que não sabemos ler no alvo web. Ignorar
      // é o certo: um valor mal lido vira uma promessa falsa na tela.
      responder(http.Response('', 503,
          headers: {'retry-after': 'Wed, 31 Aug 2026 23:59:59 GMT'}));

      final e = await erroAoListar();

      expect(e.retryAfter, isNull);
      expect(e.message, contains('em instantes'));
    });
  });

  group('a classificação em si', () {
    test('o mapa de status para natureza da falha', () {
      expect(ApiError.kindOf(0), ApiFailure.offline);
      expect(ApiError.kindOf(401), ApiFailure.request);
      expect(ApiError.kindOf(422), ApiFailure.request);
      expect(ApiError.kindOf(500), ApiFailure.serverError);
      expect(ApiError.kindOf(502), ApiFailure.unavailable);
      expect(ApiError.kindOf(503), ApiFailure.unavailable);
      expect(ApiError.kindOf(504), ApiFailure.unavailable);
      expect(ApiError.kindOf(599), ApiFailure.serverError);
    });

    test('quem já levantava ApiError continua classificado', () {
      // Os pontos antigos passam só status e mensagem — a natureza sai do
      // status, e não de uma migração de todas as chamadas.
      expect(ApiError(401, 'sessão expirada').kind, ApiFailure.request);
      expect(ApiError(503, 'fora').kind, ApiFailure.unavailable);
    });

    test('timeout é dito explicitamente, porque não tem status', () {
      final e = ApiError(0, 'demorou', kind: ApiFailure.timeout);
      expect(e.kind, ApiFailure.timeout);
      expect(e.isOutage, isTrue);
    });
  });
}
