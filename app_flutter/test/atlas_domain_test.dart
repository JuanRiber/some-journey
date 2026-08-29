import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/features/atlas/atlas_domain.dart';

/// A lógica do atlas é Dart puro, então dá para testar as mecânicas de
/// exploração (agrupamento, névoa, trajeto, distância) sem renderizar mapa —
/// que é exatamente o ganho de ter desacoplado do widget.
AtlasPoint p(double lat, double lng, {String id = 'm', DateTime? at}) =>
    AtlasPoint(memoryId: id, latitude: lat, longitude: lng, occurredAt: at);

void main() {
  _testesDoTracado();
  group('enquadramento', () {
    test('null sem pontos (a UI cai na visão ampla)', () {
      expect(AtlasDomain.boundsOf(const []), isNull);
    });

    test('envolve todos os pontos e acha o centro', () {
      final b = AtlasDomain.boundsOf([p(-10, -50), p(10, -30)])!;
      expect(b.minLat, -10);
      expect(b.maxLat, 10);
      expect(b.centerLat, 0);
      expect(b.centerLng, -40);
    });

    test('padded não escapa dos limites do mundo', () {
      final b = AtlasDomain.boundsOf([p(84, 179)])!.padded(10);
      expect(b.maxLat, lessThanOrEqualTo(85));
      expect(b.maxLng, lessThanOrEqualTo(180));
    });
  });

  group('agrupamento (cluster elegante)', () {
    test('pontos vizinhos viram UM selo com contagem', () {
      final clusters = AtlasDomain.cluster(
        [p(-23.55, -46.63, id: 'a'), p(-23.56, -46.64, id: 'b')],
        cellDegrees: 1,
      );
      expect(clusters, hasLength(1));
      expect(clusters.single.count, 2);
      expect(clusters.single.isSingle, isFalse);
    });

    test('pontos distantes permanecem separados e identificáveis', () {
      final clusters = AtlasDomain.cluster(
        [p(-23.5, -46.6, id: 'sp'), p(48.85, 2.35, id: 'paris')],
        cellDegrees: 1,
      );
      expect(clusters, hasLength(2));
      expect(clusters.every((c) => c.isSingle), isTrue);
      expect(clusters.map((c) => c.single!.memoryId), containsAll(['sp', 'paris']));
    });

    test('no detalhe (cellDegrees 0) cada memória é um pin', () {
      final clusters = AtlasDomain.cluster(
        [p(1, 1, id: 'a'), p(1.0001, 1.0001, id: 'b')],
        cellDegrees: 0,
      );
      expect(clusters, hasLength(2));
    });

    test('o selo fica no centroide, não no centro da célula', () {
      final c = AtlasDomain.cluster([p(0, 0), p(2, 2)], cellDegrees: 10).single;
      expect(c.latitude, 1);
      expect(c.longitude, 1);
    });

    test('zoom alto não agrupa; zoom baixo agrupa muito', () {
      expect(AtlasDomain.cellDegreesForZoom(14), 0);
      expect(AtlasDomain.cellDegreesForZoom(2), greaterThan(1));
    });
  });

  group('névoa (fog of war)', () {
    test('cada região visitada abre uma clareira, com intensidade por visitas', () {
      final cells = AtlasDomain.exploredCells(
        [p(0.1, 0.1), p(0.2, 0.2), p(40.5, 40.5)],
        cellDegrees: 1,
      );
      expect(cells, hasLength(2), reason: 'duas regiões distintas');
      final busiest = cells.reduce((a, b) => a.visits >= b.visits ? a : b);
      expect(busiest.visits, 2);
      // A célula cobre de fato o ponto que a gerou.
      expect(busiest.bounds.minLat, lessThanOrEqualTo(0.1));
      expect(busiest.bounds.maxLat, greaterThan(0.2));
    });
  });

  group('trajeto', () {
    test('a linha segue o TEMPO, não a ordem da API', () {
      final trail = AtlasDomain.chronologicalTrail([
        p(3, 3, id: 'terceiro', at: DateTime.utc(2025, 3, 1)),
        p(1, 1, id: 'primeiro', at: DateTime.utc(2025, 1, 1)),
        p(2, 2, id: 'segundo', at: DateTime.utc(2025, 2, 1)),
      ]);
      expect(trail.map((e) => e.memoryId), ['primeiro', 'segundo', 'terceiro']);
    });

    test('pontos sem data vão para o fim (sem quebrar a ordem)', () {
      final trail = AtlasDomain.chronologicalTrail([
        p(0, 0, id: 'sem-data'),
        p(1, 1, id: 'com-data', at: DateTime.utc(2025, 1, 1)),
      ]);
      expect(trail.first.memoryId, 'com-data');
      expect(trail.last.memoryId, 'sem-data');
    });

    test('distância de São Paulo a Rio ~ 360 km', () {
      final d = AtlasDomain.distanceMeters(p(-23.55, -46.63), p(-22.91, -43.17));
      expect(d / 1000, closeTo(360, 25));
    });

    test('um ponto só não percorreu nada', () {
      expect(AtlasDomain.trailDistanceMeters([p(0, 0)]), 0);
    });

    test('soma os trechos do trajeto', () {
      final trail = [p(0, 0), p(0, 1), p(0, 2)];
      final total = AtlasDomain.trailDistanceMeters(trail);
      final leg = AtlasDomain.distanceMeters(p(0, 0), p(0, 1));
      expect(total, closeTo(leg * 2, 1));
    });
  });

  group('narrativa da distância', () {
    test('formata metros, quilômetros e milhares em pt-BR', () {
      expect(AtlasDomain.formatDistance(820), '820 m');
      expect(AtlasDomain.formatDistance(12400), '12,4 km');
      expect(AtlasDomain.formatDistance(2430000), '2.430 km');
    });
  });
}

// ── O rastro sendo desenhado ────────────────────────────────────────────────
//
// A ponta da linha avança interpolando o segmento atual. Sem isso, um rastro de
// quatro pontos cresceria em quatro saltos — parece régua, não pena.
void _testesDoTracado() {
  group('partialLine', () {
    final linha = [
      [0.0, 0.0],
      [10.0, 0.0],
      [20.0, 0.0],
      [30.0, 0.0],
    ];

    test('em t=0 não há nada desenhado', () {
      expect(AtlasDomain.partialLine(linha, 0), isEmpty);
    });

    test('em t=1 a linha está inteira', () {
      expect(AtlasDomain.partialLine(linha, 1), linha);
    });

    test('na metade, a ponta cai no meio geométrico', () {
      final meio = AtlasDomain.partialLine(linha, 0.5);
      expect(meio.last[0], closeTo(15, 0.001),
          reason: 'a ponta interpola, não salta para o próximo vértice');
    });

    test('a ponta avança continuamente, sem degraus', () {
      double? anterior;
      for (var i = 1; i <= 20; i++) {
        final p = AtlasDomain.partialLine(linha, i / 20);
        if (p.isEmpty) continue;
        final x = p.last[0];
        if (anterior != null) {
          expect(x, greaterThanOrEqualTo(anterior));
          expect(x - anterior, lessThan(4),
              reason: 'um salto grande denunciaria avanço de vértice em vértice');
        }
        anterior = x;
      }
    });

    test('nunca devolve uma polilinha de um ponto só', () {
      for (var i = 0; i <= 40; i++) {
        final p = AtlasDomain.partialLine(linha, i / 40);
        expect(p.length, isNot(1), reason: 'um ponto não desenha linha');
      }
    });

    test('linha curta demais passa intacta', () {
      expect(AtlasDomain.partialLine([[1.0, 2.0]], 0.5), hasLength(1));
    });

    test('preserva a ordem [lng, lat] que vem da API', () {
      final p = AtlasDomain.partialLine([
        [-38.52, -3.73],
        [-38.50, -3.71],
      ], 1);
      expect(p.first, [-38.52, -3.73]);
    });
  });
}
