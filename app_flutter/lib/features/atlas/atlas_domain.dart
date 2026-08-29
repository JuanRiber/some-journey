/// # Atlas — CAMADA DE DOMÍNIO (Dart puro, zero Flutter).
///
/// Decisão arquitetural: toda a inteligência do mapa vive AQUI, sem importar
/// widgets. O componente visual (`widgets/atlas_map.dart`) só desenha o que este
/// módulo calcula. Ganhos: dá para testar sem renderizar, trocar o provedor de
/// mapa (Leaflet/flutter_map → Mapbox) sem reescrever regra, e a UI fica boba.
///
/// Direção do produto (escolhida pelo dono): a cartografia é REAL (coordenadas
/// verdadeiras, rastro de GPS verdadeiro) e as mecânicas de exploração —
/// agrupamento, névoa do que não foi visitado, trajeto, posição atual — entram
/// COMO CAMADAS sobre ela. Nada de mapa inventado.
library;

import 'dart:math' as math;

/// Um ponto do atlas: uma memória em um lugar e um tempo.
class AtlasPoint {
  const AtlasPoint({
    required this.memoryId,
    required this.latitude,
    required this.longitude,
    this.journeyId,
    this.occurredAt,
    this.title,
  });

  final String memoryId;
  final double latitude;
  final double longitude;

  /// Nulo = ponto solto (não pertence a nenhuma jornada).
  final String? journeyId;
  final DateTime? occurredAt;
  final String? title;
}

/// Retângulo geográfico. Usado para enquadrar a câmera e para a névoa.
class GeoBounds {
  const GeoBounds({
    required this.minLat,
    required this.minLng,
    required this.maxLat,
    required this.maxLng,
  });

  final double minLat, minLng, maxLat, maxLng;

  double get centerLat => (minLat + maxLat) / 2;
  double get centerLng => (minLng + maxLng) / 2;

  /// Cresce o retângulo em graus — respiro para os pins não colarem na borda.
  GeoBounds padded(double degrees) => GeoBounds(
        minLat: math.max(-85, minLat - degrees),
        minLng: math.max(-180, minLng - degrees),
        maxLat: math.min(85, maxLat + degrees),
        maxLng: math.min(180, maxLng + degrees),
      );
}

/// Um AGRUPAMENTO de pontos próximos — o "cluster elegante" do produto: ao
/// afastar o zoom o mapa não vira nuvem de marcadores, vira poucos selos com
/// contagem. Um cluster de 1 ponto é o próprio pin (a UI decide o desenho).
class AtlasCluster {
  AtlasCluster({
    required this.latitude,
    required this.longitude,
    required this.points,
  });

  final double latitude;
  final double longitude;
  final List<AtlasPoint> points;

  int get count => points.length;
  bool get isSingle => points.length == 1;

  /// Quando é um só ponto, o cluster carrega a identidade dele (para abrir a
  /// memória no toque).
  AtlasPoint? get single => isSingle ? points.first : null;
}

/// Uma célula já "explorada". A névoa (fog of war) é o COMPLEMENTO disto: o que
/// o usuário nunca visitou continua encoberto. Guardamos as células visitadas em
/// vez da névoa inteira porque são poucas e finitas.
class ExploredCell {
  const ExploredCell(this.bounds, this.visits);
  final GeoBounds bounds;

  /// Quantas memórias caíram nesta célula — a UI usa para a intensidade do
  /// "heatmap leve" (mais visitas = clareira mais nítida).
  final int visits;
}

/// Serviço de domínio do atlas. Sem estado: recebe pontos, devolve o que
/// desenhar.
abstract final class AtlasDomain {
  /// Raio médio da Terra (m) — para a distância percorrida.
  static const _earthRadiusM = 6371000.0;

  /// Enquadramento de todos os pontos. Null quando não há nada a mostrar (a UI
  /// então cai numa visão ampla padrão).
  static GeoBounds? boundsOf(Iterable<AtlasPoint> points) {
    if (points.isEmpty) return null;
    var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    return GeoBounds(minLat: minLat, minLng: minLng, maxLat: maxLat, maxLng: maxLng);
  }

  /// Agrupa por GRADE em graus — barato (O(n)) e estável: o mesmo conjunto de
  /// pontos sempre gera os mesmos clusters, então o mapa não "tremula" ao
  /// redesenhar. `cellDegrees` vem do zoom: quanto mais longe, maior a célula.
  ///
  /// A posição do cluster é o CENTROIDE dos seus pontos (não o centro da
  /// célula), senão os selos pareceriam presos a uma grade invisível.
  static List<AtlasCluster> cluster(
    Iterable<AtlasPoint> points, {
    required double cellDegrees,
  }) {
    if (cellDegrees <= 0) {
      return [
        for (final p in points)
          AtlasCluster(latitude: p.latitude, longitude: p.longitude, points: [p]),
      ];
    }
    final buckets = <String, List<AtlasPoint>>{};
    for (final p in points) {
      final key = '${(p.latitude / cellDegrees).floor()}:'
          '${(p.longitude / cellDegrees).floor()}';
      buckets.putIfAbsent(key, () => []).add(p);
    }
    final out = <AtlasCluster>[];
    for (final group in buckets.values) {
      final lat = group.map((p) => p.latitude).reduce((a, b) => a + b) / group.length;
      final lng = group.map((p) => p.longitude).reduce((a, b) => a + b) / group.length;
      out.add(AtlasCluster(latitude: lat, longitude: lng, points: group));
    }
    // Ordem determinística (mais populoso primeiro) para a UI desenhar os selos
    // grandes por baixo dos pequenos, sem sorteio a cada frame.
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  /// Tamanho de célula sugerido por zoom. Perto (zoom alto) quase não agrupa;
  /// longe (zoom baixo) agrupa continentes. Curva empírica, calma.
  static double cellDegreesForZoom(double zoom) {
    if (zoom >= 13) return 0; // detalhe: cada memória é um pin
    if (zoom >= 10) return 0.05;
    if (zoom >= 8) return 0.2;
    if (zoom >= 6) return 0.6;
    if (zoom >= 4) return 2.0;
    return 6.0;
  }

  /// Células exploradas (o inverso da névoa). `cellDegrees` define a resolução
  /// da clareira que cada memória abre no mapa.
  static List<ExploredCell> exploredCells(
    Iterable<AtlasPoint> points, {
    double cellDegrees = 0.5,
  }) {
    if (cellDegrees <= 0) return const [];
    final counts = <String, int>{};
    for (final p in points) {
      final key = '${(p.latitude / cellDegrees).floor()}:'
          '${(p.longitude / cellDegrees).floor()}';
      counts.update(key, (v) => v + 1, ifAbsent: () => 1);
    }
    return [
      for (final entry in counts.entries)
        () {
          final parts = entry.key.split(':');
          final latIndex = int.parse(parts[0]);
          final lngIndex = int.parse(parts[1]);
          return ExploredCell(
            GeoBounds(
              minLat: latIndex * cellDegrees,
              minLng: lngIndex * cellDegrees,
              maxLat: (latIndex + 1) * cellDegrees,
              maxLng: (lngIndex + 1) * cellDegrees,
            ),
            entry.value,
          );
        }(),
    ];
  }

  /// Trajeto de uma jornada em ORDEM DO TEMPO — é isto que faz a linha parecer
  /// uma viagem de verdade, e não a ordem em que a API devolveu. Pontos sem data
  /// vão para o fim, preservando a ordem relativa (estável).
  static List<AtlasPoint> chronologicalTrail(Iterable<AtlasPoint> points) {
    final list = points.toList();
    list.sort((a, b) {
      final da = a.occurredAt, db = b.occurredAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return list;
  }

  /// Distância total do trajeto em METROS (haversine). Serve a narrativa do
  /// produto: "sua jornada já percorreu 2.430 km" em vez de "12 pontos".
  static double trailDistanceMeters(List<AtlasPoint> orderedTrail) {
    if (orderedTrail.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < orderedTrail.length; i++) {
      total += distanceMeters(orderedTrail[i - 1], orderedTrail[i]);
    }
    return total;
  }

  /// O rastro desenhado até a fração [t] de seu comprimento — a linha *sendo
  /// traçada*, não revelada de uma vez.
  ///
  /// O último segmento é INTERPOLADO em vez de aparecer inteiro. Sem isso, um
  /// rastro de poucos pontos cresceria aos saltos, como quem risca a régua de
  /// marco em marco; interpolando, a ponta avança como uma pena sobre o papel.
  ///
  /// Recebe e devolve coordenadas `[lng, lat]` (a ordem do GeoJSON, que é a que
  /// chega da API) para não obrigar quem chama a converter duas vezes.
  static List<List<double>> partialLine(List<List<double>> line, double t) {
    if (line.length < 2 || t >= 1) return line;
    if (t <= 0) return const [];

    // Quantos segmentos já foram percorridos, e quanto do atual.
    final total = line.length - 1;
    final avanco = total * t;
    final inteiros = avanco.floor();
    final resto = avanco - inteiros;

    final saida = line.sublist(0, inteiros + 1);
    if (resto > 0 && inteiros < total) {
      final a = line[inteiros], b = line[inteiros + 1];
      saida.add([
        a[0] + (b[0] - a[0]) * resto,
        a[1] + (b[1] - a[1]) * resto,
      ]);
    }
    // Uma linha de um ponto só não desenha nada; devolve vazio para a camada
    // não receber uma polilinha degenerada.
    return saida.length < 2 ? const [] : saida;
  }

  /// Haversine entre dois pontos, em metros.
  static double distanceMeters(AtlasPoint a, AtlasPoint b) =>
      haversineMeters(a.latitude, a.longitude, b.latitude, b.longitude);

  /// Haversine sobre COORDENADAS cruas, em metros.
  ///
  /// Existe separado de [distanceMeters] porque a gravação de percurso mede
  /// distância entre leituras de GPS, que não são memórias — forçá-las a virar
  /// [AtlasPoint] só para medir seria inventar identidade que elas não têm.
  static double haversineMeters(
    double aLat,
    double aLng,
    double bLat,
    double bLng,
  ) {
    final dLat = _rad(bLat - aLat);
    final dLng = _rad(bLng - aLng);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(aLat)) *
            math.cos(_rad(bLat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
  }

  /// Distância legível: "820 m", "12,4 km", "2.430 km".
  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    final km = meters / 1000;
    if (km < 100) return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
    final rounded = km.round().toString();
    // Separador de milhar em pt-BR (ponto), sem depender de intl.
    final withDots = rounded.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]}.',
    );
    return '$withDots km';
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
