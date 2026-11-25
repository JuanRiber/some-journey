import 'dart:math' as math;

import 'package:flutter/material.dart' hide Page;

import '../api.dart';
import '../design/components.dart';
import '../design/illustrations.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../features/journeys/journey_domain.dart';
import '../features/phases/phase_domain.dart';
import '../features/phases/phase_store.dart';
import '../features/phases/phase_widgets.dart';
import '../features/sync/data_changes.dart';
import '../features/sync/session_cache.dart';
import '../models.dart';
import '../widgets/api_error_view.dart';
import '../widgets/sj_image.dart';
import '../widgets/surge.dart';
import 'journey_new.dart';

// ---------------------------------------------------------------------------
// As peças visuais da lane de jornadas
//
// PORQUÊ ficam aqui e não em cada tela: uma jornada é um CAPÍTULO de uma vida,
// e o capítulo tem de ser selado e ilustrado do MESMO jeito na estante e na
// abertura (`journey_detail.dart`). O que o capítulo DIZ — período, estado,
// frase — é regra, e mora em `features/journeys/journey_domain.dart`; aqui
// fica só o que precisa de cor e de widget.
// ---------------------------------------------------------------------------

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

/// A tag do Hero que liga a capa na estante à capa na abertura do capítulo. A
/// mesma função nos dois lados — senão a foto não "cresce", só aparece.
String journeyCoverTag(String journeyId) => 'capa-jornada:$journeyId';

/// A capa de uma jornada, do jeito que a estante e a abertura a desenham.
///
/// É UMA peça para os dois lugares por causa do movimento: tocar numa capa da
/// estante faz a foto CRESCER até virar a capa do capítulo (o "foto que
/// cresce" do design system, §4) — e isso só acontece se os dois lados forem a
/// mesma imagem, com a mesma tag.
///
/// PORQUÊ o tamanho de decodificação é fixo ([_side]) e não o do espaço que a
/// foto ocupa, como no resto do app (`SJNetworkImage`): durante o voo a caixa
/// muda de tamanho a cada quadro, e decodificar "no tamanho do espaço" pediria
/// uma decodificação nova por quadro — a foto piscaria justamente na hora em
/// que tem de parecer uma coisa só. Com o lado fixo, a estante e a abertura
/// pedem exatamente a mesma imagem ao cache.
class JourneyCoverImage extends StatelessWidget {
  const JourneyCoverImage({
    super.key,
    required this.journeyId,
    required this.url,
  });

  final String journeyId;
  final String url;

  /// Lado de decodificação, em pontos. Cobre a capa do celular e a da folha na
  /// tela larga sem perder nitidez, e ainda é uma fração da foto original.
  static const double _side = 420;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final foto = ColoredBox(
      color: s.surfaceAlt,
      child: Image(
        image: sjFoto(context, url, lado: _side),
        fit: BoxFit.cover,
        // Uma releitura troca o token da URL, não a foto: a que está na tela
        // fica até a nova estar pronta.
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const _CoverFallback(),
      ),
    );
    // Quem pede menos movimento não recebe o voo: a capa nova já nasce no
    // lugar, com a transição comum da página.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return foto;
    return Hero(tag: journeyCoverTag(journeyId), child: foto);
  }
}

/// Capa que falhou ao carregar: areia com o selo de itinerário — nunca um
/// retângulo cinza de erro.
class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Container(
      color: s.surfaceAlt,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: SJSpace.x10),
      child: JourneyRouteMotif(stops: 4, color: s.frame),
    );
  }
}

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
///
/// **O que vem primeiro:** o capítulo que a pessoa está VIVENDO abre a estante,
/// em destaque; os rascunhos fecham (a regra é `shelfOrder`, no domínio). A
/// lista vinha por data de criação, e um rascunho em branco ficava na frente
/// de tudo só por ter sido o último a nascer.
///
/// **Duas composições**, com o corte do login ([SJLayout.wide]): no celular,
/// uma coluna de capas; na tela larga, a estante tem um teto
/// ([SJLayout.page]), o capítulo em curso vira uma faixa e os outros se
/// arrumam em grade. Sem isso a capa crescia com a janela até passar da altura
/// dela.
///
/// **Quando a rede cai** numa releitura, a estante que já estava na tela fica,
/// com um aviso de que pode estar velha. O erro só toma a página quando não há
/// nada para mostrar no lugar — e aí o "+" de criar não aparece.
class JourneysScreen extends StatefulWidget {
  const JourneysScreen({super.key});

  @override
  State<JourneysScreen> createState() => _JourneysScreenState();
}

/// A última estante vista (a vida toda, primeira página), para a tela abrir já
/// preenchida enquanto relê.
final _estanteEmCache = SessionCache<Page<Journey>>();

/// Busca a estante ANTES de alguém pedir, para ela abrir preenchida já na
/// primeira vez. Chamado quando as abas sobem (ver tabs.dart). Em silêncio: se
/// falhar, a tela busca de novo ao abrir, como sempre fez.
Future<void> aquecerEstante() async {
  if (_estanteEmCache.valor != null) return;
  try {
    _estanteEmCache.valor = await Api.instance.listJourneys();
  } catch (_) {}
}

class _JourneysScreenState extends State<JourneysScreen>
    with AtualizaQuandoMuda<JourneysScreen> {
  List<Journey>? _journeys;
  ApiError? _error;

  /// Cursor da próxima página; nulo quando a estante acabou.
  String? _nextCursor;
  bool _loadingMore = false;

  /// Erro da PAGINAÇÃO, separado de [_error]: falhar ao buscar a próxima página
  /// não pode apagar os capítulos já lidos.
  String _moreError = '';

  final _phases = PhaseStore.instance;

  /// A fase pela qual a estante está sendo lida; null é a vida toda. É a mesma
  /// lente da timeline e do atlas: entram as jornadas marcadas na fase e as que
  /// têm alguma memória dela (a regra mora no backend).
  String? _phaseId;

  /// A lente mudou e a estante nova ainda não chegou: a antiga fica, esmaecida.
  bool _trocandoLente = false;

  /// Capítulos já mostrados — só o que chega de novo faz o surgimento.
  final Set<String> _vistas = {};

  @override
  void initState() {
    super.initState();
    _phases.addListener(_onPhases);
    // Abre com a última estante vista; a releitura logo abaixo a troca.
    final guardada = _estanteEmCache.valor;
    if (guardada != null) {
      _journeys = guardada.items;
      _nextCursor = guardada.nextCursor;
      _vistas.addAll(guardada.items.map((j) => j.id));
    }
    _load();
  }

  @override
  void dadosMudaram() => _load();

  @override
  void dispose() {
    _phases.removeListener(_onPhases);
    super.dispose();
  }

  /// Se a fase da lente foi apagada noutra tela, a estante volta para a vida
  /// toda em vez de ficar pedindo uma fase que responde 404.
  void _onPhases() {
    if (!mounted) return;
    final valida = lensFor(_phases.value, _phaseId);
    if (valida != _phaseId) {
      _setLens(valida);
    } else {
      setState(() {});
    }
  }

  /// Troca a lente e relê do começo — o cursor só vale com o mesmo filtro.
  void _setLens(String? phaseId) {
    if (phaseId == _phaseId) return;
    setState(() {
      _phaseId = phaseId;
      _trocandoLente = _journeys != null;
      _nextCursor = null;
      _moreError = '';
    });
    _load();
  }

  Future<void> _load() async {
    final lente = _phaseId;
    setState(() => _error = null);
    _phases.refresh();
    try {
      final page = await Api.instance.listJourneys(phaseId: lente);
      // A lente mudou enquanto esta página vinha: ela é de outra estante.
      if (mounted && lente == _phaseId) {
        if (lente == null) _estanteEmCache.valor = page;
        setState(() {
          _journeys = page.items;
          _nextCursor = page.nextCursor;
          _moreError = '';
          _trocandoLente = false;
        });
      }
    } on ApiError catch (e) {
      if (!mounted || lente != _phaseId) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      // 404 com lente é a fase apagada noutro aparelho: volta para a vida toda.
      if (lente != null && e.status == 404) {
        _setLens(null);
        return;
      }
      setState(() {
        _error = e;
        // A estante que ficou na tela é a da lente ANTERIOR: deixá-la sob o
        // nome da fase nova mostraria capítulos que não são dela. Sem lente
        // trocando, o que está na tela é o que a pessoa pediu — e fica.
        if (_trocandoLente) _journeys = null;
        _trocandoLente = false;
      });
    }
  }

  /// Busca a próxima página e ANEXA à estante.
  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    final lente = _phaseId;
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreError = '';
    });
    try {
      final page = await Api.instance.listJourneys(cursor: cursor, phaseId: lente);
      if (!mounted) return;
      if (lente != _phaseId) {
        setState(() => _loadingMore = false);
        return;
      }
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

  /// Nova jornada. Com a lente ligada, ela já nasce marcada na fase que a
  /// pessoa está olhando — é o capítulo que ela tinha em mente.
  Future<void> _openNew() async {
    await Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: '/journey-new'),
      builder: (_) => JourneyNewScreen(initialPhaseId: _phaseId),
    ));
  }

  /// Abre o capítulo. A estante se relê sozinha se algo for gravado lá dentro
  /// (AtualizaQuandoMuda); só olhar não custa uma ida à rede na volta.
  Future<void> _open(Journey j) async {
    await Navigator.of(context).pushNamed('/journey', arguments: j.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final journeys = _journeys;

    return Scaffold(
      backgroundColor: s.bg,
      // O "+" só existe com a estante na tela: sem conexão, um botão de criar
      // flutuando sobre o aviso seria um convite a falhar de novo.
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
            child: LayoutBuilder(
              builder: (context, box) {
                final largo = box.maxWidth >= SJLayout.wide;
                // Na tela larga a estante tem um teto e fica no meio da
                // janela. Passou dele, sobra margem — nunca uma capa do
                // tamanho da tela.
                final margem = largo
                    ? math.max(SJSpace.x8, (box.maxWidth - SJLayout.page) / 2)
                    : SJSpace.screenX;
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    margem,
                    SJSpace.x5,
                    margem,
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
                    if (_phases.value.isNotEmpty) ...[
                      const SizedBox(height: SJSpace.x5),
                      PhaseLens(
                        phases: _phases.value,
                        selected: _phaseId,
                        onChanged: _setLens,
                      ),
                    ],
                    // Uma releitura que falha NÃO apaga a estante que já
                    // estava na tela: a pessoa continua lendo, e fica sabendo
                    // que o que vê pode estar velho.
                    if (journeys != null && _error != null) ...[
                      const SizedBox(height: SJSpace.x4),
                      Text(
                        'Não deu para atualizar agora — você está vendo a '
                        'estante como estava.',
                        style: SJText.caption(color: s.inkSoft),
                      ),
                    ],
                    const SizedBox(height: SJSpace.x8),
                    if (journeys == null && _error != null)
                      _errorState(s)
                    else if (journeys == null)
                      _loadingState()
                    else if (journeys.isEmpty)
                      _emptyState()
                    else
                      _shelf(
                        s,
                        shelfOrder(journeys),
                        largo: largo,
                        width: box.maxWidth - 2 * margem,
                      ),
                    if (_nextCursor != null) _more(s),
                  ],
                );
              },
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
    final fase = phaseById(_phases.value, _phaseId);
    if (fase != null) {
      final n = journeys?.length ?? 0;
      if (journeys == null || n == 0) return 'Os capítulos da fase “${fase.name}”.';
      return n == 1
          ? 'Um capítulo na fase “${fase.name}”.'
          : '$n capítulos na fase “${fase.name}”.';
    }
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

  Widget _emptyState() {
    final fase = phaseById(_phases.value, _phaseId);
    if (fase != null) {
      // Vazio COM lente não é estante vazia: é uma fase sem capítulo ainda.
      return SJEmptyState(
        title: 'Nenhuma jornada nesta fase ainda.',
        body: 'Marque uma jornada com “${fase.name}” — ou uma memória dela — e '
            'ela aparece aqui.',
        actionLabel: 'Ver a vida toda',
        onAction: () => _setLens(null),
      );
    }
    return _emptyStateGeral();
  }

  Widget _emptyStateGeral() => SJEmptyState(
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

  // As medidas da grade larga, num lugar só.

  /// A partir desta largura de estante cabem três capas por fileira com folga
  /// para o título; abaixo, duas.
  static const double _threeColumnsFrom = 1000;

  /// Na faixa do capítulo em curso: quanto dela é a foto, e o piso de altura.
  static const double _bandPhoto = 0.6;
  static const double _bandMinHeight = 340;

  /// A estante. O capítulo que está sendo vivido abre em destaque; os outros
  /// vêm depois, na ordem de `shelfOrder`.
  ///
  /// No celular é uma coluna de capas. Na tela larga, o destaque vira uma
  /// faixa (a capa de um lado, a abertura do capítulo do outro) e o resto se
  /// arruma em grade — três capas por fileira quando cabem, duas quando não.
  Widget _shelf(
    SJScheme s,
    List<Journey> ordered, {
    required bool largo,
    required double width,
  }) {
    final lead = shelfLead(ordered);

    Widget surgir(Journey j, Widget card) => SJSurge(
          key: ValueKey(j.id),
          ativo: _vistas.add(j.id),
          child: AnimatedOpacity(
            // Trocando de lente, a estante anterior esmaece.
            opacity: _trocandoLente ? 0.4 : 1,
            duration: SJMotion.fast,
            child: card,
          ),
        );

    if (!largo) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final j in ordered)
            Padding(
              padding: const EdgeInsets.only(bottom: SJSpace.x6),
              child: surgir(j, _chapterCard(j, s, lead: identical(j, lead))),
            ),
        ],
      );
    }

    const gap = SJSpace.x6;
    final rest = lead == null ? ordered : ordered.sublist(1);
    final colunas = width >= _threeColumnsFrom ? 3 : 2;
    // Arredonda para baixo: um resto de ponto flutuante na soma empurraria a
    // última capa da fileira para a linha seguinte.
    final lado = ((width - gap * (colunas - 1)) / colunas).floorToDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lead != null)
          Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: surgir(lead, _leadBand(lead, s, width: width)),
          ),
        Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final j in rest)
              SizedBox(
                width: lado,
                child: surgir(j, _chapterCard(j, s, lead: false)),
              ),
          ],
        ),
      ],
    );
  }

  String _semantica(Journey j) => '${j.title}. ${journeyStatusLabel(j.status)}. '
      '${journeyMomentsLine(j)}, ${journeyPeriodLabel(j)}.';

  Widget _selo(Journey j, SJScheme s) => SJBadge(
        journeyStatusLabel(j.status),
        color: journeyStatusColor(j.status, s),
      );

  /// Um capítulo. Com capa, a FOTO manda (o texto só complementa dentro do
  /// scrim); sem capa, um card silencioso com o selo de itinerário.
  ///
  /// [lead]: o capítulo em curso ganha uma capa mais alta — é a única
  /// diferença de tamanho da estante, e ela diz "é aqui que você está".
  ///
  /// Sem numeral de propósito. O "01 /" contava a posição na lista, e a lista
  /// é por data de criação: o capítulo 03 virava 04 no dia em que nascia uma
  /// jornada nova. Número que muda sozinho não numera nada.
  Widget _chapterCard(Journey j, SJScheme s, {required bool lead}) {
    final periodo = journeyPeriodLabel(j);
    final linha = journeyMomentsLine(j);
    final selo = _selo(j, s);
    final semantica = _semantica(j);

    if (j.coverImageUrl != null) {
      return Semantics(
        label: semantica,
        button: true,
        excludeSemantics: true,
        child: SJPhotoCard(
          title: j.title,
          overline: periodo,
          subtitle: linha,
          aspectRatio: lead ? 1 : 4 / 3,
          trailing: selo,
          onTap: () => _open(j),
          imageChild: JourneyCoverImage(journeyId: j.id, url: j.coverImageUrl!),
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
              Expanded(child: SJOverline(periodo)),
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

  /// O capítulo em curso, na tela larga: uma faixa com a capa de um lado e a
  /// abertura do capítulo do outro. É a única peça da estante que diz mais do
  /// que o nome — a frase, a atmosfera e a porta para continuar.
  ///
  /// A altura é um PISO: quem manda é o texto. A capa é que se estica para
  /// acompanhá-lo (posicionada, do topo ao pé) — com altura fixa, um título de
  /// três linhas empurrava o botão para fora da faixa.
  Widget _leadBand(Journey j, SJScheme s, {required double width}) {
    final capa = j.coverImageUrl;
    final atmosfera = (j.mood ?? '').trim();
    // Três quintos para a foto: ela é a protagonista, e a coluna de texto
    // ainda fica com uma linha confortável de ler.
    final fotoW = capa == null ? 0.0 : (width * _bandPhoto).floorToDouble();
    return Semantics(
      label: _semantica(j),
      button: true,
      excludeSemantics: true,
      child: SJPressable(
        onTap: () => _open(j),
        pressedScale: 0.995,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: BorderRadius.circular(SJRadius.lg),
            boxShadow: SJElevation.e1(s),
          ),
          child: Stack(
            children: [
              if (capa != null)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: fotoW,
                  child: JourneyCoverImage(journeyId: j.id, url: capa),
                ),
              Container(
                constraints: const BoxConstraints(minHeight: _bandMinHeight),
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.fromLTRB(
                  fotoW + SJSpace.x8,
                  SJSpace.x8,
                  SJSpace.x8,
                  SJSpace.x8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _selo(j, s),
                    const SizedBox(height: SJSpace.x4),
                    SJOverline(journeyPeriodLabel(j)),
                    const SizedBox(height: SJSpace.x2),
                    Text(j.title, style: SJText.h1(color: s.ink)),
                    const SizedBox(height: SJSpace.x3),
                    Text(
                      journeyChapterStory(j),
                      style: SJText.bodySm(color: s.inkSoft),
                    ),
                    if (atmosfera.isNotEmpty) ...[
                      const SizedBox(height: SJSpace.x2),
                      Text(atmosfera, style: journeyMoodStyle(s)),
                    ],
                    const SizedBox(height: SJSpace.x5),
                    SJButton(
                      label: 'Continuar jornada',
                      variant: SJButtonVariant.secondary,
                      trailingIcon: Icons.arrow_forward,
                      expand: true,
                      onPressed: () => _open(j),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
