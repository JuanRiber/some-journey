// A cena do herói, em aritmética.
//
// O que se pede de uma animação dessas é quase todo negativo: que nada pule,
// que nada trema, que nada apareça do nada, que o laço não tenha emenda, que a
// bolha não atravesse o rosto do personagem, que a respiração não entorte o
// desenho. São coisas que um olho cansado deixa passar e que voltam no
// primeiro aparelho lento.
//
// Como a cena não tem quadros — é função do tempo —, cada uma dessas frases
// vira uma conta sobre o domínio, e roda aqui sem abrir a tela.

import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/features/hero/light_domain.dart';
import 'package:some_journey/features/hero/scene_domain.dart';

/// Um quadro a 60 por segundo.
const _quadro = 1 / 60;

/// Quantos pixels da arte uma camada andou na janela entre duas fases.
double _andou(StripLayer c, double de, double ate) {
  var d = c.at(ate, 0.5) - c.at(de, 0.5);
  d -= (d + 0.5).floorToDouble();
  return d.abs() * c.span / HeroTravel.aperture * HeroArtboard.glassWidth;
}

/// O passo de uma camada num quadro, em pixels da arte.
double _passo(StripLayer c) =>
    c.speed * HeroTravel.reference / HeroTravel.loopSeconds * _quadro;

void main() {
  const trilha = LightTrack.scenic;
  double faseDaZona(String nome) {
    final z = trilha.zones.firstWhere((z) => z.name == nome);
    // A fase em que o CENTRO da janela está em cima da zona.
    return (z.at - HeroTravel.aperture / 2) % 1.0;
  }

  group('as camadas e o atlas', () {
    // As medidas do atlas estão copiadas no domínio. Se a tira mudar de
    // largura e a camada não, a paisagem dá um tranco a cada volta — e nada
    // mais acusa.
    test('cada tira pintada tem a largura do ladrilho da camada que a rola', () {
      expect(HeroAtlas.clouds.width, HeroTravel.clouds.tile);
      expect(HeroAtlas.far.width, HeroTravel.far.tile);
      expect(HeroAtlas.valley.width, HeroTravel.valley.tile);
      expect(HeroAtlas.meadowBack.width, HeroTravel.meadowBack.tile);
      expect(HeroAtlas.meadow.width, HeroTravel.meadow.tile);
    });

    test('cada tira cobre a janela inteira, com folga', () {
      for (final c in HeroTravel.layers) {
        expect(c.tile, greaterThan(HeroArtboard.glassWidth * 1.3),
            reason: '${c.name}: a mesma coisa apareceria duas vezes na janela');
      }
    });

    test('nenhuma anda para trás, e o que está longe anda menos', () {
      for (final c in HeroTravel.layers) {
        expect(c.speed, greaterThan(0), reason: c.name);
        expect(c.skip, greaterThanOrEqualTo(0), reason: c.name);
      }
      final v = [for (final c in HeroTravel.layers) c.speed];
      for (var i = 1; i < v.length; i++) {
        expect(v[i], greaterThan(v[i - 1]),
            reason: '${HeroTravel.layers[i].name} devia passar mais depressa');
      }
    });

    test('as tiras vão do céu ao peitoril sem deixar buraco', () {
      // Cada tira começa acima de onde a anterior acaba.
      expect(HeroAtlas.valleyTop, lessThan(HeroAtlas.farTop + HeroAtlas.far.height));
      expect(HeroAtlas.meadowBackTop,
          lessThan(HeroAtlas.valleyTop + HeroAtlas.valley.height));
      expect(HeroAtlas.meadowTop,
          lessThan(HeroAtlas.meadowBackTop + HeroAtlas.meadowBack.height));
      expect(HeroAtlas.meadowTop + HeroAtlas.meadow.height,
          HeroArtboard.glassBottom);
    });

    test('o pixel da tira fica sempre dentro dela', () {
      for (final c in HeroTravel.layers) {
        for (var p = 0.0; p < 1; p += 0.0137) {
          expect(c.pixelAt(p), inInclusiveRange(0, c.tile), reason: c.name);
        }
      }
    });
  });

  group('o laço', () {
    test('toda camada anda um número inteiro de ladrilhos por ciclo', () {
      for (final c in HeroTravel.layers) {
        // Fase 1 É a fase 0: mesma posição, a menos de voltas inteiras.
        expect(_andou(c, 0.0, 1.0), closeTo(0, 1e-6), reason: c.name);
        expect(_andou(c, 0.25, 3.25), closeTo(0, 1e-6), reason: c.name);
        final d = (c.pixelAt(1.0) - c.pixelAt(0.0)).abs();
        expect(d < 1e-6 || (d - c.tile).abs() < 1e-6, isTrue, reason: c.name);
      }
    });

    test('não tem emenda: o último quadro encosta no primeiro', () {
      final fim = HeroTravel.phaseAt(HeroTravel.loopSeconds - _quadro / 2);
      final comeco = HeroTravel.phaseAt(HeroTravel.loopSeconds + _quadro / 2);
      for (final c in HeroTravel.layers) {
        final passo = _passo(c);
        expect(_andou(c, fim, comeco), closeTo(passo, passo * 0.05 + 1e-6),
            reason: c.name);
      }
    });

    test('o céu e a luz de fora também fecham', () {
      final a = HeroSky.at(0.0), b = HeroSky.at(1.0);
      expect(a.top, b.top);
      expect(a.horizon, b.horizon);
      expect(a.land, b.land);
      expect(a.clouds, b.clouds);
    });
  });

  group('nada pula', () {
    test('a paisagem só anda mais que o passo dela com a janela coberta', () {
      for (final c in HeroTravel.layers) {
        final passo = _passo(c);
        for (var t = 0.0; t < HeroTravel.loopSeconds; t += _quadro) {
          final de = HeroTravel.phaseAt(t), ate = HeroTravel.phaseAt(t + _quadro);
          final coberta = HeroTravel.darkness(de) == 1 &&
              HeroTravel.darkness(ate) == 1;
          if (coberta) continue;
          expect(_andou(c, de, ate), lessThan(passo * 1.02 + 1e-6),
              reason: '${c.name} em t=${t.toStringAsFixed(2)}s');
        }
      }
    });

    test('o salto das camadas distantes acontece inteiro no escuro', () {
      for (var p = 0.0; p < 1; p += 0.0005) {
        if (HeroTravel.darkness(p) == 1) continue;
        final h = HeroTravel.hidden(HeroTravel.center(p));
        expect(h == 0 || h == 1, isTrue,
            reason: 'a serra saltando à vista, na fase $p');
      }
    });

    test('e ele existe: do outro lado do túnel é outra paisagem', () {
      final antes = faseDaZona('tunel-entrada') - 0.03;
      final depois = faseDaZona('tunel-saida') + 0.03;
      for (final c in [HeroTravel.far, HeroTravel.clouds]) {
        final semSalto = (depois - antes) * c.speed / c.span;
        var d = c.at(depois, 0.5) - c.at(antes, 0.5);
        d -= d.floorToDouble();
        expect(d, greaterThan(semSalto + 0.2), reason: c.name);
      }
    });

    test('a viagem parte do campo aberto da ilustração', () {
      // Com o centro da janela no começo da trilha, a serra e as nuvens estão
      // onde o script da arte as pôs para refazer a composição original.
      final campo = faseDaZona('campo');
      expect(HeroTravel.far.pixelAt(campo), closeTo(HeroTravel.far.origin, 1e-6));
      expect(HeroTravel.clouds.pixelAt(campo),
          closeTo(HeroTravel.clouds.origin, 1e-6));
    });
  });

  group('o túnel e a luz são o mesmo relógio', () {
    test('no campo, na montanha e no entardecer a janela está aberta', () {
      for (final nome in ['campo', 'montanha', 'entardecer']) {
        expect(HeroTravel.darkness(faseDaZona(nome)), 0, reason: nome);
      }
    });

    test('na zona do túnel a parede cobre a janela inteira', () {
      expect(HeroTravel.darkness(faseDaZona('tunel-entrada')), 1);
    });

    test('janela coberta nunca coincide com vagão claro', () {
      for (var p = 0.0; p < 1; p += 0.001) {
        if (HeroTravel.darkness(p) < 1) continue;
        final luz = trilha.at(HeroTravel.center(p));
        expect(luz.exposure, lessThan(0.30), reason: 'fase $p');
        expect(luz.lamp, greaterThan(0.80), reason: 'fase $p');
      }
    });

    test('a parede entra pela direita e sai pela esquerda', () {
      // O trem anda para a direita: o que está à frente chega pela direita.
      final entrando = faseDaZona('tunel-entrada') - 0.018;
      final borda = HeroTravel.track.screenOf(entrando, HeroTravel.tunnelFrom);
      expect(borda, inExclusiveRange(0.0, 1.0));
      final depois = HeroTravel.track
          .screenOf(entrando + 0.002, HeroTravel.tunnelFrom);
      expect(depois, lessThan(borda));
    });

    test('na camada do trilho, a posição é a da trilha de luz', () {
      // É o que deixa o túnel ser autorado "aos 50% da viagem" nos dois lugares.
      for (final c in [0.1, 0.37, 0.5, 0.83]) {
        final fase = (c - HeroTravel.aperture / 2) % 1.0;
        expect(HeroTravel.track.at(fase, 0.5), closeTo(c, 1e-9));
      }
    });

    test('a paisagem escurece junto com o vagão', () {
      final campo = HeroTravel.outsideGain(trilha.at(0.0));
      final corte = HeroTravel.outsideGain(trilha.at(0.44));
      final tunel = HeroTravel.outsideGain(trilha.at(0.50));
      expect(campo, closeTo(1.0, 1e-9));
      expect(corte, lessThan(campo));
      expect(tunel, lessThan(corte));
      // Mas nunca a zero: é sombra, não é tinta preta.
      expect(tunel, greaterThan(0.25));
    });
  });

  group('o corte e o túnel', () {
    test('o corte sobe até a boca do túnel e desce depois dela', () {
      expect(Terrain.cutting(0.10), 0);
      expect(Terrain.cutting(0.80), 0);
      expect(Terrain.cutting(0.52), greaterThan(1));
      var anterior = 0.0;
      // Sobe (com a aspereza da rocha, mas sem voltar ao chão).
      for (var v = HeroTravel.cuttingFrom + 0.02; v < HeroTravel.tunnelFrom; v += 0.01) {
        final a = Terrain.cutting(v);
        expect(a, greaterThan(anterior - 0.08));
        anterior = a;
      }
      expect(anterior, greaterThan(0.6));
      // Nunca cobre a janela antes da boca: quem cobre é a parede.
      for (var v = HeroTravel.cuttingFrom; v < HeroTravel.tunnelFrom - 1e-9; v += 0.0007) {
        expect(Terrain.cutting(v), lessThan(1));
      }
    });

    test('não há poste dentro do corte nem do túnel', () {
      expect(HeroScenery.poles, isNotEmpty);
      for (final p in HeroScenery.poles) {
        expect(Terrain.cutting(p.v), 0, reason: 'poste em ${p.v}');
      }
    });

    test('as lâmpadas ficam todas dentro do túnel', () {
      expect(HeroScenery.lamps, isNotEmpty);
      for (final l in HeroScenery.lamps) {
        expect(l.v, inExclusiveRange(HeroTravel.tunnelFrom, HeroTravel.tunnelTo));
      }
    });
  });

  group('a vila', () {
    test('as luzes ficam juntas, em volta da âncora', () {
      expect(HeroScenery.village.length, greaterThanOrEqualTo(6));
      for (final l in HeroScenery.village) {
        expect(l.v.abs(), lessThan(30));
        expect(l.depth.abs(), lessThan(8));
      }
    });

    test('as âncoras caem dentro da tira do vale, no chão dele', () {
      for (final x in HeroAtlas.villages) {
        expect(x, inExclusiveRange(0, HeroAtlas.valley.width));
      }
      expect(
          HeroAtlas.villageRow,
          inExclusiveRange(HeroAtlas.valleyTop + 60,
              HeroAtlas.valleyTop + HeroAtlas.valley.height));
    });
  });

  group('o céu', () {
    test('no campo aberto a luz é branca: a janela é a pintura como ela é', () {
      final campo = HeroSky.at(0.0);
      expect(campo.land, const LightTint(255, 255, 255));
      expect(campo.clouds, const LightTint(255, 255, 255));
      expect(campo.sun, closeTo(0, 1e-9));
    });

    test('a saída do túnel é mais quente que o campo', () {
      final campo = HeroSky.at(0.0), tarde = HeroSky.at(0.74);
      expect(tarde.horizon.warmth, greaterThan(campo.horizon.warmth + 0.2));
      expect(tarde.land.warmth, greaterThan(campo.land.warmth + 0.2));
      expect(tarde.clouds.warmth, greaterThan(campo.clouds.warmth + 0.2));
      expect(tarde.sun, closeTo(1, 1e-9));
    });

    test('no atlas noturno há estrelas, não há sol, e tudo é escuro', () {
      for (final c in [0.0, 0.26, 0.74]) {
        final n = HeroSky.at(c, night: true);
        expect(n.stars, 1);
        expect(n.sun, 0);
        expect(n.top.luminance, lessThan(0.15));
        expect(n.top.luminance, lessThan(HeroSky.at(c).top.luminance));
        expect(n.land.luminance, lessThan(0.5));
        // E a noite é fria: a luz sobre a terra é a do luar.
        expect(n.land.warmth, lessThan(0));
      }
    });
  });

  group('as bolhas', () {
    /// Um ciclo e meio, quadro a quadro: `visita(antes, agora)`.
    void percorrer(void Function(Map<int, Bubble>, Map<int, Bubble>) visita) {
      var antes = <int, Bubble>{};
      for (var t = 0.0; t < HeroTravel.loopSeconds * 1.5; t += _quadro) {
        final agora = {for (final b in HeroBubbles.at(t)) b.index: b};
        if (t > 0) visita(antes, agora);
        antes = agora;
      }
    }

    test('toda bolha nasce na boca do cachimbo, do tamanho de nada', () {
      for (var n = -5; n < 200; n++) {
        // O instante do nascimento, achado por busca: a idade passa por zero.
        var t = n * HeroBubbles.interval;
        while (HeroBubbles.bubble(n, t) == null) {
          t += 0.001;
        }
        final b = HeroBubbles.bubble(n, t)!;
        expect(b.age, lessThan(0.002));
        expect(b.x, closeTo(HeroArtboard.pipeX, 0.01));
        expect(b.y, closeTo(HeroArtboard.pipeY, 0.01));
        expect(b.radius, lessThan(0.01));
        expect(b.opacity, lessThan(0.01));
        expect(b.squash, 0);
      }
    });

    test('sempre há bolhas no ar, e nunca um enxame', () {
      for (var t = 0.0; t < 200; t += 0.37) {
        expect(HeroBubbles.at(t).length, inInclusiveRange(4, 15), reason: 't=$t');
      }
    });

    test('nenhuma pula: de um quadro ao outro, menos de um pixel', () {
      percorrer((antes, agora) {
        for (final b in agora.values) {
          final a = antes[b.index];
          if (a == null) continue;
          expect((b.x - a.x).abs(), lessThan(1.0));
          expect((b.y - a.y).abs(), lessThan(1.0));
          expect((b.radius - a.radius).abs(), lessThan(0.5));
          expect((b.opacity - a.opacity).abs(), lessThan(0.08));
          expect((b.squash - a.squash).abs(), lessThan(0.03));
        }
      });
    });

    test('nenhuma aparece do nada nem some no meio do caminho', () {
      percorrer((antes, agora) {
        for (final b in agora.values) {
          if (antes.containsKey(b.index)) continue;
          expect(b.opacity, lessThan(0.02), reason: 'bolha ${b.index} surgiu');
          expect(b.radius, lessThan(1.0), reason: 'bolha ${b.index} surgiu');
        }
        for (final a in antes.values) {
          if (agora.containsKey(a.index)) continue;
          expect(a.opacity, lessThan(0.02), reason: 'bolha ${a.index} sumiu');
        }
      });
    });

    test('solta, a bolha só sobe', () {
      percorrer((antes, agora) {
        for (final b in agora.values) {
          final a = antes[b.index];
          if (a == null || a.age < HeroBubbles.inflate) continue;
          expect(b.y, lessThan(a.y), reason: 'bolha ${b.index} desceu');
        }
      });
    });

    test('nenhuma encosta no personagem', () {
      percorrer((_, agora) {
        for (final b in agora.values) {
          // O raio largo: a tremida de quando solta alarga a bolha.
          final largo = b.radius * (1 + b.squash.abs());
          expect(b.x - largo, greaterThan(HeroArtboard.characterEdge),
              reason: 'bolha ${b.index} aos ${b.age.toStringAsFixed(1)}s');
        }
      });
    });

    test('presa ao cachimbo é redonda; solta, treme e sossega', () {
      percorrer((_, agora) {
        for (final b in agora.values) {
          expect(b.squash.abs(), lessThan(0.12));
          if (b.age <= HeroBubbles.inflate) expect(b.squash, 0);
          if (b.age > HeroBubbles.inflate + 6) {
            expect(b.squash.abs(), lessThan(0.002));
          }
        }
      });
    });

    test('desfaz-se antes de a borda de cima cortá-la', () {
      percorrer((_, agora) {
        for (final b in agora.values) {
          // Com o topo da bolha já fora do quadro, ela está quase invisível.
          if (b.y - b.radius < -b.radius) {
            expect(b.opacity, lessThan(0.30));
          }
          expect(b.opacity, inInclusiveRange(0.0, 1.0));
        }
      });
    });

    test('é a mesma bolha em qualquer ordem de chamada', () {
      final a = HeroBubbles.at(123.4);
      HeroBubbles.at(7.0);
      final b = HeroBubbles.at(123.4);
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].index, b[i].index);
        expect(a[i].x, b[i].x);
        expect(a[i].y, b[i].y);
      }
    });
  });

  group('a respiração', () {
    test('enche e esvazia, sem tranco, e volta ao mesmo ponto', () {
      var anterior = HeroBreath.level(0);
      var menor = 1.0, maior = 0.0;
      for (var t = _quadro; t < HeroBreath.period * 3; t += _quadro) {
        final n = HeroBreath.level(t);
        expect(n, inInclusiveRange(0.0, 1.0));
        expect((n - anterior).abs(), lessThan(0.03), reason: 't=$t');
        if (n < menor) menor = n;
        if (n > maior) maior = n;
        anterior = n;
      }
      expect(menor, lessThan(0.001));
      expect(maior, greaterThan(0.999));
      expect(HeroBreath.level(HeroBreath.period * 5 + 1.3),
          closeTo(HeroBreath.level(1.3), 1e-9));
    });

    test('inspira mais depressa do que solta', () {
      // O pulmão cheio chega antes da metade do ciclo.
      expect(HeroBreath.level(HeroBreath.period * HeroBreath.inhale),
          closeTo(1, 1e-9));
      expect(HeroBreath.inhale, lessThan(0.5));
    });

    test('o peito sobe pouco, e nenhum ponto anda mais que três pixels', () {
      var maior = 0.0;
      for (var t = 0.0; t < HeroBreath.period; t += 0.05) {
        for (var x = 0.0; x <= HeroArtboard.width; x += 16) {
          for (var y = 0.0; y <= HeroArtboard.height; y += 16) {
            final (dx, dy) = HeroBreath.shift(x, y, t);
            final d = dx.abs() + dy.abs();
            if (d > maior) maior = d;
          }
        }
      }
      expect(maior, greaterThan(1.0), reason: 'respiração que não se vê');
      expect(maior, lessThan(3.0), reason: 'respiração que vira careta');
    });

    test('a boca do cachimbo não sai do lugar — é de lá que a bolha nasce', () {
      for (var t = 0.0; t < HeroBreath.period; t += 0.03) {
        final (dx, dy) =
            HeroBreath.shift(HeroArtboard.pipeX, HeroArtboard.pipeY, t);
        expect(dx.abs() + dy.abs(), lessThan(0.05));
      }
    });

    test('o vidro e a moldura da janela não se mexem', () {
      // Se a borda do recorte andasse, a paisagem apareceria por uma fresta.
      for (var t = 0.0; t < HeroBreath.period; t += 0.1) {
        for (var y = 0.0; y <= HeroArtboard.glassBottom - 160; y += 12) {
          final (dx, dy) = HeroBreath.shift(HeroArtboard.glassLeft, y, t);
          expect(dx.abs() + dy.abs(), lessThan(0.02), reason: 'y=$y');
        }
      }
    });

    test('nenhuma linha entorta: a deformação é rasa em todo lugar', () {
      // Dois pontos a um passo de distância nunca se afastam nem se aproximam
      // mais que 3% desse passo.
      const passo = 8.0;
      for (final t in [0.0, 0.9, 1.9, 3.1, 4.0]) {
        for (var x = 100.0; x < 700; x += passo) {
          for (var y = 180.0; y < 660; y += passo) {
            final (ax, ay) = HeroBreath.shift(x, y, t);
            final (bx, by) = HeroBreath.shift(x + passo, y, t);
            final (cx, cy) = HeroBreath.shift(x, y + passo, t);
            expect((bx - ax).abs() + (by - ay).abs(), lessThan(passo * 0.03));
            expect((cx - ax).abs() + (cy - ay).abs(), lessThan(passo * 0.03));
          }
        }
      }
    });

    test('quadro a quadro, o peito anda uma fração de pixel', () {
      const peito = HeroBreath.bumps;
      for (var t = 0.0; t < HeroBreath.period * 2; t += _quadro) {
        final (ax, ay) = HeroBreath.shift(peito.first.x, peito.first.y, t);
        final (bx, by) =
            HeroBreath.shift(peito.first.x, peito.first.y, t + _quadro);
        expect((bx - ax).abs() + (by - ay).abs(), lessThan(0.06));
      }
    });
  });
}
