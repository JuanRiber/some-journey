import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/illustrations.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../models.dart';
import '../widgets/api_error_view.dart';

// ---------------------------------------------------------------------------
// Vocabulário compartilhado da lane de jornadas
//
// PORQUÊ ficam aqui e não em cada tela: uma jornada é um CAPÍTULO de uma vida,
// e o capítulo tem de ser nomeado, datado e selado do MESMO jeito na lista e na
// abertura (`journey_detail.dart`) — se cada tela escrevesse seu próprio rótulo
// de status ou sua própria frase de período, o app perderia a voz. Estas
// funções são a "voz editorial" da lane.
// ---------------------------------------------------------------------------

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

String _monthYear(String iso) {
  final d = DateTime.parse(iso).toUtc();
  return '${_meses[d.month - 1]} de ${d.year}';
}

/// Esquema ativo da lane. O app ainda não envolve a árvore com [SJTheme]
/// (`main.dart` só alterna o `ThemeData`), então derivamos o esquema do brilho
/// do tema Material e reprovemos por dentro de cada tela — assim os componentes
/// do design system pintam no modo certo e o dia em que o modo escuro for
/// ligado no `MaterialApp` estas telas acompanham sem tocar em nada.
SJScheme journeyScheme(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? sjDark : sjLight;

/// Período compacto para overline/selo ("MARÇO DE 2026 — JUNHO DE 2026").
String journeyPeriodLabel(Journey j) {
  if (j.startedAt != null && j.endedAt != null) {
    final a = _monthYear(j.startedAt!);
    final b = _monthYear(j.endedAt!);
    return a == b ? a : '$a — $b';
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
    return a == b ? 'em $a' : 'entre $a e $b';
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
String journeyStatusLabel(String status) => switch (status) {
  'draft' => 'Rascunho',
  'active' => 'Em curso',
  'paused' => 'Em pausa',
  'finished' => 'Concluída',
  _ => status,
};

/// Cor do selo de estado: vinho para o que está vivo, mostarda para o que
/// espera, musgo para o que se fechou em paz, tinta suave para o rascunho.
Color journeyStatusColor(String status, SJScheme s) => switch (status) {
  'draft' => s.inkSoft,
  'active' => s.primary,
  'paused' => s.highlight,
  'finished' => s.moss,
  _ => s.inkSoft,
};

/// Itálico serifado da "atmosfera" da jornada — o afeto do diário (doc §2).
/// Composto só a partir dos tokens (família serif + escala body).
TextStyle journeyMoodStyle(SJScheme s) => TextStyle(
  fontFamily: SJType.serif,
  fontFamilyFallback: SJType.serifFallback,
  fontSize: SJType.bodySize,
  height: SJType.bodyLine / SJType.bodySize,
  fontStyle: FontStyle.italic,
  color: s.highlight,
);

/// Volta discreta em sans, com alvo de toque ≥44pt (o "← Voltar" do diário).
class JourneyBackLink extends StatelessWidget {
  const JourneyBackLink({super.key, this.label = 'Voltar', this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: SJPressable(
        semanticLabel: label,
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        pressedScale: 0.94,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.only(right: SJSpace.x3),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back, size: 18, color: s.inkSoft),
              const SizedBox(width: SJSpace.x2),
              Text(label, style: SJText.bodySm(color: s.inkSoft)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bloco que pulsa de leve enquanto os dados chegam (carregamento elegante em
/// vez de spinner genérico): a página já mostra o RITMO do conteúdo que vem.
class JourneySkeletonBox extends StatefulWidget {
  const JourneySkeletonBox({
    super.key,
    this.height = 16,
    this.width,
    this.radius = SJRadius.sm,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  State<JourneySkeletonBox> createState() => _JourneySkeletonBoxState();
}

class _JourneySkeletonBoxState extends State<JourneySkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SJMotion.page,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: s.inkFaint.withValues(alpha: 0.10 + 0.08 * _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Motivo de itinerário: uma linha tracejada com paradas — a mesma gramática do
/// rastro no mapa, reduzida a um selo gráfico. Usada nos capítulos SEM capa,
/// para o card não virar um retângulo de texto.
class JourneyRouteMotif extends StatelessWidget {
  const JourneyRouteMotif({super.key, required this.stops, this.color});

  final int stops;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Semantics(
      excludeSemantics: true,
      child: SizedBox(
        height: SJSpace.x3,
        width: double.infinity,
        child: CustomPaint(
          painter: _RouteMotifPainter(stops: stops, color: color ?? s.frame),
        ),
      ),
    );
  }
}

class _RouteMotifPainter extends CustomPainter {
  _RouteMotifPainter({required this.stops, required this.color});

  final int stops;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final line = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    // Trilha tracejada de ponta a ponta.
    for (double x = 0; x < size.width; x += 9) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + 5).clamp(0, size.width), y),
        line,
      );
    }

    // Paradas: no máximo cinco marcas, senão o selo vira ruído.
    final n = stops.clamp(2, 5);
    final dot = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      final x = size.width * (i / (n - 1));
      canvas.drawCircle(Offset(x.clamp(3, size.width - 3), y), 3, dot);
    }
  }

  @override
  bool shouldRepaint(_RouteMotifPainter old) =>
      old.stops != stops || old.color != color;
}

// ---------------------------------------------------------------------------
// Tela
// ---------------------------------------------------------------------------

/// Estante de capítulos: cada jornada é uma entrada do diário — capa dominante
/// quando existe foto, selo de estado, título em serifa e uma linha que conta a
/// história (nunca "156 memórias"). Ação primária única: começar um capítulo.
class JourneysScreen extends StatefulWidget {
  const JourneysScreen({super.key});

  @override
  State<JourneysScreen> createState() => _JourneysScreenState();
}

class _JourneysScreenState extends State<JourneysScreen> {
  List<Journey>? _journeys;
  ApiError? _error;

  /// Cursor da próxima página; nulo quando a estante acabou.
  String? _nextCursor;
  bool _loadingMore = false;

  /// Erro da PAGINAÇÃO, separado de [_error]: falhar ao buscar a próxima página
  /// não pode apagar os capítulos já lidos.
  String _moreError = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final page = await Api.instance.listJourneys();
      if (mounted) {
        setState(() {
          _journeys = page.items;
          _nextCursor = page.nextCursor;
          _moreError = '';
        });
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() => _error = e);
    }
  }

  /// Busca a próxima página e ANEXA à estante.
  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreError = '';
    });
    try {
      final page = await Api.instance.listJourneys(cursor: cursor);
      if (!mounted) return;
      setState(() {
        _journeys = [...?_journeys, ...page.items];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() {
        _moreError = e.message;
        _loadingMore = false;
      });
    }
  }

  Future<void> _openNew() async {
    await Navigator.of(context).pushNamed('/journey-new');
    _load();
  }

  Future<void> _open(Journey j) async {
    await Navigator.of(context).pushNamed('/journey', arguments: j.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = journeyScheme(context);
    final journeys = _journeys;

    return SJTheme(
      scheme: s,
      child: Scaffold(
        backgroundColor: s.bg,
        floatingActionButton: (journeys != null && journeys.isNotEmpty)
            ? Padding(
                padding: const EdgeInsets.only(bottom: SJSpace.x2),
                child: SJFab(
                  icon: Icons.add,
                  semanticLabel: 'Começar um novo capítulo',
                  onTap: _openNew,
                ),
              )
            : null,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: s.primary,
            backgroundColor: s.surface,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.axis == Axis.vertical &&
                    n.metrics.pixels >= n.metrics.maxScrollExtent - 600) {
                  _loadMore();
                }
                return false;
              },
              child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                SJSpace.screenX,
                SJSpace.x5,
                SJSpace.screenX,
                SJSpace.x16,
              ),
              children: [
                const JourneyBackLink(),
                const SizedBox(height: SJSpace.x4),
                const SJOverline('seus capítulos'),
                const SizedBox(height: SJSpace.x2),
                Text('Jornadas', style: SJText.display(color: s.ink)),
                const SizedBox(height: SJSpace.x2),
                Text(_headline(journeys), style: journeyMoodStyle(s)),
                const SizedBox(height: SJSpace.x8),
                if (_error != null)
                  _errorState(s)
                else if (journeys == null)
                  _loadingState()
                else if (journeys.isEmpty)
                  _emptyState()
                else
                  for (var i = 0; i < journeys.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: SJSpace.x6),
                      child: _chapterCard(journeys[i], i, s),
                    ),
                if (_nextCursor != null) _more(s),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }

  /// Continuação da estante enquanto houver páginas. Em erro, mantém o que já
  /// foi lido na tela e oferece o caminho de volta.
  Widget _more(SJScheme s) {
    if (_moreError.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SJSpace.x6),
        child: Column(
          children: [
            Text(
              _moreError,
              style: SJText.bodySm(color: s.inkSoft),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SJSpace.x4),
            SJButton(
              label: 'Carregar mais',
              variant: SJButtonVariant.secondary,
              onPressed: _loadMore,
            ),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: SJSpace.x8),
      child: Center(child: SJSpinner()),
    );
  }

  /// Abertura narrativa da estante — soma o que a pessoa já viveu, não conta
  /// registros ("Você já guardou 12 momentos em 3 capítulos.").
  String _headline(List<Journey>? journeys) {
    if (journeys == null || journeys.isEmpty) {
      return 'Sua vida contada através dos lugares.';
    }
    final momentos = journeys.fold<int>(0, (n, j) => n + j.pointsCount);
    final capitulos = journeys.length == 1
        ? 'um capítulo'
        : '${journeys.length} capítulos';
    if (momentos == 0) return 'Você abriu $capitulos — agora é hora de vivê-los.';
    if (momentos == 1) return 'Um momento guardado, em $capitulos.';
    return 'Você já guardou $momentos momentos em $capitulos.';
  }

  Widget _loadingState() => Column(
    children: List.generate(
      2,
      (i) => Padding(
        padding: const EdgeInsets.only(bottom: SJSpace.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            JourneySkeletonBox(height: 168, radius: SJRadius.lg),
            SizedBox(height: SJSpace.x4),
            JourneySkeletonBox(height: 20, width: 180),
            SizedBox(height: SJSpace.x2),
            JourneySkeletonBox(height: 12, width: 120),
          ],
        ),
      ),
    ),
  );

  Widget _emptyState() => SJEmptyState(
    illustration: const SJIllustration(kind: SJIllustrationKind.firstJourney),
    title: 'Seu primeiro capítulo',
    body:
        'Uma jornada é um trecho da sua vida — uma viagem, uma fase, uma cidade, '
        'uma rotina. Você dá um nome a ela e vai colecionando os lugares que '
        'importaram pelo caminho.',
    actionLabel: 'Criar primeira jornada',
    onAction: _openNew,
  );

  Widget _errorState(SJScheme s) => ApiErrorView(
    error: _error!,
    fallbackTitle: 'Não foi possível abrir suas jornadas',
    onRetry: _load,
  );

  /// Um capítulo. Com capa, a FOTO manda (o texto só complementa dentro do
  /// scrim); sem capa, um card silencioso com o selo de itinerário.
  Widget _chapterCard(Journey j, int index, SJScheme s) {
    final numeral = (index + 1).toString().padLeft(2, '0');
    final periodo = journeyPeriodLabel(j);
    final linha = journeyMomentsLine(j);
    final selo = SJBadge(
      journeyStatusLabel(j.status),
      color: journeyStatusColor(j.status, s),
    );
    final semantica =
        '${j.title}. ${journeyStatusLabel(j.status)}. $linha, $periodo.';

    if (j.coverImageUrl != null) {
      return Semantics(
        label: semantica,
        button: true,
        excludeSemantics: true,
        child: SJPhotoCard(
          title: j.title,
          overline: '$numeral  /  $periodo',
          subtitle: linha,
          aspectRatio: 4 / 3,
          trailing: selo,
          onTap: () => _open(j),
          imageChild: Image.network(
            j.coverImageUrl!,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : _coverFallback(s),
            errorBuilder: (_, _, _) => _coverFallback(s),
          ),
        ),
      );
    }

    return SJCard(
      onTap: () => _open(j),
      semanticLabel: semantica,
      padding: const EdgeInsets.all(SJSpace.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SJOverline(periodo, numeral: numeral)),
              const SizedBox(width: SJSpace.x3),
              selo,
            ],
          ),
          const SizedBox(height: SJSpace.x3),
          Text(
            j.title,
            style: SJText.h2(color: s.ink),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if ((j.description ?? '').isNotEmpty) ...[
            const SizedBox(height: SJSpace.x2),
            Text(
              j.description!,
              style: SJText.bodySm(color: s.inkSoft),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if ((j.mood ?? '').isNotEmpty) ...[
            const SizedBox(height: SJSpace.x2),
            Text(
              j.mood!,
              style: journeyMoodStyle(s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: SJSpace.x5),
          JourneyRouteMotif(stops: j.pointsCount),
          const SizedBox(height: SJSpace.x4),
          Row(
            children: [
              Expanded(
                child: Text(linha, style: SJText.caption(color: s.inkSoft)),
              ),
              if (!j.isPrivate) ...[
                const SizedBox(width: SJSpace.x2),
                SJChip(
                  label: 'pública',
                  icon: Icons.public,
                  color: s.secondary,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Capa ausente ou que falhou: areia com o selo de itinerário — nunca um
  /// retângulo cinza de erro.
  Widget _coverFallback(SJScheme s) => Container(
    color: s.surfaceAlt,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: SJSpace.x10),
    child: JourneyRouteMotif(stops: 4, color: s.frame),
  );
}
