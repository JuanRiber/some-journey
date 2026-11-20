// Os pontos de GPS que ainda não subiram sobrevivem ao app.
//
// O gravador envia o percurso em lotes. Entre um lote e outro — e durante todo
// o tempo em que a rede falhava — os pontos existiam só em memória: se o app
// morresse ali, o fim do percurso sumia e o traço simplesmente terminava
// antes. Agora cada ponto aceito é escrito no aparelho e só sai quando o
// servidor confirma.
//
// "O app morreu" aqui é literal: o gravador é abandonado sem `stop` nem
// `dispose`, e um gravador NOVO nasce sobre o mesmo armazenamento — que é o
// que acontece quando a pessoa reabre o app.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/features/tracks/location_source.dart';
import 'package:some_journey/features/tracks/track_domain.dart';
import 'package:some_journey/features/tracks/track_outbox.dart';
import 'package:some_journey/features/tracks/track_panel.dart';
import 'package:some_journey/features/tracks/track_recorder.dart';

final _t0 = DateTime.utc(2026, 8, 28, 12);

/// Um ponto a ~22 m do anterior, 10 s depois: o domínio aceita todos.
TrackSample _ponto(int passo) => TrackSample(
      latitude: -3.73 + 0.0002 * passo,
      longitude: -38.52,
      accuracy: 4,
      altitude: 12.5,
      recordedAt: _t0.add(Duration(seconds: passo * 10)),
    );

class GpsFalso implements LocationSource {
  final _ctrl = StreamController<TrackSample>.broadcast();

  @override
  Future<void> ensurePermission() async {}

  @override
  Stream<TrackSample> watch(SamplingPolicy policy) => _ctrl.stream;

  void mover(int passo) => _ctrl.add(_ponto(passo));
}

/// O aparelho, em memória: o que um gravador deixa, o próximo encontra.
class DiscoFalso implements TrackOutbox {
  final Map<String, PendingTrack> guardado = {};

  @override
  Future<PendingTrack?> load(String journeyId) async => guardado[journeyId];

  @override
  Future<void> save(
      String journeyId, String trackId, List<TrackSample> points) async {
    if (points.isEmpty) {
      guardado.remove(journeyId);
    } else {
      guardado[journeyId] =
          PendingTrack(trackId: trackId, points: List.of(points));
    }
  }

  @override
  Future<void> clear(String journeyId) async => guardado.remove(journeyId);

  int pontos(String journeyId) => guardado[journeyId]?.points.length ?? 0;
}

class Servidor {
  final rotas = <String>[];

  /// Os pontos que chegaram, por trecho.
  final recebidos = <String, List<dynamic>>{};

  /// 503 nos pontos: queda. 409: recusa (o trecho fechou).
  int? statusDosPontos;
  bool falharNoFinish = false;
  bool conflitoNoStart = false;
  var proximoTrecho = 1;

  /// Os trechos abertos, como `GET /tracks` os devolve.
  final abertos = <String>{};

  Map<String, dynamic> _trecho(String id, {required bool ativo}) => {
        'id': id,
        'journey_id': 'j1',
        'source': 'gps_live',
        'started_at': '2026-08-28T12:00:00Z',
        'ended_at': ativo ? null : '2026-08-28T12:30:00Z',
        'is_active': ativo,
        'point_count': 0,
        'distance_m': 0,
        'created_at': '2026-08-28T12:00:00Z',
      };

  http.Response _json(Object corpo, [int status = 200]) =>
      http.Response(jsonEncode(corpo), status,
          headers: {'content-type': 'application/json'});

  http.Client get client => MockClient((req) async {
        final p = req.url.path;
        rotas.add('${req.method} $p');
        final partes = p.split('/');
        if (p.endsWith('/tracks/start')) {
          if (conflitoNoStart) {
            return _json({'detail': 'Já existe um trecho aberto.'}, 409);
          }
          final id = 'trecho-${proximoTrecho++}';
          abertos.add(id);
          return _json(_trecho(id, ativo: true), 201);
        }
        if (p.endsWith('/points')) {
          final status = statusDosPontos;
          if (status != null) return _json({'detail': 'não deu'}, status);
          final id = partes[partes.length - 2];
          recebidos
              .putIfAbsent(id, () => [])
              .addAll(jsonDecode(req.body)['points'] as List);
          return http.Response('', 204);
        }
        if (p.endsWith('/finish')) {
          if (falharNoFinish) return _json({'detail': 'sem rede'}, 503);
          final id = partes[partes.length - 2];
          abertos.remove(id);
          return _json(_trecho(id, ativo: false));
        }
        if (req.method == 'GET' && p.endsWith('/tracks')) {
          return _json([for (final id in abertos) _trecho(id, ativo: true)]);
        }
        return _json({'detail': 'rota inesperada'}, 404);
      });

  int chegaram(String trecho) => recebidos[trecho]?.length ?? 0;
}

Future<void> _assentar() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late http.Client anterior;
  late Servidor servidor;
  late DiscoFalso disco;

  setUp(() {
    servidor = Servidor();
    disco = DiscoFalso();
    anterior = Api.instance.swapClient(servidor.client);
    Api.instance.debugSetToken('token-de-teste');
  });
  tearDown(() => Api.instance.swapClient(anterior));

  TrackRecorder gravador(GpsFalso gps, {int lote = 3}) => TrackRecorder(
        journeyId: 'j1',
        source: gps,
        flushEvery: lote,
        outbox: disco,
      );

  group('enquanto grava', () {
    test('o ponto aceito já está no aparelho antes de qualquer envio', () async {
      final gps = GpsFalso();
      final r = gravador(gps, lote: 100);
      await r.start();

      gps.mover(0);
      gps.mover(1);
      await _assentar();

      expect(servidor.chegaram('trecho-1'), 0, reason: 'o lote ainda não fechou');
      expect(disco.pontos('j1'), 2);
      expect(disco.guardado['j1']!.trackId, 'trecho-1',
          reason: 'sem o trecho, os pontos não teriam para onde ir depois');
    });

    test('lote confirmado sai do aparelho', () async {
      final gps = GpsFalso();
      final r = gravador(gps, lote: 3);
      await r.start();

      for (var i = 0; i < 4; i++) {
        gps.mover(i);
      }
      await _assentar();

      expect(servidor.chegaram('trecho-1'), 3);
      expect(disco.pontos('j1'), 1, reason: 'só o que ainda falta subir');
    });

    test('lote que falhou continua guardado, na ordem', () async {
      final gps = GpsFalso();
      final r = gravador(gps, lote: 2);
      await r.start();
      servidor.statusDosPontos = 503;

      for (var i = 0; i < 3; i++) {
        gps.mover(i);
      }
      await _assentar();

      expect(servidor.chegaram('trecho-1'), 0);
      expect(r.pendingCount, 3);
      final guardados = disco.guardado['j1']!.points;
      expect(guardados.map((p) => p.recordedAt),
          [for (var i = 0; i < 3; i++) _ponto(i).recordedAt]);
    });

    test('gravar de novo não herda o que era de um trecho já fechado', () async {
      disco.guardado['j1'] =
          PendingTrack(trackId: 'trecho-velho', points: [_ponto(0)]);
      final gps = GpsFalso();
      final r = gravador(gps, lote: 100);
      await _assentar();
      expect(r.savedPointCount, 1);

      await r.start();
      await _assentar();

      expect(disco.pontos('j1'), 0,
          reason: 'ponto de trecho fechado não tem para onde ir');
      expect(r.savedPointCount, 0);
    });
  });

  group('o app morreu no meio da gravação', () {
    /// Grava [n] pontos sem que nenhum suba, e abandona o gravador.
    Future<void> gravarEMorrer(int n) async {
      final gps = GpsFalso();
      final r = gravador(gps, lote: 100);
      await r.start();
      for (var i = 0; i < n; i++) {
        gps.mover(i);
      }
      await _assentar();
      // Sem stop, sem dispose: o processo simplesmente acabou.
      servidor.rotas.clear();
    }

    test('ao reabrir, o gravador sabe quantos pontos ficaram', () async {
      await gravarEMorrer(4);

      final novo = gravador(GpsFalso());
      await _assentar();

      expect(novo.savedPointCount, 4);
    });

    test('encerrar a gravação anterior sobe os pontos e fecha o trecho',
        () async {
      await gravarEMorrer(4);
      final novo = gravador(GpsFalso());
      await _assentar();

      await novo.closeOrphanTrack();

      expect(servidor.chegaram('trecho-1'), 4, reason: 'nenhum ponto se perdeu');
      expect(servidor.rotas, [
        'GET /journeys/j1/tracks',
        'POST /journeys/j1/tracks/trecho-1/points',
        'POST /journeys/j1/tracks/trecho-1/finish',
      ], reason: 'os pontos sobem ANTES de o trecho fechar');
      expect(disco.pontos('j1'), 0);
      expect(novo.savedPointCount, 0);
      expect(novo.status, RecorderStatus.idle);
    });

    test('a saída do 409 leva junto o que ficou guardado', () async {
      await gravarEMorrer(2);
      servidor.conflitoNoStart = true;
      final novo = gravador(GpsFalso());

      await novo.start();
      expect(novo.hasOrphanTrack, isTrue);
      await novo.closeOrphanTrack();

      expect(servidor.chegaram('trecho-1'), 2);
      expect(novo.hasOrphanTrack, isFalse);
    });

    test('sem rede, nada é fechado nem apagado — e tentar de novo funciona',
        () async {
      await gravarEMorrer(3);
      final novo = gravador(GpsFalso());
      await _assentar();
      servidor.statusDosPontos = 503;

      await novo.closeOrphanTrack();

      expect(novo.status, RecorderStatus.error);
      expect(servidor.rotas.where((r) => r.endsWith('/finish')), isEmpty,
          reason: 'fechar sem os pontos jogaria fora o fim do percurso');
      expect(disco.pontos('j1'), 3);

      servidor.statusDosPontos = null;
      await novo.closeOrphanTrack();

      expect(servidor.chegaram('trecho-1'), 3);
      expect(disco.pontos('j1'), 0);
      expect(novo.status, RecorderStatus.idle);
    });

    test('pontos que o servidor recusa não prendem a jornada', () async {
      await gravarEMorrer(3);
      final novo = gravador(GpsFalso());
      await _assentar();
      servidor.statusDosPontos = 409; // recusa: tentar de novo não muda nada

      await novo.closeOrphanTrack();

      expect(servidor.rotas.last, endsWith('/finish'));
      expect(disco.pontos('j1'), 0);
      expect(novo.status, RecorderStatus.idle);
    });

    test('trecho que já fechou por outro caminho: os pontos são descartados',
        () async {
      await gravarEMorrer(3);
      servidor.abertos.clear(); // encerrado noutro aparelho
      final novo = gravador(GpsFalso());
      await _assentar();

      await novo.closeOrphanTrack();

      expect(servidor.rotas, ['GET /journeys/j1/tracks']);
      expect(disco.pontos('j1'), 0);
      expect(novo.savedPointCount, 0);
    });

    test('muitos pontos sobem em lotes que o servidor aceita', () async {
      disco.guardado['j1'] = PendingTrack(
        trackId: 'trecho-1',
        points: [for (var i = 0; i < 1200; i++) _ponto(i)],
      );
      servidor.abertos.add('trecho-1');
      final novo = gravador(GpsFalso());

      await novo.closeOrphanTrack();

      expect(servidor.chegaram('trecho-1'), 1200);
      expect(servidor.rotas.where((r) => r.endsWith('/points')), hasLength(3),
          reason: 'o servidor aceita até 1000 pontos por requisição');
    });
  });

  group('encerrar', () {
    test('trecho fechado limpa o aparelho', () async {
      final gps = GpsFalso();
      final r = gravador(gps, lote: 100);
      await r.start();
      gps.mover(0);
      gps.mover(1);
      await _assentar();

      await r.stop();
      await _assentar();

      expect(servidor.chegaram('trecho-1'), 2);
      expect(disco.pontos('j1'), 0);
      expect(r.pendingCount, 0);
    });

    test('fechou sem conseguir enviar: não fica promessa de envio guardada',
        () async {
      final gps = GpsFalso();
      final r = gravador(gps, lote: 100);
      await r.start();
      gps.mover(0);
      await _assentar();
      servidor.statusDosPontos = 503;

      await r.stop();
      await _assentar();

      expect(r.status, RecorderStatus.idle);
      expect(disco.pontos('j1'), 0,
          reason: 'trecho fechado não recebe mais ponto');
    });

    test('sem rede nenhuma: os pontos ficam, e encerrar de novo os envia',
        () async {
      final gps = GpsFalso();
      final r = gravador(gps, lote: 100);
      await r.start();
      gps.mover(0);
      gps.mover(1);
      await _assentar();
      servidor.statusDosPontos = 503;
      servidor.falharNoFinish = true;

      await r.stop();
      await _assentar();

      expect(r.status, RecorderStatus.error);
      expect(disco.pontos('j1'), 2);

      servidor.statusDosPontos = null;
      servidor.falharNoFinish = false;
      await r.stop();
      await _assentar();

      expect(servidor.chegaram('trecho-1'), 2, reason: 'antes, eles se perdiam');
      expect(disco.pontos('j1'), 0);
      expect(r.status, RecorderStatus.idle);
    });
  });

  group('sair da tela gravando', () {
    test('sobe o que faltava, fecha o trecho e limpa o aparelho', () async {
      final gps = GpsFalso();
      final r = gravador(gps, lote: 100);
      await r.start();
      gps.mover(0);
      gps.mover(1);
      await _assentar();

      r.dispose();
      await _assentar();

      expect(servidor.chegaram('trecho-1'), 2,
          reason: 'antes, sair da tela fechava o trecho sem eles');
      expect(servidor.rotas.last, endsWith('/finish'));
      expect(disco.pontos('j1'), 0);
    });

    test('sem rede, o trecho fica aberto e os pontos ficam guardados',
        () async {
      final gps = GpsFalso();
      final r = gravador(gps, lote: 100);
      await r.start();
      gps.mover(0);
      await _assentar();
      servidor.statusDosPontos = 503;

      r.dispose();
      await _assentar();

      expect(servidor.rotas.where((x) => x.endsWith('/finish')), isEmpty);
      expect(disco.pontos('j1'), 1,
          reason: 'é o que "Encerrar a gravação anterior" vai enviar na volta');
    });
  });

  group('o painel', () {
    Future<void> abrir(WidgetTester tester, TrackRecorder r,
        {VoidCallback? aoEncerrar}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TrackPanel(recorder: r, onFinished: aoEncerrar ?? () {}),
        ),
      ));
      await tester.pump();
    }

    testWidgets('sem nada guardado, não fala de gravação interrompida',
        (tester) async {
      final r = gravador(GpsFalso());
      await abrir(tester, r);

      expect(find.textContaining('interrompida'), findsNothing);
      expect(find.text('ENVIAR E ENCERRAR'), findsNothing);
    });

    testWidgets('diz quantos pontos ficaram e oferece enviá-los',
        (tester) async {
      disco.guardado['j1'] = PendingTrack(
          trackId: 'trecho-1', points: [_ponto(0), _ponto(1), _ponto(2)]);
      servidor.abertos.add('trecho-1');
      var recarregou = false;
      final r = gravador(GpsFalso());
      await abrir(tester, r, aoEncerrar: () => recarregou = true);

      expect(find.textContaining('3 pontos do percurso ficaram neste aparelho'),
          findsOneWidget);

      // SJButton desenha o rótulo em maiúsculas.
      await tester.tap(find.text('ENVIAR E ENCERRAR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(servidor.chegaram('trecho-1'), 3);
      expect(recarregou, isTrue, reason: 'o mapa precisa ganhar o trecho');
      expect(find.textContaining('interrompida'), findsNothing);
    });
  });

  group('no aparelho (shared_preferences)', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    const caixa = PrefsTrackOutbox();

    test('o ponto volta igual ao que foi guardado', () async {
      await caixa.save('j1', 'trecho-1', [_ponto(0), _ponto(1)]);

      final lido = await caixa.load('j1');

      expect(lido!.trackId, 'trecho-1');
      expect(lido.points, hasLength(2));
      final p = lido.points.last;
      expect(p.latitude, _ponto(1).latitude);
      expect(p.longitude, _ponto(1).longitude);
      expect(p.accuracy, 4);
      expect(p.altitude, 12.5);
      expect(p.speed, isNull);
      expect(p.recordedAt, _ponto(1).recordedAt);
      expect(p.recordedAt.isUtc, isTrue,
          reason: 'é o que ordena o percurso no servidor');
    });

    test('cada jornada tem a sua caixa', () async {
      await caixa.save('j1', 'a', [_ponto(0)]);
      await caixa.save('j2', 'b', [_ponto(0), _ponto(1)]);

      expect((await caixa.load('j1'))!.points, hasLength(1));
      expect((await caixa.load('j2'))!.trackId, 'b');
    });

    test('lista vazia apaga', () async {
      await caixa.save('j1', 'a', [_ponto(0)]);
      await caixa.save('j1', 'a', const []);

      expect(await caixa.load('j1'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('conteúdo ilegível vale como vazio, sem lançar', () async {
      SharedPreferences.setMockInitialValues({'sj_track_outbox_j1': '{cortado'});

      expect(await caixa.load('j1'), isNull);
    });

    test('sair da conta apaga os percursos pendentes, e só eles', () async {
      SharedPreferences.setMockInitialValues({'sj_theme_mode': 'dark'});
      await caixa.save('j1', 'a', [_ponto(0)]);
      await caixa.save('j2', 'b', [_ponto(0)]);

      await Api.instance.logout();

      expect(await caixa.load('j1'), isNull);
      expect(await caixa.load('j2'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sj_theme_mode'), 'dark');
    });
  });
}
