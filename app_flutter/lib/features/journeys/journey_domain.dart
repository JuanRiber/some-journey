/// # Jornadas — CAMADA DE DOMÍNIO (Dart puro, zero Flutter).
///
/// Uma jornada é um CAPÍTULO de uma vida. Aqui mora tudo o que as telas de
/// jornada precisam SABER sem desenhar: como o capítulo se nomeia e se data, o
/// que a pessoa pode fazer com ele em cada estado, em que ordem a estante o
/// apresenta e como as memórias viram as paradas do roteiro.
///
/// PORQUÊ fora das telas: a estante e a abertura do capítulo têm de falar com
/// a MESMA voz — e a voz ficava dentro de `screens/journeys.dart`, importada
/// pela outra tela como se uma fosse biblioteca da outra. Regra dentro de tela
/// só se testa montando a tela.
library;

import '../../models.dart';

const List<String> _meses = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

const List<String> _mesesCurtos = [
  'JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN',
  'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ',
];

String _monthYear(String iso) {
  final d = DateTime.parse(iso).toUtc();
  return '${_meses[d.month - 1]} de ${d.year}';
}

String _month(String iso) => _meses[DateTime.parse(iso).toUtc().month - 1];

bool _sameYear(String a, String b) =>
    DateTime.parse(a).toUtc().year == DateTime.parse(b).toUtc().year;

// ---------------------------------------------------------------------------
// A voz editorial: como o capítulo se nomeia e se data
// ---------------------------------------------------------------------------

/// Período compacto para overline/selo ("março — junho de 2026").
///
/// Dentro do mesmo ano, o ano aparece UMA vez: "fevereiro de 2019 — julho de
/// 2019" repetia o que não muda e não cabia numa linha de celular — a overline
/// da capa quebrava em duas.
String journeyPeriodLabel(Journey j) {
  if (j.startedAt != null && j.endedAt != null) {
    final a = _monthYear(j.startedAt!);
    final b = _monthYear(j.endedAt!);
    if (a == b) return a;
    if (_sameYear(j.startedAt!, j.endedAt!)) return '${_month(j.startedAt!)} — $b';
    return '$a — $b';
  }
  if (j.startedAt != null) return 'desde ${_monthYear(j.startedAt!)}';
  return _monthYear(j.createdAt);
}

/// O mesmo período, mas dito em voz de narrativa ("entre março e junho de
/// 2026") — para caber dentro de uma frase, não de um selo.
String journeyPeriodPhrase(Journey j) {
  if (j.startedAt != null && j.endedAt != null) {
    final a = _monthYear(j.startedAt!);
    final b = _monthYear(j.endedAt!);
    if (a == b) return 'em $a';
    if (_sameYear(j.startedAt!, j.endedAt!)) {
      return 'entre ${_month(j.startedAt!)} e $b';
    }
    return 'entre $a e $b';
  }
  if (j.startedAt != null) return 'desde ${_monthYear(j.startedAt!)}';
  return 'aberto em ${_monthYear(j.createdAt)}';
}

/// Linha curta de apoio no card (uma linha, sem ponto final).
String journeyMomentsLine(Journey j) => switch (j.pointsCount) {
      0 => 'Ainda sem momentos — este capítulo está em branco',
      1 => 'Um momento guardado',
      final n => '$n momentos guardados',
    };

/// Frase inteira do capítulo (momentos + período) para a abertura da jornada.
String journeyChapterStory(Journey j) {
  final periodo = journeyPeriodPhrase(j);
  return switch (j.pointsCount) {
    0 => 'Um capítulo em branco, $periodo — esperando o primeiro momento.',
    1 => 'Um momento registrado, $periodo.',
    final n => '$n momentos registrados, $periodo.',
  };
}

/// Rótulo humano do estado do capítulo (nunca o enum cru da API).
///
/// É o ÚNICO vocabulário de estado do app. A abertura da jornada tinha o seu
/// ("Ativa", "Pausada") e a estante o dela ("Em curso", "Em pausa"): a mesma
/// jornada mudava de nome ao ser aberta.
String journeyStatusLabel(String status) => switch (status) {
      'draft' => 'Rascunho',
      'active' => 'Em curso',
      'paused' => 'Em pausa',
      'finished' => 'Concluída',
      _ => status,
    };

// ---------------------------------------------------------------------------
// O que se pode fazer com o capítulo
// ---------------------------------------------------------------------------

/// As transições de ciclo de vida que a API oferece.
enum JourneyAction { start, pause, resume, finish }

/// Como a ação se chama no botão.
String journeyActionLabel(JourneyAction a) => switch (a) {
      JourneyAction.start => 'Iniciar jornada',
      JourneyAction.pause => 'Pausar',
      JourneyAction.resume => 'Retomar jornada',
      JourneyAction.finish => 'Finalizar jornada',
    };

/// O que o estado do capítulo permite — e qual dessas coisas LIDERA a tela.
///
/// PORQUÊ existe: a tela mostrava, na jornada em curso, três botões cheios do
/// mesmo peso — Finalizar, Gravar percurso e Nova memória —, e o primeiro
/// deles, logo abaixo do título, era justamente o que ENCERRA o capítulo. Uma
/// tela tem uma ação principal. Qual, depende de onde a jornada está:
///
/// - rascunho: começar ([lead] = start);
/// - em curso: guardar o que está acontecendo — a memória nova lidera
///   ([newMemoryLeads]), e pausar/finalizar ficam discretos;
/// - em pausa: retomar;
/// - concluída: nenhuma. O capítulo fechou, e não recebe memória nova.
class JourneyStage {
  const JourneyStage({
    this.lead,
    this.quiet = const [],
    this.acceptsMemories = true,
  });

  /// A transição que é a ação principal da tela, quando há uma.
  final JourneyAction? lead;

  /// As outras transições possíveis: existem, e não disputam com a principal.
  final List<JourneyAction> quiet;

  /// O capítulo ainda recebe memórias (novas ou trazidas).
  final bool acceptsMemories;

  /// Registrar uma memória é a ação principal — vale quando nenhuma transição
  /// lidera e o capítulo está aberto.
  bool get newMemoryLeads => lead == null && acceptsMemories;
}

JourneyStage journeyStage(String status) => switch (status) {
      'draft' => const JourneyStage(lead: JourneyAction.start),
      'active' => const JourneyStage(
          quiet: [JourneyAction.pause, JourneyAction.finish],
        ),
      'paused' => const JourneyStage(
          lead: JourneyAction.resume,
          quiet: [JourneyAction.finish],
        ),
      'finished' => const JourneyStage(acceptsMemories: false),
      // Estado que este app ainda não conhece: nenhuma transição oferecida (não
      // dá para saber qual vale), e a memória nova continua possível — é o que
      // a API recusa só para o capítulo concluído.
      _ => const JourneyStage(),
    };

// ---------------------------------------------------------------------------
// A estante
// ---------------------------------------------------------------------------

/// O capítulo está sendo vivido agora (em curso ou em pausa).
bool journeyInProgress(Journey j) => j.status == 'active' || j.status == 'paused';

int _shelfRank(Journey j) => switch (j.status) {
      'active' => 0,
      'paused' => 1,
      'draft' => 3,
      _ => 2,
    };

/// A ordem em que a estante apresenta os capítulos.
///
/// A API devolve por data de criação, e isso punha um rascunho em branco na
/// frente de tudo só por ter sido o último a nascer — enquanto a jornada que a
/// pessoa está VIVENDO ficava no meio da lista, igual às outras. Aqui: o que
/// está em curso abre a estante, depois o que está em pausa, depois os
/// capítulos guardados, e os rascunhos por último. Dentro de cada grupo a
/// ordem da API fica como veio (a ordenação é estável).
///
/// Vale para o que já foi carregado. Uma jornada em curso que só chegue numa
/// página seguinte sobe para a frente quando chegar — é raro (mais de trinta
/// capítulos) e é o lugar dela.
List<Journey> shelfOrder(List<Journey> journeys) {
  final indexed = [
    for (var i = 0; i < journeys.length; i++) (i, journeys[i]),
  ];
  indexed.sort((a, b) {
    final rank = _shelfRank(a.$2).compareTo(_shelfRank(b.$2));
    return rank != 0 ? rank : a.$1.compareTo(b.$1);
  });
  return [for (final (_, j) in indexed) j];
}

/// O capítulo que abre a estante em destaque: o que está sendo vivido, se
/// houver. Recebe a lista JÁ ordenada por [shelfOrder].
Journey? shelfLead(List<Journey> ordered) =>
    ordered.isNotEmpty && journeyInProgress(ordered.first) ? ordered.first : null;

// ---------------------------------------------------------------------------
// O roteiro: as memórias como paradas
// ---------------------------------------------------------------------------

/// Uma parada do roteiro: o ponto do rastro, com o que a memória dele tem para
/// mostrar.
class JourneyStop {
  const JourneyStop({
    required this.memoryId,
    required this.number,
    required this.title,
    required this.latitude,
    required this.longitude,
    required this.occurredAt,
    this.placeLabel,
    this.photoUrl,
    this.photoCount = 0,
    this.excerpt = '',
  });

  final String memoryId;

  /// A posição no rastro, contada de 1.
  final int number;
  final String title;
  final double latitude;
  final double longitude;
  final String occurredAt;
  final String? placeLabel;

  /// A primeira foto da memória, ou null — a parada vira nota tipográfica.
  final String? photoUrl;

  /// Quantas fotos a memória guarda. Mais de uma, a parada avisa.
  final int photoCount;

  /// O texto da memória numa linha só. Vazio quando não há texto, ou quando a
  /// memória ainda não chegou.
  final String excerpt;

  bool get hasTitle => title.trim().isNotEmpty;
  bool get hasPhoto => photoUrl != null;
}

/// Junta os pontos do rastro (que dão a ORDEM) com as memórias (que dão a foto
/// e o texto).
///
/// As duas listas vêm de pedidos diferentes, e a das memórias pode não ter
/// chegado — ou ter falhado. Nada disso tira uma parada do roteiro: sem a
/// memória, ela aparece com o que o ponto sabe (título, lugar, data) e ganha a
/// foto quando a memória chegar.
List<JourneyStop> itineraryStops(
  List<JourneyPoint> points,
  List<Memory> memories,
) {
  final byId = {for (final m in memories) m.id: m};
  return [
    for (var i = 0; i < points.length; i++)
      _stop(points[i], i, byId[points[i].memoryId]),
  ];
}

JourneyStop _stop(JourneyPoint p, int index, Memory? m) => JourneyStop(
      memoryId: p.memoryId,
      number: p.position ?? index + 1,
      title: p.title,
      latitude: p.latitude,
      longitude: p.longitude,
      occurredAt: p.occurredAt,
      placeLabel: p.placeLabel,
      photoUrl: m?.imageUrl ?? (m != null && m.images.isNotEmpty ? m.images.first.url : null),
      photoCount: m?.images.length ?? 0,
      excerpt: (m?.text ?? '').trim().replaceAll(RegExp(r'\s+'), ' '),
    );

/// A data da parada ("07 JUL 2018"), pelas partes UTC: `occurred_at` é
/// canonicamente o DIA em UTC, e pelo fuso do aparelho ele vazaria para a
/// véspera. Com o ano, ao contrário da timeline — lá o ano é o capítulo; uma
/// jornada pode atravessar a virada.
String stopDateLabel(String iso) {
  final d = DateTime.parse(iso).toUtc();
  return '${d.day.toString().padLeft(2, '0')} ${_mesesCurtos[d.month - 1]} ${d.year}';
}

/// A nova ordem dos ids quando a parada em [index] troca de lugar com a
/// vizinha ([dir] = -1 sobe, +1 desce). Devolve null quando não há para onde
/// ir — a primeira não sobe, a última não desce —, e aí nada vai ao servidor.
List<String>? movedOrder(List<String> ids, int index, int dir) {
  final target = index + dir;
  if (index < 0 || index >= ids.length || target < 0 || target >= ids.length) {
    return null;
  }
  final next = [...ids];
  final tmp = next[index];
  next[index] = next[target];
  next[target] = tmp;
  return next;
}
