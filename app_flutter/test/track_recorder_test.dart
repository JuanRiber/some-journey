// Coreografia da gravação: permissão, abertura do trecho, lotes, falha de rede
// e encerramento. GPS falso e cliente HTTP falso — o caminho real da API é
// exercitado, sem sair do lugar e sem servidor de pé.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/features/tracks/location_source.dart';
import 'package:some_journey/features/tracks/track_domain.dart';
import 'package:some_journey/features/tracks/track_recorder.dart';

final _t0 = DateTime.utc(2026, 8, 28, 12, 0, 0);
const _grau11m = 0.0001;

/// GPS de mentira: entrega o que o teste mandar, quando mandar.
class FakeLocation implements LocationSource {
  FakeLocation({this.denial});
  final LocationDenial? denial;
  final _ctrl = StreamController<TrackSample>.broadcast();
  var permissaoPedida = false;

  @override
  Future<void> ensurePermission() async {
    permissaoPedida = true;
    if (denial != null) throw LocationUnavailable(denial!);
  }

  @override
  Stream<TrackSample> watch(SamplingPolicy policy) => _ctrl.stream;

  /// Emite uma leitura já boa o bastante para o domínio aceitar.
  void mover(int passo) => _ctrl.add(TrackSample(
        latitude: -3.73 + _grau11m * 2 * passo,
        longitude: -38.52,
        accuracy: 4,
        recordedAt: _t0.add(Duration(seconds: passo * 10)),
      ));

  Future<void> fechar() => _ctrl.close();
}

/// Servidor de mentira. Registra o que recebeu e deixa o teste mandar falhar.
class FakeServer {
  final List<String> rotas = [];
  final List<List<dynamic>> lotes = [];
  bool falharNosPontos = false;

  /// Simula "já existe um trecho aberto nesta jornada".
  bool conflitoNoStart = false;

  /// Simula queda de rede no encerramento.
  bool falharNoFinish = false;

  /// Trechos que a listagem devolve (para o encerramento do órfão).
  List<Map<String, dynamic>> abertos = const [];

  http.Client get client => MockClient((req) async {
        final p = req.url.path;
        rotas.add('${req.method} $p');
        if (p.endsWith('/tracks/start')) {
          if (conflitoNoStart) {
            return http.Response(
              '{"detail":"Journey already has an open track."}',
              409,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'id': 'track-1',
              'journey_id': 'j1',
              'source': 'gps_live',
              'started_at': '2026-08-28T12:00:00Z',
              'ended_at': null,
              'is_active': true,
              'point_count': 0,
              'distance_m': 0,
              'created_at': '2026-08-28T12:00:00Z',
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        if (p.endsWith('/points')) {
          if (falharNosPontos) return http.Response('{"detail":"caiu"}', 503);
          lotes.add(jsonDecode(req.body)['points'] as List);
          return http.Response('', 204);
        }
        if (req.method == 'GET' && p.endsWith('/tracks')) {
          return http.Response(jsonEncode(abertos), 200,
              headers: {'content-type': 'application/json'});
        }
        if (p.endsWith('/finish')) {
          if (falharNoFinish) return http.Response('{"detail":"sem rede"}', 503);
          return http.Response(
            jsonEncode({
              'id': 'track-1',
              'journey_id': 'j1',
              'source': 'gps_live',
              'started_at': '2026-08-28T12:00:00Z',
              'ended_at': '2026-08-28T12:30:00Z',
              'is_active': false,
              'point_count': 3,
              'distance_m': 66,
              'created_at': '2026-08-28T12:00:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"detail":"rota inesperada"}', 404);
      });
}

void main() {
  late http.Client anterior;
  late FakeServer server;

  setUp(() {
    server = FakeServer();
    anterior = Api.instance.swapClient(server.client);
    Api.instance.debugSetToken('token-de-teste');
  });
  tearDown(() => Api.instance.swapClient(anterior));

  TrackRecorder criar(FakeLocation gps, {int flushEvery = 3}) => TrackRecorder(
        journeyId: 'j1',
        source: gps,
        policy: SamplingPolicy.walking,
        flushEvery: flushEvery,
      );

  test('start pede permissão e abre o trecho', () async {
    final gps = FakeLocation();
    final r = criar(gps);

    await r.start();

    expect(gps.permissaoPedida, isTrue);
    expect(r.status, RecorderStatus.recording);
    expect(server.rotas.first, 'POST /journeys/j1/tracks/start');
    await gps.fechar();
    r.dispose();
  });

  test('permissão bloqueada vira mensagem acionável, não exceção', () async {
    final gps = FakeLocation(denial: LocationDenial.deniedForever);
    final r = criar(gps);

    await r.start();

    expect(r.status, RecorderStatus.error);
    expect(r.error, contains('ajustes do sistema'));
    expect(server.rotas, isEmpty, reason: 'sem permissão, nem abre trecho');
    r.dispose();
  });

  test('GPS desligado se explica de outro jeito', () async {
    final r = criar(FakeLocation(denial: LocationDenial.serviceDisabled));
    await r.start();
    expect(r.error, contains('desligada'));
    r.dispose();
  });

  test('sobe um lote ao completar o tamanho, e só então', () async {
    final gps = FakeLocation();
    final r = criar(gps, flushEvery: 3);
    await r.start();

    gps.mover(0);
    gps.mover(1);
    await Future<void>.delayed(Duration.zero);
    expect(server.lotes, isEmpty, reason: 'ainda não fechou o lote');

    gps.mover(2);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(server.lotes, hasLength(1));
    expect(server.lotes.single, hasLength(3));
    expect(r.pointCount, 3);
    expect(r.distanceMeters, greaterThan(0));
    await gps.fechar();
    r.dispose();
  });

  test('o ponto chega no formato do contrato', () async {
    final gps = FakeLocation();
    final r = criar(gps, flushEvery: 1);
    await r.start();
    gps.mover(0);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final ponto = server.lotes.single.single as Map<String, dynamic>;
    expect(ponto.keys, containsAll(['latitude', 'longitude', 'recorded_at']));
    expect(ponto['recorded_at'], endsWith('Z'), reason: 'recorded_at em UTC');
    expect(ponto['accuracy'], 4);
    await gps.fechar();
    r.dispose();
  });

  test('queda de rede não perde ponto — o lote volta para a fila', () async {
    final gps = FakeLocation();
    final r = criar(gps, flushEvery: 2);
    await r.start();

    server.falharNosPontos = true;
    gps.mover(0);
    gps.mover(1);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(server.lotes, isEmpty, reason: 'o envio falhou');
    expect(r.pendingCount, 2, reason: 'os pontos continuam na fila');

    // Rede volta e mais um ponto fecha o lote seguinte.
    server.falharNosPontos = false;
    gps.mover(2);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final enviados = server.lotes.expand((l) => l).length;
    expect(enviados, 3, reason: 'os três pontos chegaram, nenhum se perdeu');
    await gps.fechar();
    r.dispose();
  });

  test('stop sobe o que sobrou e encerra o trecho', () async {
    final gps = FakeLocation();
    final r = criar(gps, flushEvery: 100); // nunca fecha lote sozinho
    await r.start();
    gps.mover(0);
    gps.mover(1);
    await Future<void>.delayed(Duration.zero);
    expect(server.lotes, isEmpty);

    await r.stop();

    expect(server.lotes.expand((l) => l), hasLength(2),
        reason: 'o resto do buffer sobe ao encerrar');
    expect(server.rotas.last, 'POST /journeys/j1/tracks/track-1/finish');
    expect(r.status, RecorderStatus.idle);
    await gps.fechar();
    r.dispose();
  });

  test('encerra o trecho mesmo se o último envio falhar', () async {
    final gps = FakeLocation();
    final r = criar(gps, flushEvery: 100);
    await r.start();
    gps.mover(0);
    await Future<void>.delayed(Duration.zero);

    server.falharNosPontos = true;
    await r.stop();

    expect(server.rotas.last, contains('/finish'),
        reason: 'deixar o trecho aberto bloquearia a próxima gravação com 409');
    expect(r.status, RecorderStatus.idle);
    await gps.fechar();
    r.dispose();
  });

  test('leitura ruim não entra e o motivo fica visível', () async {
    final gps = FakeLocation();
    final r = criar(gps, flushEvery: 100);
    await r.start();
    gps.mover(0);
    await Future<void>.delayed(Duration.zero);

    // Mesma posição, um instante depois: é ruído de quem está parado.
    gps._ctrl.add(TrackSample(
      latitude: -3.73,
      longitude: -38.52,
      accuracy: 4,
      recordedAt: _t0.add(const Duration(seconds: 20)),
    ));
    await Future<void>.delayed(Duration.zero);

    expect(r.lastVerdict, SampleVerdict.stationary);
    expect(r.pointCount, 1, reason: 'parado não avança o percurso');
    await gps.fechar();
    r.dispose();
  });

  // ── Trechos que ficam abertos ─────────────────────────────────────────────
  //
  // O beco sem saída que estes testes fecham: sair da tela no meio da gravação
  // (ou perder a rede ao encerrar) deixava o trecho `is_active` no servidor, e
  // TODA gravação seguinte daquela jornada respondia 409 — sem nenhum controle
  // no app capaz de encerrá-lo.

  group('trecho que ficou aberto', () {
    test('o id não se perde quando o encerramento falha', () async {
      final fonte = FakeLocation();
      final r = TrackRecorder(journeyId: 'j1', source: fonte);
      await r.start();
      fonte.mover(1);
      await Future<void>.delayed(Duration.zero);

      server.falharNoFinish = true;
      await r.stop();

      expect(r.error, isNotEmpty, reason: 'a falha precisa ser visível');
      // Com a rede de volta, encerrar de novo tem de funcionar: se o id
      // tivesse sido esquecido, não haveria o que encerrar.
      server.falharNoFinish = false;
      await r.stop();
      expect(server.rotas.where((x) => x.endsWith('/finish')), hasLength(2));
      expect(r.status, RecorderStatus.idle);
    });

    test('409 ao iniciar é sinalizado como trecho órfão', () async {
      server.conflitoNoStart = true;
      final r = TrackRecorder(journeyId: 'j1', source: FakeLocation());

      await r.start();

      expect(r.status, RecorderStatus.error);
      expect(r.hasOrphanTrack, isTrue,
          reason: 'a tela precisa saber que existe uma saída');
      expect(r.error, contains('de antes'));
    });

    test('encerrar o órfão fecha os trechos ativos e destrava', () async {
      server.conflitoNoStart = true;
      server.abertos = [
        {
          'id': 'antigo',
          'journey_id': 'j1',
          'source': 'gps_live',
          'started_at': '2026-08-28T10:00:00Z',
          'ended_at': null,
          'is_active': true,
          'point_count': 9,
          'distance_m': 120,
          'created_at': '2026-08-28T10:00:00Z',
        }
      ];
      final r = TrackRecorder(journeyId: 'j1', source: FakeLocation());
      await r.start();

      await r.closeOrphanTrack();

      expect(server.rotas, contains('POST /journeys/j1/tracks/antigo/finish'));
      expect(r.status, RecorderStatus.idle);
      expect(r.error, isEmpty);
    });

    test('sair da tela encerra o trecho no servidor', () async {
      final fonte = FakeLocation();
      final r = TrackRecorder(journeyId: 'j1', source: fonte);
      await r.start();
      fonte.mover(1);
      await Future<void>.delayed(Duration.zero);

      r.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        server.rotas.any((x) => x.endsWith('/finish')),
        isTrue,
        reason: 'sem isto o trecho fica aberto e a próxima gravação dá 409',
      );
    });
  });
}
