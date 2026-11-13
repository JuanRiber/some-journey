// O contrato das fases entre o app e a API, com um servidor falso.
//
// A lente é um parâmetro de query, e o cursor de uma página filtrada só vale
// com o MESMO filtro — por isso os dois têm de sair juntos na mesma URL. E o
// vínculo vem em `life_phase_id`, que os modelos precisam ler, senão o
// seletor da edição abre sempre em "Nenhuma" e o próximo salvar SOLTA a fase.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/features/phases/phase_domain.dart';
import 'package:some_journey/models.dart';

http.Response _json(Object corpo, {int status = 200, Map<String, String>? headers}) =>
    http.Response(jsonEncode(corpo), status,
        headers: {'content-type': 'application/json', ...?headers});

const _mapaVazio = {'loose_points': <dynamic>[], 'journeys': <dynamic>[]};

void main() {
  late http.Client original;
  final pedidos = <http.Request>[];

  setUp(() {
    pedidos.clear();
    Api.instance.debugSetToken('token');
  });

  tearDown(() => Api.instance.swapClient(original));

  void responder(http.Response Function(http.Request) r) {
    original = Api.instance.swapClient(MockClient((req) async {
      pedidos.add(req);
      return r(req);
    }));
  }

  group('a lente na URL', () {
    test('listMemories leva a fase e o cursor juntos', () async {
      responder((_) => _json(<dynamic>[]));

      await Api.instance.listMemories(cursor: 'C=', phaseId: 'f1');

      final q = pedidos.single.url.queryParameters;
      expect(pedidos.single.url.path, '/memories');
      expect(q['life_phase_id'], 'f1');
      expect(q['cursor'], 'C=', reason: 'o padding do cursor sobrevive à codificação');
    });

    test('sem lente, a URL é a de sempre', () async {
      responder((req) =>
          req.url.path == '/map' ? _json(_mapaVazio) : _json(<dynamic>[]));

      await Api.instance.listMemories();
      await Api.instance.getMap();

      expect(pedidos[0].url.hasQuery, isFalse);
      expect(pedidos[1].url.toString(), endsWith('/map'));
    });

    test('getMap e listJourneys com lente', () async {
      responder((req) =>
          req.url.path == '/map' ? _json(_mapaVazio) : _json(<dynamic>[]));

      await Api.instance.getMap(phaseId: 'f1');
      await Api.instance.listJourneys(phaseId: 'f1');

      expect(pedidos[0].url.path, '/map');
      expect(pedidos[0].url.queryParameters, {'life_phase_id': 'f1'});
      expect(pedidos[1].url.path, '/journeys');
      expect(pedidos[1].url.queryParameters['life_phase_id'], 'f1');
    });
  });

  group('CRUD das fases', () {
    test('listPhases lê a lista; quem não tem nenhuma recebe []', () async {
      responder((_) => _json([
            {'id': 'f1', 'name': 'Infância', 'color': 'highlight'},
          ]));
      final fases = await Api.instance.listPhases();
      expect(fases.single.name, 'Infância');
      expect(fases.single.color, PhaseColor.highlight);
    });

    test('verbo e caminho de cada operação', () async {
      responder((req) => req.method == 'DELETE'
          ? http.Response('', 204)
          : _json({'id': 'f1', 'name': 'X', 'color': 'accent'},
              status: req.method == 'POST' ? 201 : 200));

      await Api.instance.createPhase({'name': 'X'});
      await Api.instance.updatePhase('f1', {'ended_at': null});
      await Api.instance.deletePhase('f1');

      expect(pedidos.map((r) => '${r.method} ${r.url.path}'), [
        'POST /life-phases',
        'PATCH /life-phases/f1',
        'DELETE /life-phases/f1',
      ]);
      // O null que reabre a fase tem de chegar como null, não sumir no caminho.
      expect(jsonDecode(pedidos[1].body), {'ended_at': null});
    });

    test('o 422 do backend chega com a frase pronta', () async {
      responder((_) => _json(
          {'detail': 'Uma fase não pode terminar antes de começar.'},
          status: 422));
      await expectLater(
        Api.instance.createPhase({'name': 'X'}),
        throwsA(isA<ApiError>().having(
            (e) => e.message, 'message', contains('terminar antes de começar'))),
      );
    });
  });

  group('os modelos leem o vínculo', () {
    test('Memory', () {
      final base = {
        'id': 'm1',
        'title': '',
        'text': '',
        'latitude': 0,
        'longitude': 0,
        'occurred_at': '2024-01-01T12:00:00Z',
        'created_at': '2024-01-01T12:00:00Z',
      };
      expect(Memory.fromJson({...base, 'life_phase_id': 'f1'}).lifePhaseId, 'f1');
      expect(Memory.fromJson(base).lifePhaseId, isNull,
          reason: 'resposta antiga, sem o campo, continua legível');
    });

    test('Journey e JourneyDetail', () {
      final base = {
        'id': 'j1',
        'title': 'Mochilão',
        'status': 'draft',
        'is_private': true,
        'points_count': 0,
        'created_at': '2024-01-01T12:00:00Z',
        'life_phase_id': 'f1',
      };
      expect(Journey.fromJson(base).lifePhaseId, 'f1');
      expect(
        JourneyDetail.fromJson({...base, 'points': <dynamic>[]}).lifePhaseId,
        'f1',
        reason: 'é o detalhe que a tela de edição lê',
      );
    });
  });
}
