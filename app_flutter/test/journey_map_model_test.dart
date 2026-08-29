// Leitura do mapa da jornada — fixado contra uma resposta REAL do backend.
//
// A carga abaixo saiu de um servidor de verdade (FastAPI + PostGIS), com um
// percurso gravado de ponta a ponta. Um teste escrito só a partir da minha
// leitura do schema validaria o meu entendimento, não o contrato; este pega
// divergência de formato — e a armadilha aqui é séria: GeoJSON usa
// [longitude, latitude], a ordem INVERSA da que o mapa desenha.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/models.dart';

const _respostaReal = '''
{
  "journey": {
    "id": "f981c5b2-dd2e-4ad4-91c1-ce520763844b",
    "title": "Caminhada na Beira-Mar"
  },
  "tracks": {
    "type": "FeatureCollection",
    "features": [
      {
        "type": "Feature",
        "properties": {
          "track_id": "18580a9f-2628-4fdb-bbd5-28acb9e9463a",
          "source": "gps_live",
          "started_at": "2026-08-28T18:57:04.106462-03:00",
          "ended_at": "2026-08-28T18:57:04.687227-03:00",
          "point_count": 3,
          "distance_m": 272.2
        },
        "geometry": {
          "type": "LineString",
          "coordinates": [[-38.509, -3.7227], [-38.5089, -3.7225], [-38.5088, -3.7223]]
        }
      }
    ]
  },
  "memories": {"type": "FeatureCollection", "features": []},
  "symbolic_route": null,
  "distance_m": 272.2
}
''';

void main() {
  test('lê o percurso real de uma resposta do servidor', () {
    final m = JourneyMap.fromJson(
        jsonDecode(_respostaReal) as Map<String, dynamic>);

    expect(m.title, 'Caminhada na Beira-Mar');
    expect(m.trackLines, hasLength(1));
    expect(m.trackLines.first, hasLength(3));
    expect(m.distanceMeters, 272.2);
    expect(m.hasRealTrack, isTrue);
  });

  test('as coordenadas continuam em [lng, lat], como o GeoJSON manda', () {
    final m = JourneyMap.fromJson(
        jsonDecode(_respostaReal) as Map<String, dynamic>);
    final primeira = m.trackLines.first.first;

    expect(primeira[0], -38.509, reason: 'índice 0 é longitude');
    expect(primeira[1], -3.7227, reason: 'índice 1 é latitude');
    // Fortaleza fica em latitude ~-3.7 e longitude ~-38.5. Se a inversão
    // vazasse, a latitude seria -38.5 — um ponto no meio do Atlântico Sul.
    expect(primeira[1].abs(), lessThan(10),
        reason: 'latitude trocada por longitude jogaria o traço no oceano');
  });

  test('jornada sem trecho gravado não finge ter percurso', () {
    final m = JourneyMap.fromJson(jsonDecode('''
      {"journey":{"id":"j","title":"Sem GPS"},
       "tracks":{"type":"FeatureCollection","features":[]},
       "memories":{"type":"FeatureCollection","features":[]},
       "symbolic_route":null,"distance_m":0}
    ''') as Map<String, dynamic>);

    expect(m.trackLines, isEmpty);
    expect(m.hasRealTrack, isFalse);
    expect(m.distanceMeters, 0);
  });

  test('trecho de um ponto só não vira linha', () {
    final m = JourneyMap.fromJson(jsonDecode('''
      {"journey":{"id":"j","title":"Um ponto"},
       "tracks":{"type":"FeatureCollection","features":[
         {"type":"Feature","properties":{},"geometry":{"type":"LineString",
          "coordinates":[[-38.5,-3.7]]}}]},
       "memories":{"type":"FeatureCollection","features":[]},
       "symbolic_route":null,"distance_m":0}
    ''') as Map<String, dynamic>);

    expect(m.trackLines.first, hasLength(1));
    expect(m.hasRealTrack, isFalse,
        reason: 'uma linha precisa de dois pontos para existir');
  });

  test('lê o trecho da listagem de tracks', () {
    final t = JourneyTrack.fromJson(jsonDecode('''
      {"id":"t1","journey_id":"j1","source":"gps_live",
       "started_at":"2026-08-28T18:57:04Z","ended_at":null,
       "is_active":true,"point_count":12,"distance_m":272.2,
       "created_at":"2026-08-28T18:57:04Z"}
    ''') as Map<String, dynamic>);

    expect(t.isActive, isTrue);
    expect(t.pointCount, 12);
    expect(t.distanceMeters, 272.2);
    expect(t.endedAt, isNull, reason: 'trecho aberto não tem fim');
  });
}
