/// # Fases da vida — as regras (domínio puro)
///
/// Uma fase é um CAPÍTULO que a pessoa reconhece na própria história:
/// infância, recomeços, o intercâmbio. O app não oferece lista pronta e não
/// pede que ninguém use fase alguma — quem nunca criar uma usa o produto
/// inteiro sem perceber que isto existe. Por isso as telas só desenham o
/// seletor e a lente quando há fase para escolher.
///
/// Aqui é Dart puro: sem Flutter, sem rede, sem relógio. A cor é um PAPEL da
/// paleta e não um `Color` justamente para isto continuar testável sem montar
/// árvore nenhuma — quem pinta é `phase_widgets.dart`.
///
/// Os limites e as mensagens espelham `backend/app/domain/life_phase.py`.
/// Validar aqui é não gastar uma viagem de rede para dizer que o nome está
/// vazio; a autoridade continua lá, e o que esta camada não sabe volta pelo 422
/// já escrito em pt-BR.
library;

/// `NOME_MAX` em `app/domain/life_phase.py`.
const int phaseNameMax = 60;

/// `DESCRICAO_MAX` em `app/domain/life_phase.py`.
const int phaseDescriptionMax = 280;

/// Os papéis da paleta que uma fase pode vestir — os MESMOS nomes de `CORES`
/// no backend e dos tokens de `SJScheme`, então nada traduz nada.
///
/// Cor livre não existe de propósito: o que é legível no papel quente some no
/// atlas noturno, e estes cinco já têm contraste conferido nos dois modos.
enum PhaseColor {
  primary('Vinho'),
  secondary('Lago'),
  accent('Couro'),
  moss('Musgo'),
  highlight('Terracota');

  const PhaseColor(this.label);

  /// Como a cor é chamada na tela — o nome do token não é para quem usa.
  final String label;

  /// A padrão do backend (`COR_PADRAO`).
  static const PhaseColor standard = PhaseColor.accent;

  /// Lê o papel que veio da API. Um valor desconhecido (uma cor nova no
  /// backend antes de o app aprender) cai na padrão em vez de derrubar a
  /// leitura da lista inteira.
  static PhaseColor parse(String? raw) {
    for (final c in values) {
      if (c.name == raw) return c;
    }
    return standard;
  }
}

/// Uma fase como a API devolve.
///
/// As datas são guardadas como DIA (`AAAA-MM-DD`), igual à data da memória:
/// o app envia meio-dia em UTC, e ler as partes UTC devolve exatamente o dia
/// escolhido, em qualquer fuso do aparelho.
class LifePhase {
  final String id;
  final String name;
  final String? description;
  final PhaseColor color;

  /// Nulo quando a pessoa não sabe quando a fase começou.
  final String? startedOn;

  /// Nulo na fase em curso.
  final String? endedOn;

  const LifePhase({
    required this.id,
    required this.name,
    this.description,
    this.color = PhaseColor.standard,
    this.startedOn,
    this.endedOn,
  });

  factory LifePhase.fromJson(Map<String, dynamic> j) => LifePhase(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        description: j['description'] as String?,
        color: PhaseColor.parse(j['color'] as String?),
        startedOn: _day(j['started_at'] as String?),
        endedOn: _day(j['ended_at'] as String?),
      );

  /// "2019 — 2023", "desde 2019", "até 2010" — ou vazio, quando a pessoa não
  /// deu período nenhum. Só o ano: fase é coisa longa, e "março de 2019" leria
  /// como a data de uma memória, não como o começo de um capítulo.
  String get period {
    final inicio = startedOn == null ? null : _year(startedOn!);
    final fim = endedOn == null ? null : _year(endedOn!);
    if (inicio != null && fim != null) {
      return inicio == fim ? '$inicio' : '$inicio — $fim';
    }
    if (inicio != null) return 'desde $inicio';
    if (fim != null) return 'até $fim';
    return '';
  }
}

/// O dia (`AAAA-MM-DD`) de um instante da API, pelas partes UTC.
String? _day(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final d = DateTime.tryParse(iso);
  if (d == null) return null;
  final u = d.toUtc();
  return '${u.year.toString().padLeft(4, '0')}-'
      '${u.month.toString().padLeft(2, '0')}-'
      '${u.day.toString().padLeft(2, '0')}';
}

int _year(String day) => int.parse(day.substring(0, 4));

/// Meio-dia em UTC do dia escolhido — a mesma âncora da data da memória, que
/// mantém o dia inteiro em qualquer fuso. Vazio vira null: sem data.
String? _instant(String day) => day.isEmpty ? null : '${day}T12:00:00Z';

/// O que impede salvar, ou null quando está tudo certo. As frases são as do
/// backend, para a pessoa não ler duas versões do mesmo aviso.
String? validatePhase({
  required String name,
  String startedOn = '',
  String endedOn = '',
}) {
  final nome = name.trim();
  if (nome.isEmpty) return 'Dê um nome a esta fase.';
  if (nome.length > phaseNameMax) {
    return 'O nome pode ter no máximo $phaseNameMax caracteres.';
  }
  // `AAAA-MM-DD` ordena como texto na mesma ordem que como data.
  if (startedOn.isNotEmpty &&
      endedOn.isNotEmpty &&
      endedOn.compareTo(startedOn) < 0) {
    return 'Uma fase não pode terminar antes de começar.';
  }
  return null;
}

/// O corpo do POST. Campo em branco não vai: o backend já entende ausência
/// como "não tem", e mandar menos é ter menos para dar errado.
Map<String, dynamic> phaseCreateBody({
  required String name,
  String description = '',
  PhaseColor color = PhaseColor.standard,
  String startedOn = '',
  String endedOn = '',
}) {
  final d = description.trim();
  return {
    'name': name.trim(),
    if (d.isNotEmpty) 'description': d,
    'color': color.name,
    'started_at': ?_instant(startedOn),
    'ended_at': ?_instant(endedOn),
  };
}

/// O corpo do PATCH com o que REALMENTE mudou.
///
/// Aqui `null` LIMPA — é o contrário do PATCH de jornada, e é de propósito no
/// backend: uma fase que ganhou fim por engano precisa voltar a ser a fase em
/// curso, e para data não existe o truque da string vazia. Então apagar a data
/// de fim manda `ended_at: null`, e deixar como estava não manda nada.
Map<String, dynamic> phasePatch(
  LifePhase original, {
  required String name,
  required String description,
  required PhaseColor color,
  required String startedOn,
  required String endedOn,
}) {
  final patch = <String, dynamic>{};
  final n = name.trim();
  if (n != original.name) patch['name'] = n;

  final d = description.trim();
  if (d != (original.description ?? '')) {
    patch['description'] = d.isEmpty ? null : d;
  }
  if (color != original.color) patch['color'] = color.name;
  if (startedOn != (original.startedOn ?? '')) {
    patch['started_at'] = _instant(startedOn);
  }
  if (endedOn != (original.endedOn ?? '')) {
    patch['ended_at'] = _instant(endedOn);
  }
  return patch;
}

/// O pedaço do PATCH de memória ou jornada que cuida da fase.
///
/// Vai só quando mudou. E `null` aqui SOLTA — a exceção deliberada ao "null
/// não mexe" daqueles PATCHes, porque um id não tem string vazia que o
/// substitua. Mandar sempre, mesmo sem mudança, seria inofensivo hoje e uma
/// armadilha no dia em que duas telas editarem a mesma memória.
Map<String, dynamic> phaseLinkPatch(String? before, String? after) =>
    before == after ? const {} : {'life_phase_id': after};

/// A fase pela qual a lente está olhando, ainda válida — ou null (a vida toda).
///
/// A fase escolhida pode ter sido apagada noutra tela enquanto esta estava
/// aberta. Continuar filtrando por ela daria 404 a cada recarga; voltar para a
/// vida toda é a leitura honesta de "essa fase não existe mais".
String? lensFor(List<LifePhase> phases, String? selected) {
  if (selected == null) return null;
  return phases.any((p) => p.id == selected) ? selected : null;
}

/// A fase com este id, ou null.
LifePhase? phaseById(List<LifePhase> phases, String? id) {
  if (id == null) return null;
  for (final p in phases) {
    if (p.id == id) return p;
  }
  return null;
}
