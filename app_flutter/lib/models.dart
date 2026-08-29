// Modelos da API (espelham os schemas do backend FastAPI).

class MemoryImage {
  final String id;
  final String url;
  MemoryImage({required this.id, required this.url});
  factory MemoryImage.fromJson(Map<String, dynamic> j) =>
      MemoryImage(id: j['id'] as String, url: j['url'] as String);
}

class Memory {
  final String id;
  final String title;
  final String text;
  final double latitude;
  final double longitude;
  final String occurredAt;
  final String createdAt;
  final List<MemoryImage> images;
  final String? imageUrl;

  Memory({
    required this.id,
    required this.title,
    required this.text,
    required this.latitude,
    required this.longitude,
    required this.occurredAt,
    required this.createdAt,
    required this.images,
    this.imageUrl,
  });

  factory Memory.fromJson(Map<String, dynamic> j) => Memory(
        id: j['id'] as String,
        title: j['title'] as String,
        text: (j['text'] ?? '') as String,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        occurredAt: j['occurred_at'] as String,
        createdAt: j['created_at'] as String,
        images: ((j['images'] ?? []) as List)
            .map((e) => MemoryImage.fromJson(e as Map<String, dynamic>))
            .toList(),
        imageUrl: j['image_url'] as String?,
      );
}

class Journey {
  final String id;
  final String title;
  final String? description;
  final String? mood;
  final bool isPrivate;
  final String? coverImageUrl;
  final String status; // draft | active | paused | finished
  final String? startedAt;
  final String? endedAt;
  final String createdAt;
  final int pointsCount;

  Journey({
    required this.id,
    required this.title,
    this.description,
    this.mood,
    required this.isPrivate,
    this.coverImageUrl,
    required this.status,
    this.startedAt,
    this.endedAt,
    required this.createdAt,
    required this.pointsCount,
  });

  factory Journey.fromJson(Map<String, dynamic> j) => Journey(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        mood: j['mood'] as String?,
        isPrivate: (j['is_private'] ?? true) as bool,
        coverImageUrl: j['cover_image_url'] as String?,
        status: j['status'] as String,
        startedAt: j['started_at'] as String?,
        endedAt: j['ended_at'] as String?,
        createdAt: j['created_at'] as String,
        pointsCount: (j['points_count'] ?? 0) as int,
      );
}

class JourneyPoint {
  final String memoryId;
  final String title;
  final double latitude;
  final double longitude;
  final String occurredAt;
  final int? position;

  JourneyPoint({
    required this.memoryId,
    required this.title,
    required this.latitude,
    required this.longitude,
    required this.occurredAt,
    this.position,
  });

  factory JourneyPoint.fromJson(Map<String, dynamic> j) => JourneyPoint(
        memoryId: j['memory_id'] as String,
        title: j['title'] as String,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        occurredAt: j['occurred_at'] as String,
        position: j['position'] as int?,
      );
}

/// Rastro simbólico: LineString GeoJSON ([lng, lat]).
class JourneyRoute {
  final List<List<double>> coordinates;
  JourneyRoute({required this.coordinates});
  factory JourneyRoute.fromJson(Map<String, dynamic> j) => JourneyRoute(
        coordinates: ((j['coordinates'] ?? []) as List)
            .map((c) => (c as List).map((v) => (v as num).toDouble()).toList())
            .toList(),
      );
}

class JourneyDetail extends Journey {
  final List<JourneyPoint> points;
  final JourneyRoute? route;

  JourneyDetail({
    required super.id,
    required super.title,
    super.description,
    super.mood,
    required super.isPrivate,
    super.coverImageUrl,
    required super.status,
    super.startedAt,
    super.endedAt,
    required super.createdAt,
    required super.pointsCount,
    required this.points,
    this.route,
  });

  factory JourneyDetail.fromJson(Map<String, dynamic> j) {
    final base = Journey.fromJson(j);
    return JourneyDetail(
      id: base.id,
      title: base.title,
      description: base.description,
      mood: base.mood,
      isPrivate: base.isPrivate,
      coverImageUrl: base.coverImageUrl,
      status: base.status,
      startedAt: base.startedAt,
      endedAt: base.endedAt,
      createdAt: base.createdAt,
      pointsCount: base.pointsCount,
      points: ((j['points'] ?? []) as List)
          .map((e) => JourneyPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      route: j['route'] == null ? null : JourneyRoute.fromJson(j['route'] as Map<String, dynamic>),
    );
  }
}

class MapJourney {
  final String id;
  final String title;
  final String status;
  final List<JourneyPoint> points;
  final JourneyRoute? route;

  MapJourney({
    required this.id,
    required this.title,
    required this.status,
    required this.points,
    this.route,
  });

  factory MapJourney.fromJson(Map<String, dynamic> j) => MapJourney(
        id: j['id'] as String,
        title: j['title'] as String,
        status: j['status'] as String,
        points: ((j['points'] ?? []) as List)
            .map((e) => JourneyPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        route: j['route'] == null ? null : JourneyRoute.fromJson(j['route'] as Map<String, dynamic>),
      );
}

class MapResponse {
  final List<JourneyPoint> loosePoints;
  final List<MapJourney> journeys;

  MapResponse({required this.loosePoints, required this.journeys});

  factory MapResponse.fromJson(Map<String, dynamic> j) => MapResponse(
        loosePoints: ((j['loose_points'] ?? []) as List)
            .map((e) => JourneyPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        journeys: ((j['journeys'] ?? []) as List)
            .map((e) => MapJourney.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  int get totalPoints =>
      loosePoints.length + journeys.fold(0, (n, j) => n + j.points.length);
}

/// Perfil da conta (GET /auth/me). Só campos públicos — o hash de senha nunca
/// sai da API.
class UserProfile {
  final String id;
  final String name;
  final String email;
  final bool isActive;
  final String createdAt;

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        isActive: (j['is_active'] ?? true) as bool,
        createdAt: (j['created_at'] ?? '') as String,
      );
}

/// Um trecho de percurso REAL (rastro de GPS), distinto da linha simbólica que
/// liga as memórias na ordem. Pausar e retomar a gravação gera vários trechos;
/// juntos formam uma experiência só.
class JourneyTrack {
  final String id;
  final String journeyId;
  final String source;
  final String startedAt;
  final String? endedAt;
  final bool isActive;
  final int pointCount;
  final double distanceMeters;

  JourneyTrack({
    required this.id,
    required this.journeyId,
    required this.source,
    required this.startedAt,
    required this.isActive,
    required this.pointCount,
    required this.distanceMeters,
    this.endedAt,
  });

  factory JourneyTrack.fromJson(Map<String, dynamic> j) => JourneyTrack(
        id: j['id'] as String,
        journeyId: j['journey_id'] as String,
        source: (j['source'] ?? 'gps_live') as String,
        startedAt: j['started_at'] as String,
        endedAt: j['ended_at'] as String?,
        isActive: (j['is_active'] ?? false) as bool,
        pointCount: (j['point_count'] as num?)?.toInt() ?? 0,
        distanceMeters: (j['distance_m'] as num?)?.toDouble() ?? 0,
      );
}

/// O mapa da jornada: percurso real por trecho, memórias e o rastro simbólico.
///
/// Vem em GeoJSON — `[lng, lat]`, ordem do padrão, INVERTIDA em relação ao que
/// o mapa desenha. A conversão acontece na borda, uma vez, para não espalhar a
/// troca de eixos pela UI.
class JourneyMap {
  final String journeyId;
  final String title;

  /// Uma lista de coordenadas por trecho gravado.
  final List<List<List<double>>> trackLines;
  final JourneyRoute? symbolicRoute;
  final double distanceMeters;

  JourneyMap({
    required this.journeyId,
    required this.title,
    required this.trackLines,
    required this.distanceMeters,
    this.symbolicRoute,
  });

  bool get hasRealTrack => trackLines.any((l) => l.length >= 2);

  factory JourneyMap.fromJson(Map<String, dynamic> j) {
    final journey = (j['journey'] ?? const {}) as Map<String, dynamic>;
    final tracks = (j['tracks'] ?? const {}) as Map<String, dynamic>;
    final features = (tracks['features'] ?? const []) as List;
    return JourneyMap(
      journeyId: (journey['id'] ?? '') as String,
      title: (journey['title'] ?? '') as String,
      trackLines: features
          .map((f) => (((f as Map<String, dynamic>)['geometry']
                  as Map<String, dynamic>)['coordinates'] as List)
              .map((c) => (c as List).map((v) => (v as num).toDouble()).toList())
              .toList())
          .toList(),
      symbolicRoute: j['symbolic_route'] == null
          ? null
          : JourneyRoute.fromJson(j['symbolic_route'] as Map<String, dynamic>),
      distanceMeters: (j['distance_m'] as num?)?.toDouble() ?? 0,
    );
  }
}
