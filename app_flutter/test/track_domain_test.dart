// Domínio da gravação de percurso: o que vira ponto e o que é ruído.
//
// Estes testes existem porque a diferença entre um percurso e um rabisco não é
// o GPS — é o filtro. Dá para simular caminhada, parada no semáforo, sinal ruim
// e relógio pulando sem sair da cadeira, e é assim que se sabe que o traço
// desenhado no mapa corresponde ao caminho que a pessoa fez.

import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/features/tracks/track_domain.dart';

final _t0 = DateTime.utc(2026, 8, 28, 12, 0, 0);

TrackSample _s(
  double lat,
  double lng, {
  int segundos = 0,
  double? precisao = 5,
}) =>
    TrackSample(
      latitude: lat,
      longitude: lng,
      accuracy: precisao,
      recordedAt: _t0.add(Duration(seconds: segundos)),
    );

/// ~0,0001 grau de latitude ≈ 11 m. Usado para montar deslocamentos plausíveis.
const _grau11m = 0.0001;

void main() {
  group('primeira leitura', () {
    test('é sempre aceita — não há com o que comparar', () {
      final r = TrackRecorderCore();
      expect(r.offer(_s(-3.73, -38.52)).accepted, isTrue);
      expect(r.acceptedCount, 1);
      expect(r.distanceMeters, 0, reason: 'um ponto só não percorreu nada');
    });

    test('mesmo imprecisa, se estiver dentro do teto', () {
      final r = TrackRecorderCore(policy: const SamplingPolicy(maxAccuracyMeters: 50));
      expect(r.offer(_s(-3.73, -38.52, precisao: 49)).accepted, isTrue);
    });
  });

  group('qualidade do sinal', () {
    test('leitura acima do teto de erro é descartada', () {
      final r = TrackRecorderCore(policy: const SamplingPolicy(maxAccuracyMeters: 50));
      final v = r.offer(_s(-3.73, -38.52, precisao: 120)).verdict;
      expect(v, SampleVerdict.inaccurate);
      expect(r.acceptedCount, 0, reason: 'sinal ruim não entra no percurso');
    });

    test('sem informação de precisão, a leitura é aproveitada', () {
      final r = TrackRecorderCore();
      expect(r.offer(_s(-3.73, -38.52, precisao: null)).accepted, isTrue);
    });
  });

  group('parado não é caminhada', () {
    test('oscilação do GPS parado não vira percurso nem distância', () {
      final r = TrackRecorderCore(policy: SamplingPolicy.walking);
      r.offer(_s(-3.7300, -38.5200));

      // Dez leituras num raio de poucos metros, como quem tomou um café.
      var recusados = 0;
      for (var i = 1; i <= 10; i++) {
        final o = r.offer(_s(
          -3.7300 + (i.isEven ? 0.00002 : -0.00002),
          -38.5200 + (i.isEven ? -0.00002 : 0.00002),
          segundos: i * 5,
        ));
        if (!o.accepted) recusados++;
      }

      expect(recusados, 10, reason: 'nenhuma delas é movimento');
      expect(r.acceptedCount, 1);
      expect(r.distanceMeters, 0,
          reason: 'ficar parado não pode inflar a distância');
    });

    test('o piso sobe junto com o erro da leitura', () {
      // Andou ~11 m, mas a leitura tem 30 m de incerteza: não dá para afirmar
      // que houve deslocamento.
      final r = TrackRecorderCore(policy: SamplingPolicy.walking);
      r.offer(_s(-3.73, -38.52, precisao: 30));
      final o = r.offer(_s(-3.73 + _grau11m, -38.52, segundos: 10, precisao: 30));
      expect(o.verdict, SampleVerdict.stationary);
    });

    test('com leitura precisa, o mesmo deslocamento conta', () {
      final r = TrackRecorderCore(policy: SamplingPolicy.walking);
      r.offer(_s(-3.73, -38.52, precisao: 4));
      final o = r.offer(_s(-3.73 + _grau11m, -38.52, segundos: 10, precisao: 4));
      expect(o.accepted, isTrue);
      expect(r.distanceMeters, closeTo(11, 2));
    });
  });

  group('ritmo', () {
    test('leitura antes do intervalo mínimo espera a próxima', () {
      final r = TrackRecorderCore(
        policy: const SamplingPolicy(minInterval: Duration(seconds: 10)),
      );
      r.offer(_s(-3.73, -38.52));
      final o = r.offer(_s(-3.73 + _grau11m * 10, -38.52, segundos: 3));
      expect(o.verdict, SampleVerdict.tooSoon);
    });

    test('carimbo repetido ou para trás é recusado', () {
      final r = TrackRecorderCore();
      r.offer(_s(-3.73, -38.52, segundos: 30));
      expect(r.offer(_s(-3.74, -38.53, segundos: 30)).verdict,
          SampleVerdict.outOfOrder);
      expect(r.offer(_s(-3.75, -38.54, segundos: 10)).verdict,
          SampleVerdict.outOfOrder,
          reason: 'relógio andando para trás não pode reordenar o traço');
    });
  });

  group('caminhada de verdade', () {
    test('acumula pontos e distância coerentes', () {
      final r = TrackRecorderCore(policy: SamplingPolicy.walking);
      for (var i = 0; i < 10; i++) {
        r.offer(_s(-3.73 + _grau11m * 2 * i, -38.52,
            segundos: i * 10, precisao: 4));
      }
      expect(r.acceptedCount, 10);
      // 9 trechos de ~22 m.
      expect(r.distanceMeters, closeTo(9 * 22, 15));
    });
  });

  group('lotes', () {
    test('pede envio ao completar o lote', () {
      final r = TrackRecorderCore(policy: SamplingPolicy.walking, flushEvery: 3);
      final pedidos = <bool>[];
      for (var i = 0; i < 3; i++) {
        pedidos.add(r
            .offer(_s(-3.73 + _grau11m * 2 * i, -38.52,
                segundos: i * 10, precisao: 4))
            .shouldFlush);
      }
      expect(pedidos, [false, false, true]);
    });

    test('drain entrega e esvazia', () {
      final r = TrackRecorderCore(policy: SamplingPolicy.walking);
      r.offer(_s(-3.73, -38.52, precisao: 4));
      r.offer(_s(-3.73 + _grau11m * 2, -38.52, segundos: 10, precisao: 4));

      final saiu = r.drain();
      expect(saiu, hasLength(2));
      expect(r.hasPending, isFalse);
      expect(r.acceptedCount, 2, reason: 'enviar não apaga o que foi percorrido');
    });

    test('falha de envio devolve os pontos na ordem, sem perder nada', () {
      final r = TrackRecorderCore(policy: SamplingPolicy.walking);
      r.offer(_s(-3.73, -38.52, precisao: 4));
      r.offer(_s(-3.73 + _grau11m * 2, -38.52, segundos: 10, precisao: 4));

      final tentativa = r.drain();
      r.restore(tentativa); // o envio falhou
      r.offer(_s(-3.73 + _grau11m * 4, -38.52, segundos: 20, precisao: 4));

      final agora = r.pending;
      expect(agora, hasLength(3), reason: 'nada se perdeu na queda de rede');
      expect(
        agora.map((p) => p.recordedAt).toList(),
        [_t0, _t0.add(const Duration(seconds: 10)), _t0.add(const Duration(seconds: 20))],
        reason: 'os pontos recuperados voltam ANTES dos novos',
      );
    });
  });

  test('reset começa um trecho limpo', () {
    final r = TrackRecorderCore(policy: SamplingPolicy.walking);
    r.offer(_s(-3.73, -38.52, precisao: 4));
    r.offer(_s(-3.73 + _grau11m * 2, -38.52, segundos: 10, precisao: 4));
    r.reset();

    expect(r.acceptedCount, 0);
    expect(r.distanceMeters, 0);
    expect(r.hasPending, isFalse);
    expect(r.lastAccepted, isNull);
    expect(r.offer(_s(-3.73, -38.52, segundos: 5)).accepted, isTrue,
        reason: 'sem memória do trecho anterior, a primeira leitura entra');
  });

  test('o ponto vai para a API no formato do contrato', () {
    final j = _s(-3.73, -38.52, precisao: 4.5).toJson();
    expect(j['latitude'], -3.73);
    expect(j['longitude'], -38.52);
    expect(j['accuracy'], 4.5);
    expect(j['recorded_at'], '2026-08-28T12:00:00.000Z',
        reason: 'recorded_at precisa ir em UTC — o backend exige aware');
  });
}
