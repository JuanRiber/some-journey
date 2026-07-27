/// Modelos do Perfil — espelham o payload de `GET /me/profile`.
///
/// O contrato vem em BLOCOS (identidade, estatísticas, passaporte, última
/// aventura, jornada atual) e não num mapa plano: quando avatar, @username,
/// conquistas e coleções chegarem, cada bloco novo entra sem quebrar o que já é
/// lido aqui. Nenhum número é calculado no cliente — tudo já vem agregado.
library;

// `characters` trata GRAFEMAS: iniciais de um nome com acento ou emoji não podem
// ser cortadas no meio de um code unit.
import 'package:characters/characters.dart';

class ProfileIdentity {
  final String id;
  final String name;
  final String email;
  final DateTime joinedAt;
  final DateTime? memberSince;
  final String? username;
  final String? avatarUrl;
  final String? bio;

  ProfileIdentity({
    required this.id,
    required this.name,
    required this.email,
    required this.joinedAt,
    this.memberSince,
    this.username,
    this.avatarUrl,
    this.bio,
  });

  factory ProfileIdentity.fromJson(Map<String, dynamic> j) => ProfileIdentity(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        joinedAt: DateTime.parse(j['joined_at'] as String),
        memberSince: j['member_since'] == null
            ? null
            : DateTime.parse(j['member_since'] as String),
        username: j['username'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        bio: j['bio'] as String?,
      );

  /// Iniciais para o avatar enquanto não há foto ("Juan Pedro" -> "JP").
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }
}

class ProfileStats {
  final int memories;
  final int journeys;
  final int journeysFinished;
  final int cities;
  final int countries;
  final int continents;
  final int photos;
  final double trackedMeters;
  final int activeDays;

  /// Quantas memórias ainda esperam geocodificação — o Perfil AVISA em vez de
  /// deixar o passaporte parecer errado.
  final int pendingGeocode;

  ProfileStats({
    required this.memories,
    required this.journeys,
    required this.journeysFinished,
    required this.cities,
    required this.countries,
    required this.continents,
    required this.photos,
    required this.trackedMeters,
    required this.activeDays,
    required this.pendingGeocode,
  });

  factory ProfileStats.fromJson(Map<String, dynamic> j) => ProfileStats(
        memories: (j['memories'] ?? 0) as int,
        journeys: (j['journeys'] ?? 0) as int,
        journeysFinished: (j['journeys_finished'] ?? 0) as int,
        cities: (j['cities'] ?? 0) as int,
        countries: (j['countries'] ?? 0) as int,
        continents: (j['continents'] ?? 0) as int,
        photos: (j['photos'] ?? 0) as int,
        trackedMeters: ((j['tracked_meters'] ?? 0) as num).toDouble(),
        activeDays: (j['active_days'] ?? 0) as int,
        pendingGeocode: (j['pending_geocode'] ?? 0) as int,
      );

  bool get isEmpty => memories == 0 && journeys == 0;
}

class PassportStamp {
  final String continent;
  final bool visited;

  PassportStamp({required this.continent, required this.visited});

  factory PassportStamp.fromJson(Map<String, dynamic> j) => PassportStamp(
        continent: (j['continent'] ?? '') as String,
        visited: (j['visited'] ?? false) as bool,
      );
}

class LastAdventure {
  final String? city;
  final String? country;
  final String? countryCode;
  final DateTime? occurredAt;

  LastAdventure({this.city, this.country, this.countryCode, this.occurredAt});

  factory LastAdventure.fromJson(Map<String, dynamic> j) => LastAdventure(
        city: j['city'] as String?,
        country: j['country'] as String?,
        countryCode: j['country_code'] as String?,
        occurredAt: j['occurred_at'] == null
            ? null
            : DateTime.parse(j['occurred_at'] as String),
      );

  String get label => [city, country].whereType<String>().join(', ');
}

class CurrentJourney {
  final String id;
  final String title;
  final DateTime? startedAt;
  final int pointsCount;

  CurrentJourney({
    required this.id,
    required this.title,
    this.startedAt,
    required this.pointsCount,
  });

  factory CurrentJourney.fromJson(Map<String, dynamic> j) => CurrentJourney(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        startedAt:
            j['started_at'] == null ? null : DateTime.parse(j['started_at'] as String),
        pointsCount: (j['points_count'] ?? 0) as int,
      );
}

class Profile {
  final ProfileIdentity identity;
  final ProfileStats stats;
  final List<PassportStamp> passport;
  final LastAdventure? lastAdventure;
  final CurrentJourney? currentJourney;

  Profile({
    required this.identity,
    required this.stats,
    required this.passport,
    this.lastAdventure,
    this.currentJourney,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        identity: ProfileIdentity.fromJson(j['identity'] as Map<String, dynamic>),
        stats: ProfileStats.fromJson(j['stats'] as Map<String, dynamic>),
        passport: ((j['passport'] ?? []) as List)
            .map((e) => PassportStamp.fromJson(e as Map<String, dynamic>))
            .toList(),
        lastAdventure: j['last_adventure'] == null
            ? null
            : LastAdventure.fromJson(j['last_adventure'] as Map<String, dynamic>),
        currentJourney: j['current_journey'] == null
            ? null
            : CurrentJourney.fromJson(j['current_journey'] as Map<String, dynamic>),
      );

  /// Distância legível em pt-BR ("820 m", "12,4 km", "2.430 km"). Mesma regra do
  /// domínio do Atlas — o Perfil conta história, não expõe metros crus.
  String get trackedLabel {
    final meters = stats.trackedMeters;
    if (meters < 1000) return '${meters.round()} m';
    final km = meters / 1000;
    if (km < 100) return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
    final rounded = km.round().toString();
    return '${rounded.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')} km';
  }
}
