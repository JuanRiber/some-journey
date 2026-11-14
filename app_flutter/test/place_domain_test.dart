// O lugar de uma memória, em palavras.
//
// O backend resolvia o nome do lugar havia tempo e nenhuma tela o mostrava: o
// `place_label` chegava no JSON e morria no `fromJson`, que não o lia. O
// detalhe exibia "-3.494, -39.579" e a timeline "3.49° S · 39.58° O" — dois
// formatos para o mesmo dado, e nenhum dos dois era o que a pessoa conhece.
//
// Estes testes guardam as duas metades da correção: o campo atravessa o
// `fromJson` (memória e ponto de jornada), e a regra de exibição cai para a
// coordenada só enquanto o nome não existe.

import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/features/places/place_domain.dart';
import 'package:some_journey/models.dart';

void main() {
  group('placeLine', () {
    test('com nome resolvido, mostra o nome', () {
      expect(placeLine('Vila de Jericoacoara, Jijoca de Jericoacoara', -2.79, -40.51),
          'Vila de Jericoacoara, Jijoca de Jericoacoara');
    });

    test('sem nome ainda, cai para a coordenada de atlas', () {
      expect(placeLine(null, -3.7197, -38.5434), '3.72° S · 38.54° O');
    });

    test('nome em branco conta como ausente', () {
      expect(placeLine('   ', -3.7197, -38.5434), '3.72° S · 38.54° O');
    });

    test('hemisférios norte e leste', () {
      expect(atlasCoords(38.7223, 9.1393), '38.72° N · 9.14° L');
    });
  });

  group('place_label atravessa o fromJson', () {
    test('memória', () {
      final m = Memory.fromJson({
        'id': 'm1',
        'title': '',
        'text': '',
        'latitude': -3.7,
        'longitude': -38.5,
        'occurred_at': '2026-08-14T00:00:00Z',
        'created_at': '2026-08-14T00:00:00Z',
        'place_label': 'Praia de Iracema, Fortaleza',
      });
      expect(m.placeLabel, 'Praia de Iracema, Fortaleza');
    });

    test('memória ainda sem lugar', () {
      final m = Memory.fromJson({
        'id': 'm1',
        'title': '',
        'text': '',
        'latitude': -3.7,
        'longitude': -38.5,
        'occurred_at': '2026-08-14T00:00:00Z',
        'created_at': '2026-08-14T00:00:00Z',
      });
      expect(m.placeLabel, isNull);
    });

    test('ponto de jornada', () {
      final p = JourneyPoint.fromJson({
        'memory_id': 'm1',
        'title': '',
        'latitude': -3.49,
        'longitude': -39.58,
        'occurred_at': '2024-07-05T00:00:00Z',
        'position': 1,
        'place_label': 'Itapipoca',
      });
      expect(p.placeLabel, 'Itapipoca');
    });
  });
}
