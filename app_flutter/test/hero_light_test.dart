// A iluminação do herói.
//
// O pedido do dono foi: "os ambientes devem interagir em questão de
// iluminação". Este arquivo transforma isso em aritmética — o campo é quente, a
// montanha é fria, no túnel sobra só o abajur, o entardecer é o ponto mais
// quente do ciclo. São afirmações que se verificam sem olhar para a tela.
//
// E travam a linha do alfa da matriz: se ela deixar de ser identidade, o
// recorte da janela fecha e a paisagem some atrás do vagão.

import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/features/hero/light_domain.dart';

void main() {
  const trilha = LightTrack.scenic;

  /// A amostra na zona de nome [nome], no ponto exato em que ela está cheia.
  LightSample naZona(String nome, [LightTrack t = trilha]) {
    final z = t.zones.firstWhere((z) => z.name == nome);
    return t.at(z.at);
  }

  group('a trilha existe e é bem formada', () {
    test('tem zonas suficientes para interpolar', () {
      expect(trilha.zones.length, greaterThanOrEqualTo(2));
    });

    test('as zonas estão em ordem crescente dentro de [0,1)', () {
      double? anterior;
      for (final z in trilha.zones) {
        expect(z.at, inInclusiveRange(0, 0.999999));
        if (anterior != null) expect(z.at, greaterThan(anterior));
        anterior = z.at;
      }
    });
  });

  group('o laço', () {
    test('fecha: o começo e o fim são o mesmo estado', () {
      expect(trilha.at(1.0), trilha.at(0.0));
    });

    test('não tem costura: a véspera do fim quase encosta no começo', () {
      final fim = trilha.at(0.999);
      final comeco = trilha.at(0.0);
      expect((fim.tint.r - comeco.tint.r).abs(), lessThan(4));
      expect((fim.tint.g - comeco.tint.g).abs(), lessThan(4));
      expect((fim.tint.b - comeco.tint.b).abs(), lessThan(4));
      expect((fim.exposure - comeco.exposure).abs(), lessThan(0.03));
    });

    test('envolve circularmente', () {
      expect(trilha.at(1.3).exposure, closeTo(trilha.at(0.3).exposure, 1e-9));
      expect(trilha.at(-0.1).exposure, closeTo(trilha.at(0.9).exposure, 1e-9));
    });

    test('é determinística — o mesmo ponto dá a mesma luz', () {
      expect(trilha.at(0.42), trilha.at(0.42));
    });
  });

  group('a exigência do dono, como especificação', () {
    test('o campo aberto ilumina QUENTE', () {
      expect(naZona('campo').warmth, greaterThan(0),
          reason: 'sol de meio-dia: mais vermelho que azul');
    });

    test('a montanha ESFRIA em relação ao campo', () {
      expect(naZona('montanha').warmth, lessThan(naZona('campo').warmth));
    });

    test('no túnel sobra só o abajur', () {
      final t = naZona('tunel-entrada');
      expect(t.exposure, lessThan(0.15),
          reason: 'quase nenhuma luz entra pela janela');
      expect(t.lamp, greaterThan(0.8),
          reason: 'a luminária assume — é a frase do dono, em número');
    });

    test('o entardecer é o ponto mais quente do ciclo', () {
      final entardecer = naZona('entardecer').warmth;
      for (var i = 0; i <= 200; i++) {
        expect(trilha.at(i / 200).warmth, lessThanOrEqualTo(entardecer + 1e-9));
      }
    });

    test('o abajur é inverso à luz de fora', () {
      // Quanto menos entra pela janela, mais a luminária pesa. Se esta relação
      // se inverter, o vagão acende quando devia escurecer.
      expect(naZona('tunel-entrada').lamp, greaterThan(naZona('campo').lamp));
      expect(naZona('campo').exposure, greaterThan(naZona('tunel-entrada').exposure));
    });

    test('o túnel também tira a cor do mundo', () {
      expect(naZona('tunel-entrada').saturation, lessThan(0.3));
      expect(naZona('campo').saturation, greaterThan(0.9));
    });
  });

  group('a transição', () {
    test('nenhum salto brusco ao varrer o ciclo', () {
      double? antes;
      for (var i = 0; i <= 400; i++) {
        final e = trilha.at(i / 400).exposure;
        if (antes != null) {
          expect((e - antes).abs(), lessThan(0.06),
              reason: 'um degrau aqui apareceria como piscada na tela');
        }
        antes = e;
      }
    });

    test('a entrada do túnel é abrupta, mas contínua', () {
      // Duas zonas quase coladas: a queda tem de ser rápida e ainda assim sem
      // degrau. Comparamos o trecho do túnel com um trecho calmo.
      final quedaTunel =
          (trilha.at(0.44).exposure - trilha.at(0.50).exposure).abs();
      final calmo = (trilha.at(0.10).exposure - trilha.at(0.16).exposure).abs();
      expect(quedaTunel, greaterThan(calmo),
          reason: 'entrar num túnel não é o mesmo que atravessar um campo');
    });

    test('nada estoura os limites declarados', () {
      for (var i = 0; i <= 400; i++) {
        final s = trilha.at(i / 400);
        expect(s.exposure, inInclusiveRange(0, 1.4));
        expect(s.saturation, inInclusiveRange(0, 1));
        expect(s.lamp, inInclusiveRange(0, 1));
        for (final c in [s.tint.r, s.tint.g, s.tint.b]) {
          expect(c, inInclusiveRange(0, 255));
        }
      }
    });
  });

  group('a matriz de cor', () {
    test('tem 20 posições', () {
      expect(trilha.at(0).colorMatrix, hasLength(20));
    });

    test('a linha do alfa é a identidade — a janela continua um buraco', () {
      for (var i = 0; i <= 20; i++) {
        final m = trilha.at(i / 20).colorMatrix;
        expect(m.sublist(15), [0, 0, 0, 1, 0],
            reason: 'mexer aqui fecha o recorte e some com a paisagem');
      }
    });

    test('nenhum ganho absurdo', () {
      for (var i = 0; i <= 40; i++) {
        for (final v in trilha.at(i / 40).colorMatrix) {
          expect(v.abs(), lessThan(30), reason: 'ganho estourado lava a arte');
        }
      }
    });

    test('aplicada a um cinza, esquenta no campo e esfria na montanha', () {
      double canal(List<double> m, int linha, double v) =>
          m[linha * 5] * v + m[linha * 5 + 1] * v + m[linha * 5 + 2] * v +
          m[linha * 5 + 4];

      const cinza = 128.0;
      final campo = naZona('campo').colorMatrix;
      final montanha = naZona('montanha').colorMatrix;

      expect(canal(campo, 0, cinza), greaterThan(canal(campo, 2, cinza)),
          reason: 'no campo o vermelho supera o azul');
      expect(canal(montanha, 2, cinza), greaterThan(canal(montanha, 0, cinza)),
          reason: 'na montanha o azul supera o vermelho');
    });
  });

  group('o atlas noturno', () {
    final noite = trilha.toNight();

    test('toda a viagem escurece', () {
      for (var i = 0; i <= 100; i++) {
        expect(noite.at(i / 100).exposure,
            lessThan(trilha.at(i / 100).exposure + 1e-9));
      }
    });

    test('o abajur nunca apaga à noite', () {
      for (final z in noite.zones) {
        expect(z.lamp, greaterThanOrEqualTo(0.6),
            reason: 'no escuro a luminária é a fonte principal');
      }
    });

    test('o laço continua fechando', () {
      expect(noite.at(1.0), noite.at(0.0));
    });

    test('preserva a ordem das zonas', () {
      expect(noite.zones.map((z) => z.name).toList(),
          trilha.zones.map((z) => z.name).toList());
    });
  });

  group('windowCenter', () {
    test('no início, o centro da janela é meia abertura adiante', () {
      expect(LightTrack.windowCenter(0, 0.3), closeTo(0.15, 1e-9));
    });

    test('envolve corretamente', () {
      expect(LightTrack.windowCenter(1 - 0.3 / 2, 0.3), closeTo(0, 1e-9));
      expect(LightTrack.windowCenter(-0.1, 0.2), closeTo(0.0, 1e-9));
    });
  });
}
