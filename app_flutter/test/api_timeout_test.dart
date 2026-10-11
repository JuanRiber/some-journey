// Quanto o cliente espera antes de desistir do servidor.
//
// Por que este teste existe: a API roda no plano free do Render, que desliga a
// instância ociosa, e o teto de espera era 20s. Como o próprio Render avisa que
// a primeira requisição depois da pausa "pode atrasar as requisições em 50
// segundos ou mais", esses 20s não eram um limite — eram a certeza de que quem
// abrisse o app depois de um tempo ia ler "O servidor demorou a responder",
// todas as vezes, com o servidor inteiro e já subindo. Medimos 0,39s com ele
// quente e 90s sem um byte com ele fora.
//
// Os dois lados da fronteira importam, e por motivos diferentes: encurtar
// demais devolve o bug; alargar sem fim troca o erro por um spinner eterno.
// Então aqui se fixa que o que chega dentro do teto é ENTREGUE e o que passa
// dele vira ApiError com kind timeout — nunca offline, que é outra notícia.
//
// O relógio é falso de propósito: provar um teto de 75s esperando 75s de
// verdade seria uma suíte inutilizável.

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/models.dart';

/// O que o Render avisa no painel sobre a primeira requisição depois da
/// ociosidade. É o piso que o teto do cliente tem de cobrir.
const _coldStartAvisado = Duration(seconds: 50);

/// A API quente, medida em produção.
const _respostaQuente = Duration(milliseconds: 390);

void main() {
  late http.Client original;

  setUp(() => Api.instance.debugSetToken('token-de-teste'));
  tearDown(() => Api.instance.swapClient(original));

  /// Instala um servidor que existe, responde 200 — e só depois de [atraso].
  ///
  /// É o formato exato do cold start: ninguém recusa a conexão, ninguém devolve
  /// erro; a resposta simplesmente demora porque o contêiner está subindo.
  void servidorQueDemora(Duration atraso) {
    original = Api.instance.swapClient(MockClient(
      (_) => Future.delayed(
        atraso,
        () => http.Response(jsonEncode(<dynamic>[]), 200,
            headers: {'content-type': 'application/json'}),
      ),
    ));
  }

  /// Dispara uma chamada sob o relógio falso e devolve o desfecho dela depois
  /// de [espera]: a página, o erro levantado, ou null se nada aconteceu ainda.
  Object? desfechoApos(Duration espera) {
    Object? desfecho;
    fakeAsync((relogio) {
      unawaited(() async {
        try {
          desfecho = await Api.instance.listJourneys();
        } on ApiError catch (e) {
          desfecho = e;
        }
      }());
      relogio.elapse(espera);
      relogio.flushMicrotasks();
    });
    return desfecho;
  }

  /// O mesmo, já exigindo que o desfecho tenha sido uma falha da API.
  ApiError erroApos(Duration espera) {
    final desfecho = desfechoApos(espera);
    expect(desfecho, isA<ApiError>(),
        reason: 'esperava uma falha, veio $desfecho');
    return desfecho as ApiError;
  }

  /// Folga para o relógio passar do evento que está sendo observado.
  const depois = Duration(seconds: 5);

  group('o que chega dentro do teto', () {
    test('o servidor quente responde na hora, como sempre respondeu', () {
      servidorQueDemora(_respostaQuente);

      expect(desfechoApos(_respostaQuente + depois), isA<Page<Journey>>());
    });

    test('o cold start que o Render avisa não derruba mais a primeira tela', () {
      // O caso que motivou a mudança: 50s é o número do painel do Render, e com
      // o teto de 20s esta chamada falhava SEMPRE — servidor são, resposta a
      // caminho, erro na tela.
      servidorQueDemora(_coldStartAvisado);

      expect(desfechoApos(_coldStartAvisado + depois), isA<Page<Journey>>(),
          reason: 'o teto precisa cobrir a instância subindo do zero');
    });

    test('uma resposta no último segundo ainda é entregue', () {
      servidorQueDemora(apiTimeout - const Duration(seconds: 1));

      expect(desfechoApos(apiTimeout + depois), isA<Page<Journey>>());
    });

    test('antes do teto, a chamada segue pendente em vez de falhar', () {
      servidorQueDemora(apiTimeout + const Duration(seconds: 30));

      expect(desfechoApos(apiTimeout - const Duration(seconds: 1)), isNull,
          reason: 'desistir antes da hora é o bug que se está corrigindo');
    });
  });

  group('o que passa do teto', () {
    test('vira ApiError, e não uma espera infinita', () {
      servidorQueDemora(apiTimeout + const Duration(seconds: 1));

      final e = erroApos(apiTimeout + depois);

      expect(e.status, 0, reason: 'não houve resposta para ter status');
      expect(e.message, contains('demorou'));
    });

    test('é classificado como timeout, não como offline', () {
      // A diferença é o que a tela diz: offline é "você está sem rede"; timeout
      // é "ele está demorando". Quem caísse no catch genérico viraria offline.
      servidorQueDemora(const Duration(minutes: 10));

      expect(erroApos(apiTimeout + depois).kind, ApiFailure.timeout);
    });

    test('o servidor que nunca responde ainda vale um "tentar de novo"', () {
      servidorQueDemora(const Duration(hours: 1));

      expect(erroApos(apiTimeout + depois).isOutage, isTrue,
          reason: 'a culpa não é do que a pessoa pediu');
    });
  });

  group('o teto escolhido', () {
    test('fica acima do cold start avisado pelo Render', () {
      expect(apiTimeout, greaterThan(_coldStartAvisado),
          reason: 'abaixo disso a primeira tela depois da pausa falha sempre');
    });

    test('sobra margem para o "ou mais" do aviso', () {
      // 50s é o começo da faixa que o Render descreve, não o fim. Encostar nele
      // deixaria o conserto valendo só no melhor caso.
      expect(apiTimeout - _coldStartAvisado, greaterThanOrEqualTo(const Duration(seconds: 20)));
    });

    test('não vira spinner sem fim', () {
      expect(apiTimeout, lessThanOrEqualTo(const Duration(minutes: 2)),
          reason: 'passou disso, a pessoa já foi embora');
    });

    test('o upload espera mais que uma leitura', () {
      // O relógio do upload cobre os bytes subindo, não só a espera pelo
      // servidor — e o cold start pode se somar a isso.
      expect(apiUploadTimeout, greaterThan(apiTimeout));
    });
  });
}
