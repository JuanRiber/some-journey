/// # Coleção — CAMADA DE DOMÍNIO (Dart puro, zero Flutter).
///
/// Os números do Perfil ("37 cidades", "212 fotos") são portas: tocar num
/// deles abre o que ele conta. Aqui moram os recortes que essas portas abrem
/// ([MemoryFilter]), as listas que o backend agrupa por trás de "cidades",
/// "países" e "dias no app", e os textos que as telas mostram sobre elas.
library;

const _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

const _semana = [
  'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo',
];

/// "1 memória" / "3 memórias" — o número sempre com a palavra no número certo.
String countLabel(int n, String singular, String plural) =>
    '$n ${n == 1 ? singular : plural}';

/// Um recorte das memórias, na forma que `GET /memories` entende.
///
/// Tudo opcional e combinável; o filtro vazio é a coleção inteira. A cidade
/// vai com o país quando se sabe o país: Valencia existe na Espanha e na
/// Venezuela, e só o par abre a certa.
class MemoryFilter {
  const MemoryFilter({
    this.city,
    this.countryCode,
    this.hasImages = false,
    this.createdOn,
  });

  /// Toda a coleção, sem recorte.
  static const all = MemoryFilter();

  final String? city;
  final String? countryCode;
  final bool hasImages;

  /// O dia do REGISTRO (`AAAA-MM-DD`), não o dia em que aconteceu.
  final String? createdOn;

  bool get isEmpty =>
      city == null && countryCode == null && !hasImages && createdOn == null;

  /// Os parâmetros da querystring. Só entra o que recorta: mandar
  /// `has_images=false` seria ruído numa URL que também vira cursor.
  Map<String, String> toQuery() => {
        'city': ?city,
        'country_code': ?countryCode,
        if (hasImages) 'has_images': 'true',
        'created_on': ?createdOn,
      };

  @override
  bool operator ==(Object other) =>
      other is MemoryFilter &&
      other.city == city &&
      other.countryCode == countryCode &&
      other.hasImages == hasImages &&
      other.createdOn == createdOn;

  @override
  int get hashCode => Object.hash(city, countryCode, hasImages, createdOn);
}

/// Uma cidade da coleção e quantas memórias moram nela.
class CityEntry {
  const CityEntry({
    required this.city,
    required this.memories,
    this.country,
    this.countryCode,
  });

  factory CityEntry.fromJson(Map<String, dynamic> j) => CityEntry(
        city: j['city'] as String,
        country: j['country'] as String?,
        countryCode: j['country_code'] as String?,
        memories: (j['memories'] as num).toInt(),
      );

  final String city;
  final String? country;
  final String? countryCode;
  final int memories;

  MemoryFilter get filter => MemoryFilter(city: city, countryCode: countryCode);
}

/// Um país da coleção: quantas memórias e em quantas cidades.
class CountryEntry {
  const CountryEntry({
    required this.countryCode,
    required this.memories,
    required this.cities,
    this.country,
  });

  factory CountryEntry.fromJson(Map<String, dynamic> j) => CountryEntry(
        countryCode: j['country_code'] as String,
        country: j['country'] as String?,
        memories: (j['memories'] as num).toInt(),
        cities: (j['cities'] as num).toInt(),
      );

  final String countryCode;
  final String? country;
  final int memories;
  final int cities;

  /// O nome quando o geocodificador deu um; o código quando não — melhor
  /// "PT" do que uma linha em branco.
  String get name {
    final n = country?.trim() ?? '';
    return n.isNotEmpty ? n : countryCode;
  }

  MemoryFilter get filter => MemoryFilter(countryCode: countryCode);
}

/// `GET /me/places`: as cidades e os países por trás dos números do Perfil.
class Places {
  const Places({required this.cities, required this.countries});

  factory Places.fromJson(Map<String, dynamic> j) => Places(
        cities: [
          for (final c in (j['cities'] ?? const []) as List)
            CityEntry.fromJson(c as Map<String, dynamic>),
        ],
        countries: [
          for (final c in (j['countries'] ?? const []) as List)
            CountryEntry.fromJson(c as Map<String, dynamic>),
        ],
      );

  final List<CityEntry> cities;
  final List<CountryEntry> countries;
}

/// Um dia em que a pessoa registrou algo, e quantas memórias nasceram nele.
class DayEntry {
  const DayEntry({required this.day, required this.memories});

  factory DayEntry.fromJson(Map<String, dynamic> j) => DayEntry(
        day: j['day'] as String,
        memories: (j['memories'] as num).toInt(),
      );

  /// `AAAA-MM-DD`, exatamente como o backend agrupa.
  final String day;
  final int memories;

  MemoryFilter get filter => MemoryFilter(createdOn: day);
}

/// As partes de um `AAAA-MM-DD`, lidas como texto: o dia é o do calendário,
/// não um instante — passar por `DateTime.parse` local poderia empurrá-lo
/// para o dia vizinho conforme o fuso do aparelho.
(int, int, int) _partes(String isoDay) {
  final p = isoDay.split('-');
  return (int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// "10 de março de 2026".
String dayLabel(String isoDay) {
  final (ano, mes, dia) = _partes(isoDay);
  return '$dia de ${_meses[mes - 1]} de $ano';
}

/// "terça" — o dia da semana daquele dia do calendário (em UTC, onde a data
/// é só uma data).
String weekdayLabel(String isoDay) {
  final (ano, mes, dia) = _partes(isoDay);
  return _semana[DateTime.utc(ano, mes, dia).weekday - 1];
}

/// "março de 2026" — o cabeçalho que agrupa os dias por mês.
String monthLabel(String isoDay) {
  final (ano, mes, _) = _partes(isoDay);
  return '${_meses[mes - 1]} de $ano';
}
