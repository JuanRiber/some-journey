import 'package:flutter_test/flutter_test.dart';

import 'package:some_journey/models.dart';

void main() {
  test('MapResponse.totalPoints soma pontos soltos + pontos de jornadas', () {
    final map = MapResponse.fromJson({
      'loose_points': [
        {
          'memory_id': 'a',
          'title': 'Solto',
          'latitude': -3.7,
          'longitude': -38.5,
          'occurred_at': '2026-01-01T12:00:00Z',
          'position': null,
        },
      ],
      'journeys': [
        {
          'id': 'j1',
          'title': 'Tour',
          'status': 'active',
          'points': [
            {
              'memory_id': 'b',
              'title': 'P1',
              'latitude': -8.0,
              'longitude': -34.8,
              'occurred_at': '2026-02-01T12:00:00Z',
              'position': 1,
            },
          ],
          'route': null,
        },
      ],
    });

    expect(map.loosePoints.length, 1);
    expect(map.journeys.single.points.single.memoryId, 'b');
    expect(map.totalPoints, 2);
  });

  test('Journey.fromJson lê status e privacidade', () {
    final j = Journey.fromJson({
      'id': 'j1',
      'title': 'Fortaleza Nights',
      'description': null,
      'mood': 'noturno',
      'is_private': false,
      'cover_image_url': null,
      'status': 'paused',
      'started_at': null,
      'ended_at': null,
      'created_at': '2026-01-01T00:00:00Z',
      'points_count': 3,
    });

    expect(j.status, 'paused');
    expect(j.isPrivate, false);
    expect(j.pointsCount, 3);
  });
}
