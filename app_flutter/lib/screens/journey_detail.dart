import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/illustrations.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../features/atlas/atlas_domain.dart';
import '../features/journeys/journey_domain.dart';
import '../features/journeys/journey_stops.dart';
import '../features/phases/phase_widgets.dart';
import '../features/sync/seen.dart';
import '../features/tracks/track_list.dart';
import '../features/tracks/track_panel.dart';
import '../features/tracks/track_recorder.dart';
import '../models.dart';
import '../widgets/api_error_view.dart';
import '../widgets/atlas_map.dart';
import '../widgets/common.dart';
import '../widgets/surge.dart';
// As peças visuais da lane de jornadas (selo de estado, atmosfera, a capa que
// cresce) moram na estante: a abertura de um capítulo tem de se desenhar com a
// MESMA mão da lista.
import 'journeys.dart';

/// # Jornada aberta — a abertura de um capítulo
///
/// **Por que existe:** a estante mostra a capa; aqui o capítulo se abre. É onde
/// a foto, o mapa e a história de uma jornada se encontram — e também onde ela
/// é gerida (ciclo de vida, percurso, ordem das memórias).
///
/// **O que a pessoa sente:** que abriu um capítulo do próprio diário, não a
/// ficha de um cadastro. Por isso a página é lida de cima para baixo como uma
/// abertura: a CAPA sangrando no topo com o nome por cima, a frase do
/// capítulo, o caminho no mapa e as memórias como um roteiro ilustrado.
///
/// **Ação principal:** uma, e depende de onde a jornada está (a regra é
/// `journeyStage`, no domínio): começar o rascunho, guardar uma memória na
/// jornada em curso, retomar a que está em pausa. Pausar e finalizar existem e
/// não disputam com ela — finalizar encerra o capítulo, e era o botão mais
/// vistoso da tela.
///
/// **A gestão fica recolhida.** Subir, descer e tirar uma memória do rastro
/// são coisa de arrumar, não de ler: aparecem ao tocar em "Organizar". Com os
/// três controles sempre à vista, cada memória era uma linha de administração
/// com o título cortado para caber nos botões.
///
/// **Duas composições**, com o mesmo corte do login ([SJLayout.wide]):
/// - **coluna** (celular): capa, abertura, mapa em prancha, roteiro;
/// - **folha sobre o mapa** (tela larga): o MAPA sangra na janela inteira,
///   como a arte do login, e o capítulo é uma folha de papel de largura fixa
///   pousada sobre ele. O mapa deixa de prender a rolagem — a folha rola, ele
///   fica.
///
/// **Estados:** abre com o que já está na mão (a capa que a estante mostrou, a
/// jornada vista antes) e relê por baixo; sem nada na mão, o esqueleto tem o
/// ritmo da página; se a jornada não abre, a notícia vem da natureza da falha
/// ([ApiErrorView]); capítulo sem memória ensina o primeiro passo.
class JourneyDetailScreen extends StatefulWidget {
  final String journeyId;
  const JourneyDetailScreen({super.key, required this.journeyId});

  @override
  State<JourneyDetailScreen> createState() => _JourneyDetailScreenState();
}

class _JourneyDetailScreenState extends State<JourneyDetailScreen> {
  // As medidas desta tela, num lugar só. O que é do design system vem dos
  // tokens; estas são da composição da página.

  /// A capa no celular: dois quintos da tela — é a primeira coisa que se vê, e
  /// ainda sobra a frase do capítulo acima da dobra. Com piso e teto, para não
  /// virar uma tira num celular deitado nem a tela inteira num tablet.
  static const double _coverFraction = 0.42;
  static const double _coverMin = 260;
  static const double _coverMax = 380;

  /// A capa dentro da folha, na tela larga.
  static const double _sheetCover = 300;

  /// O mapa em prancha, na coluna. Menor que a tela de propósito: quem rola a
  /// página precisa de papel acima e abaixo dele para pôr o dedo.
  static const double _mapHeight = 300;

  /// As ilustrações de estado dentro da página (não na tela inteira).
  static const double _illustration = 120;

  /// O diâmetro do "+" — o do [SJFab], repetido aqui porque a tela larga
  /// precisa dele para pousar o botão no canto da folha.
  static const double _fabSize = 56;

  /// Nasce com a última versão vista desta jornada nesta sessão (ver
  /// features/sync/seen.dart): reabrir não passa pelo esqueleto.
  late JourneyDetail? _journey = jornadasVistas[widget.journeyId];

  /// O que a ESTANTE mostrou deste capítulo: basta para a capa e a abertura
  /// nascerem no lugar enquanto os pontos não chegam — e é o que dá à foto da
  /// estante um destino para onde crescer.
  late final Journey? _shelved = capitulosVistos[widget.journeyId];

  /// As memórias do capítulo, com foto e texto: o que ilustra o roteiro.
  late List<Memory> _memories = roteirosVistos[widget.journeyId] ?? const [];

  /// Por que a jornada não abriu. Só existe enquanto não há jornada na tela.
  ApiError? _failure;

  /// A jornada não existe mais (apagada noutro lugar).
  bool _gone = false;

  /// Erro de uma AÇÃO (pausar, reordenar…), mostrado junto dela.
  String _error = '';
  bool _busy = false;

  /// Mapa da jornada (percurso real + distância). Carregado à parte do detalhe
  /// porque só ele conhece os trechos de GPS.
  late JourneyMap? _map = percursosVistos[widget.journeyId]?.map;

  /// Trechos gravados. Vêm da listagem, não do mapa: o mapa traz a geometria
  /// para desenhar, a listagem traz a identidade de cada trecho — que é o que
  /// permite remover um sem tocar nos outros.
  late List<JourneyTrack> _tracks =
      percursosVistos[widget.journeyId]?.tracks ?? const [];
  TrackRecorder? _recorder;
  bool _confirmDelete = false;
  List<JourneyPoint>? _loose; // pontos soltos para vincular (null = fechado)

  /// O roteiro está sendo arrumado: as paradas viram linhas com os controles.
  bool _arranging = false;

  /// Paradas que já apareceram uma vez — só a que chega de novo faz o
  /// surgimento. Reordenar não é chegar.
  final Set<String> _shown = {};

  /// O que há para desenhar no topo: a jornada, ou o que a estante sabia dela.
  Journey? get _header => _gone ? null : (_journey ?? _shelved);

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Busca o percurso real. Falha aqui NÃO derruba a tela: a jornada continua
  /// legível sem o traço de GPS.
  ///
  /// As duas leituras saem JUNTAS: uma não depende da outra, e em fila a
  /// segunda só começava quando a primeira voltava dos EUA.
  Future<void> _loadMap(String id) async {
    try {
      final (m, t) =
          await (Api.instance.journeyMap(id), Api.instance.listTracks(id)).wait;
      percursosVistos[id] = (map: m, tracks: t);
      if (mounted) {
        setState(() {
          _map = m;
          _tracks = t;
        });
      }
    } catch (_) {
      // sem percurso é um estado válido, não um erro
    }
  }

  /// Busca as memórias do capítulo. Também não derruba nada: sem elas o
  /// roteiro continua inteiro, só que sem foto — cada parada com o que o ponto
  /// do rastro já sabe (ver `itineraryStops`).
  Future<void> _loadMemories(String id) async {
    try {
      final memorias = await Api.instance.journeyMemories(id);
      if (mounted) setState(() => _memories = memorias);
    } catch (_) {
      // roteiro sem foto é um estado válido, não um erro
    }
  }

  /// Abre a edição e recarrega se algo mudou. A tela devolve `true` só quando
  /// gravou de fato — voltar sem mexer não custa uma requisição.
  Future<void> _openEdit(String id) async {
    final mudou =
        await Navigator.of(context).pushNamed('/journey-edit', arguments: id);
    if (!mounted || mudou != true) return;
    await _load();
  }

  /// Remove um trecho e recarrega o que depende dele.
  ///
  /// O traço some do mapa e a distância total encolhe; as memórias da jornada
  /// não são tocadas — o backend guarda percurso e memória em tabelas distintas
  /// justamente para que apagar um caminho não apague o que se viveu nele.
  Future<void> _deleteTrack(JourneyTrack t) async {
    try {
      await Api.instance.deleteTrack(t.journeyId, t.id);
      await _loadMap(t.journeyId);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      // Trecho que já não existe (toque duplo, lista desatualizada) não é falha:
      // o resultado que a pessoa queria já aconteceu. Só recarrega, em vez de
      // acusar um erro que ela não pode resolver.
      if (e.isNotFound) {
        await _loadMap(t.journeyId);
        return;
      }
      setState(() => _error = e.message);
    }
  }

  Future<void> _load() async {
    // O percurso e as memórias não esperam a jornada: os pedidos saem de uma
    // vez, e a tela se completa na ordem em que eles voltam. Falha em qualquer
    // um dos dois não é erro (ver _loadMap e _loadMemories), então eles correm
    // por fora deste try.
    final percurso = _loadMap(widget.journeyId);
    final roteiro = _loadMemories(widget.journeyId);
    // Tentando de novo depois de uma falha: a notícia sai e o esqueleto volta,
    // para o toque em "Tentar de novo" ter resposta na hora.
    if (_failure != null) setState(() => _failure = null);
    try {
      final data = await Api.instance.getJourney(widget.journeyId);
      // Pausar ou finalizar a jornada PARA a gravação. Antes, o painel apenas
      // sumia da tela e o gravador seguia vivo: GPS ligado e lotes subindo,
      // sem nenhum botão à vista para interromper.
      if (data.status != 'active' && (_recorder?.isRecording ?? false)) {
        await _recorder!.stop();
      }
      if (mounted) {
        setState(() {
          _journey = data;
          _failure = null;
        });
      }
      await percurso;
      await roteiro;
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      if (e.isNotFound) {
        // Apagada noutro lugar: o que estava em mãos não vale mais.
        jornadasVistas.remove(widget.journeyId);
        percursosVistos.remove(widget.journeyId);
        capitulosVistos.remove(widget.journeyId);
        roteirosVistos.remove(widget.journeyId);
        setState(() {
          _journey = null;
          _gone = true;
        });
        return;
      }
      setState(() {
        // Com a jornada na tela, a falha de uma releitura é um aviso junto das
        // ações; sem ela, é a notícia da página inteira.
        if (_journey == null) {
          _failure = e;
        } else {
          _error = e.message;
        }
      });
    }
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await fn();
      await _load();
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _recorder?.dispose();
    super.dispose();
  }

  Future<void> _openAdd() async {
    try {
      final map = await Api.instance.getMap();
      if (mounted) setState(() => _loose = map.loosePoints);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _openMemory(String id) =>
      Navigator.of(context).pushNamed('/memory', arguments: id);

  Future<void> _newMemory(String journeyId) async {
    await Navigator.of(context).pushNamed('/memory-new', arguments: journeyId);
    if (mounted) _load();
  }

  Future<Journey> _transition(JourneyAction action, String id) =>
      switch (action) {
        JourneyAction.start => Api.instance.startJourney(id),
        JourneyAction.pause => Api.instance.pauseJourney(id),
        JourneyAction.resume => Api.instance.resumeJourney(id),
        JourneyAction.finish => Api.instance.finishJourney(id),
      };

  Future<void> _move(JourneyDetail j, int index, int dir) async {
    final ordem = movedOrder([for (final p in j.points) p.memoryId], index, dir);
    if (ordem == null) return;
    await _run(() => Api.instance.reorderJourneyPoints(j.id, ordem));
  }

  /// O mapa só conhece este capítulo: os pontos dele e a linha que os liga.
  MapResponse? _mapData(JourneyDetail? j) => j == null
      ? null
      : MapResponse(loosePoints: const [], journeys: [
          MapJourney(
            id: j.id,
            title: j.title,
            status: j.status,
            points: j.points,
            route: j.route,
          ),
        ]);

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Scaffold(
      backgroundColor: s.bg,
      body: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= SJLayout.wide
            ? _wide(s)
            : _narrow(s, box.maxWidth),
      ),
    );
  }

  /// O "+" da jornada em curso: guardar uma memória é a ação principal dela, e
  /// uma ação principal não pode morar depois do mapa e de todas as paradas —
  /// a tela de quem está viajando abriria sem o botão que ela veio usar. É o
  /// mesmo gesto do "+" da barra de abas, já apontado para este capítulo.
  ///
  /// Só existe quando é isso que lidera (`journeyStage`): no rascunho e na
  /// pausa quem lidera é começar ou retomar, e dois botões cheios disputariam.
  Widget? _fab() {
    final j = _journey;
    if (j == null || !journeyStage(j.status).newMemoryLeads) return null;
    return SJFab(
      icon: Icons.add,
      size: _fabSize,
      semanticLabel: 'Nova memória nesta jornada',
      onTap: () {
        if (!_busy) _newMemory(j.id);
      },
    );
  }

  // ── Composição estreita: coluna ───────────────────────────────────────────

  Widget _narrow(SJScheme s, double width) {
    final media = MediaQuery.of(context);
    // Num tablet em pé a coluna ainda é uma só, mas o TEXTO não acompanha a
    // largura: a margem cresce e a leitura fica com a medida da folha. A capa
    // continua sangrando de borda a borda — é imagem, não linha de texto.
    final gutter = math.max(SJSpace.screenX, (width - SJLayout.sheet) / 2);
    final capa = (media.size.height * _coverFraction)
        .clamp(_coverMin, _coverMax);
    final fab = _fab();
    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.only(
            // Com o "+" na tela, o fim da página sobe o bastante para ele não
            // ficar em cima de "Excluir jornada".
            bottom: (fab == null ? SJSpace.x12 : SJSpace.x16 + SJSpace.x8) +
                media.padding.bottom,
          ),
          children: _page(
            s,
            gutter: gutter,
            edge: SJSpace.screenX,
            coverHeight: capa,
            topInset: media.padding.top,
            withMap: true,
          ),
        ),
        if (fab != null)
          Positioned(
            right: SJSpace.x5,
            bottom: SJSpace.x5 + media.padding.bottom,
            child: fab,
          ),
      ],
    );
  }

  // ── Composição larga: a folha sobre o mapa ────────────────────────────────

  Widget _wide(SJScheme s) {
    final media = MediaQuery.of(context);
    final fab = _fab();
    return Stack(
      fit: StackFit.expand,
      children: [
        // O mapa é a arte desta tela: sangra até as bordas, sem moldura, e
        // enquadra o rastro no que a folha deixa à vista.
        AtlasMap(
          data: _mapData(_journey),
          trackLines: _map?.trackLines,
          onSelect: _openMemory,
          height: null,
          framed: false,
          covered: const EdgeInsets.only(left: SJLayout.sheet + SJSpace.x6),
        ),
        Positioned(
          left: SJSpace.x6,
          top: SJSpace.x6 + media.padding.top,
          bottom: SJSpace.x6 + media.padding.bottom,
          width: SJLayout.sheet,
          // A folha é do papel da PÁGINA (`bg`), não de `surface`: dentro dela
          // moram cartões, e cartão sobre cartão da mesma cor não levanta.
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: s.bg,
              borderRadius: BorderRadius.circular(SJRadius.xl),
              boxShadow: SJElevation.e2(s),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SJRadius.xl),
              child: ListView(
                padding: EdgeInsets.only(
                  bottom: fab == null ? SJSpace.x10 : SJSpace.x16 + SJSpace.x8,
                ),
                children: _page(
                  s,
                  gutter: SJSpace.x8,
                  edge: SJSpace.x8,
                  coverHeight: _sheetCover,
                  topInset: 0,
                  withMap: false,
                ),
              ),
            ),
          ),
        ),
        // O "+" pousa no canto da FOLHA, não no da janela: a ação é do
        // capítulo, e no canto da tela ela ficaria sozinha sobre o mar.
        if (fab != null)
          Positioned(
            left: SJSpace.x6 + SJLayout.sheet - SJSpace.x5 - _fabSize,
            bottom: SJSpace.x6 + SJSpace.x5 + media.padding.bottom,
            child: fab,
          ),
      ],
    );
  }

  // ── A página (a mesma nas duas composições) ───────────────────────────────

  /// [withMap]: na coluna o mapa é um bloco da página; na tela larga ele já é
  /// o fundo, e repeti-lo dentro da folha seria o mesmo desenho duas vezes.
  ///
  /// [gutter] é a margem do TEXTO; [edge], a dos botões que flutuam sobre a
  /// capa. São a mesma coisa quase sempre — só num tablet em pé o texto recua
  /// para a medida de leitura e os botões continuam junto da borda da tela.
  List<Widget> _page(
    SJScheme s, {
    required double gutter,
    required double edge,
    required double coverHeight,
    required double topInset,
    required bool withMap,
  }) {
    Widget dentro(Widget child, {double top = 0}) => Padding(
          padding: EdgeInsets.fromLTRB(gutter, top, gutter, 0),
          child: child,
        );

    final header = _header;
    if (header == null) {
      return [
        _barOnPaper(s, gutter: edge, topInset: topInset),
        if (_gone)
          SJEmptyState(
            illustration: const SJIllustration(
              kind: SJIllustrationKind.empty,
              size: _illustration,
            ),
            title: 'Este capítulo não está mais aqui.',
            body: 'A jornada foi excluída. As memórias dela continuam no seu '
                'álbum.',
            actionLabel: 'Voltar',
            onAction: () => Navigator.of(context).maybePop(),
          )
        else if (_failure != null)
          ApiErrorView(
            error: _failure!,
            fallbackTitle: 'Não conseguimos abrir esta jornada.',
            onRetry: _load,
            illustrationSize: _illustration,
          )
        else
          dentro(_skeleton(coverHeight)),
      ];
    }

    final j = _journey;
    return [
      _cover(s, header,
          gutter: gutter,
          edge: edge,
          height: coverHeight,
          topInset: topInset),
      dentro(_opening(s, header), top: SJSpace.x6),
      if (j == null && _failure != null)
        // A capa veio da estante e o resto não abriu: a notícia fica abaixo do
        // que já se sabe, sem apagar o nome do capítulo.
        ApiErrorView(
          error: _failure!,
          fallbackTitle: 'Não conseguimos abrir esta jornada.',
          onRetry: _load,
          illustrationSize: _illustration,
        )
      else if (j == null)
        dentro(_bodySkeleton(), top: SJSpace.x8)
      else ...[
        dentro(_lifecycle(s, j)),
        dentro(InlineError(_error)),
        // Gravar percurso só faz sentido com a jornada em andamento: um
        // capítulo encerrado não recebe caminho novo.
        if (j.status == 'active')
          dentro(
            TrackPanel(
              recorder: _recorder ??= TrackRecorder(journeyId: j.id),
              onFinished: () => _loadMap(j.id),
            ),
            top: SJSpace.x6,
          ),
        if (withMap && (j.points.isNotEmpty || (_map?.hasRealTrack ?? false)))
          dentro(_mapBlock(s, j), top: SJSpace.x8),
        if (!withMap && (_map?.distanceMeters ?? 0) > 0)
          dentro(_distance(s), top: SJSpace.x6),
        // Fora do bloco do mapa de propósito: os trechos precisam ser vistos e
        // removidos mesmo numa jornada encerrada, quando o painel de gravação
        // já não aparece.
        if (_tracks.isNotEmpty)
          dentro(
            TrackList(tracks: _tracks, onDelete: _deleteTrack),
            top: SJSpace.x6,
          ),
        dentro(_itinerary(s, j), top: SJSpace.x10),
        dentro(_deleteSection(s, j), top: SJSpace.x10),
      ],
    ];
  }

  // ── Capa ──────────────────────────────────────────────────────────────────

  Widget _cover(
    SJScheme s,
    Journey r, {
    required double gutter,
    required double edge,
    required double height,
    required double topInset,
  }) {
    final url = r.coverImageUrl;
    return Stack(
      children: [
        SJCover(
          title: r.title,
          overline: journeyPeriodLabel(r),
          badge: SJBadge(
            journeyStatusLabel(r.status),
            color: journeyStatusColor(r.status, s),
          ),
          // Sem foto a capa é uma faixa de papel, e papel não precisa de dois
          // quintos da tela para dizer um nome.
          minHeight: url == null ? height * 0.7 : height,
          topInset: topInset + SJIconButton.target,
          gutter: gutter,
          sealLegend: journeyStatusLabel(r.status).toUpperCase(),
          image: url == null ? null : JourneyCoverImage(journeyId: r.id, url: url),
        ),
        Positioned(
          top: topInset + SJSpace.x1,
          left: edge - SJSpace.x2,
          right: edge - SJSpace.x2,
          child: Row(
            children: [
              SJIconButton(
                icon: Icons.arrow_back,
                semanticLabel: 'Voltar',
                disc: true,
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              // Editar mora no cabeçalho, junto do que se edita. Só com a
              // jornada inteira na mão: a edição abre a partir dela.
              if (_journey != null)
                SJIconButton(
                  icon: Icons.edit_outlined,
                  semanticLabel: 'Editar jornada',
                  disc: true,
                  onTap: () => _openEdit(r.id),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// A barra de voltar quando não há capa para pousar (carregando do zero,
  /// erro, jornada que sumiu).
  Widget _barOnPaper(SJScheme s, {required double gutter, required double topInset}) =>
      Padding(
        padding: EdgeInsets.fromLTRB(
          gutter - SJSpace.x2,
          topInset + SJSpace.x1,
          gutter,
          0,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SJIconButton(
            icon: Icons.arrow_back,
            semanticLabel: 'Voltar',
            disc: true,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
      );

  // ── Abertura ──────────────────────────────────────────────────────────────

  /// A frase do capítulo, o que a pessoa escreveu sobre ele e as marcas que
  /// ele carrega. Tudo o que a estante já sabia — por isso aparece antes de o
  /// detalhe chegar.
  Widget _opening(SJScheme s, Journey r) {
    final descricao = (r.description ?? '').trim();
    final atmosfera = (r.mood ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(journeyChapterStory(r), style: _storyStyle(s)),
        if (descricao.isNotEmpty) ...[
          const SizedBox(height: SJSpace.x4),
          Text(descricao, style: SJText.body(color: s.ink)),
        ],
        if (atmosfera.isNotEmpty) ...[
          const SizedBox(height: SJSpace.x2),
          Text(atmosfera, style: journeyMoodStyle(s)),
        ],
        if (r.lifePhaseId != null || !r.isPrivate) ...[
          const SizedBox(height: SJSpace.x4),
          Wrap(
            spacing: SJSpace.x4,
            runSpacing: SJSpace.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (r.lifePhaseId != null) PhaseTag(phaseId: r.lifePhaseId),
              if (!r.isPrivate)
                SJChip(label: 'pública', icon: Icons.public, color: s.secondary),
            ],
          ),
        ],
      ],
    );
  }

  /// Serifa itálica da frase do capítulo (a "letra do diário"), composta só a
  /// partir dos tokens.
  TextStyle _storyStyle(SJScheme s) => TextStyle(
        fontFamily: SJType.serif,
        fontFamilyFallback: SJType.serifFallback,
        fontSize: SJType.bodySize,
        height: SJType.bodyLine / SJType.bodySize,
        fontStyle: FontStyle.italic,
        color: s.inkSoft,
      );

  // ── Ciclo de vida ─────────────────────────────────────────────────────────

  /// As transições do capítulo. A que lidera é um botão; as outras são links —
  /// e a jornada em curso não tem botão aqui: a ação principal dela é guardar
  /// uma memória, lá no roteiro.
  Widget _lifecycle(SJScheme s, JourneyDetail j) {
    final stage = journeyStage(j.status);
    if (stage.lead == null && stage.quiet.isEmpty) return const SizedBox.shrink();

    VoidCallback? agir(JourneyAction a) =>
        _busy ? null : () => _run(() => _transition(a, j.id));

    return Padding(
      padding: const EdgeInsets.only(top: SJSpace.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stage.lead != null)
            SJButton(
              label: journeyActionLabel(stage.lead!),
              expand: true,
              onPressed: agir(stage.lead!),
            ),
          if (stage.quiet.isNotEmpty)
            // Recuo negativo do tamanho do respiro do link: o TEXTO alinha com
            // a margem da página, não a caixa de toque dele.
            Transform.translate(
              offset: const Offset(-SJSpace.x2, 0),
              child: Wrap(
                spacing: SJSpace.x2,
                children: [
                  for (final a in stage.quiet)
                    // O botão ocupa a largura que lhe derem; `IntrinsicWidth`
                    // o deixa do tamanho do rótulo, para os links ficarem
                    // lado a lado em vez de um por linha.
                    IntrinsicWidth(
                      child: SJButton(
                        label: journeyActionLabel(a),
                        variant: SJButtonVariant.text,
                        onPressed: agir(a),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Mapa ──────────────────────────────────────────────────────────────────

  Widget _mapBlock(SJScheme s, JourneyDetail j) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SJOverline('O caminho'),
          const SizedBox(height: SJSpace.x3),
          Semantics(
            label: 'Mapa desta jornada. Toque num pin para abrir a memória.',
            container: true,
            child: AtlasMap(
              data: _mapData(j),
              trackLines: _map?.trackLines,
              onSelect: _openMemory,
              height: _mapHeight,
            ),
          ),
          if ((_map?.distanceMeters ?? 0) > 0) ...[
            const SizedBox(height: SJSpace.x3),
            _distance(s),
          ],
        ],
      );

  Widget _distance(SJScheme s) => Text(
        '${AtlasDomain.formatDistance(_map!.distanceMeters)} percorridos'
            .toUpperCase(),
        style: SJText.overline(color: s.accent),
      );

  // ── Roteiro ───────────────────────────────────────────────────────────────

  Widget _itinerary(SJScheme s, JourneyDetail j) {
    final stage = journeyStage(j.status);
    final stops = itineraryStops(j.points, _memories);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sem memória não há o que intitular nem o que organizar: o convite
        // fala sozinho, sem um cabeçalho de seção vazia por cima.
        if (stops.isNotEmpty) ...[
          SJSectionHeader(
            overline: 'As memórias',
            title: 'Na ordem do rastro',
            action: SJButton(
              label: _arranging ? 'Concluir' : 'Organizar',
              variant: SJButtonVariant.text,
              onPressed: () => setState(() => _arranging = !_arranging),
            ),
          ),
          const SizedBox(height: SJSpace.x5),
        ],
        if (stops.isEmpty)
          _emptyItinerary(s, stage)
        else
          // Entrar e sair da arrumação troca a natureza das linhas; o fade
          // curto explica que são as mesmas memórias, vistas de outro jeito.
          AnimatedSwitcher(
            duration: SJMotion.base,
            switchInCurve: SJMotion.standard,
            switchOutCurve: SJMotion.standard,
            layoutBuilder: (atual, anteriores) => Stack(
              alignment: Alignment.topCenter,
              children: [...anteriores, ?atual],
            ),
            child: Column(
              key: ValueKey(_arranging),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < stops.length; i++)
                  _arranging
                      ? JourneyArrangeRow(
                          key: ValueKey('arrumar-${stops[i].memoryId}'),
                          stop: stops[i],
                          onUp: _busy || i == 0 ? null : () => _move(j, i, -1),
                          onDown: _busy || i == stops.length - 1
                              ? null
                              : () => _move(j, i, 1),
                          onRemove: _busy
                              ? null
                              : () => _run(() => Api.instance
                                  .unlinkJourneyPoint(j.id, stops[i].memoryId)),
                        )
                      // Só a parada que CHEGA faz o surgimento; reordenar e
                      // sair da arrumação não são chegar.
                      : SJSurge(
                          key: ValueKey(stops[i].memoryId),
                          ativo: _shown.add(stops[i].memoryId),
                          child: JourneyStopTile(
                            stop: stops[i],
                            first: i == 0,
                            last: i == stops.length - 1,
                            onOpen: () => _openMemory(stops[i].memoryId),
                          ),
                        ),
              ],
            ),
          ),
        if (stage.acceptsMemories) ...[
          const SizedBox(height: SJSpace.x4),
          // De apoio em todos os estados: na jornada em curso a ação cheia é
          // o "+" flutuante (ver [_fab]); no rascunho e na pausa, é começar ou
          // retomar. Este fica onde o roteiro acaba — o lugar natural de quem
          // leu as paradas e quer acrescentar mais uma.
          SJButton(
            label: 'Nova memória nesta jornada',
            icon: Icons.add,
            expand: true,
            variant: SJButtonVariant.secondary,
            onPressed: _busy ? null : () => _newMemory(j.id),
          ),
          const SizedBox(height: SJSpace.x2),
          if (_loose == null)
            Center(
              child: SJButton(
                label: 'Trazer uma memória que já existe',
                variant: SJButtonVariant.text,
                onPressed: _busy ? null : _openAdd,
              ),
            )
          else
            _looseBox(s, j),
        ],
      ],
    );
  }

  /// Capítulo sem memória: diz o que falta e deixa os dois caminhos logo
  /// abaixo (os botões do roteiro). Concluído e vazio não tem próximo passo a
  /// ensinar — só o fato.
  Widget _emptyItinerary(SJScheme s, JourneyStage stage) => SJEmptyState(
        illustration: const SJIllustration(
          kind: SJIllustrationKind.noMemories,
          size: _illustration,
        ),
        // Convite, não diagnóstico: a frase do capítulo, lá em cima, já disse
        // que ele está em branco.
        title: stage.acceptsMemories
            ? 'Guarde o primeiro momento.'
            : 'Este capítulo fechou sem memórias.',
        body: stage.acceptsMemories
            ? 'Registre uma memória aqui dentro — ou traga uma que você já '
                'guardou — e ela vira a primeira parada deste mapa.'
            : 'Uma jornada concluída não recebe memórias novas.',
      );

  /// As memórias soltas do atlas, para trazer para dentro do capítulo.
  Widget _looseBox(SJScheme s, JourneyDetail j) {
    final loose = _loose!;
    return Container(
      padding: const EdgeInsets.all(SJSpace.x4),
      decoration: BoxDecoration(
        // Um véu do azul-lago — a mesma cor que marca o ponto SOLTO no atlas,
        // aqui só como fundo da caixa que os traz para dentro da jornada.
        color: s.secondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SJRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SJOverline('Memórias soltas'),
          const SizedBox(height: SJSpace.x3),
          if (loose.isEmpty)
            Text(
              'Nenhuma memória solta para trazer.',
              style: SJText.bodySm(color: s.inkSoft),
            )
          else
            for (final m in loose)
              Padding(
                padding: const EdgeInsets.only(bottom: SJSpace.x2),
                child: Container(
                  padding: const EdgeInsets.only(left: SJSpace.x4),
                  decoration: BoxDecoration(
                    color: s.surface,
                    borderRadius: BorderRadius.circular(SJRadius.md),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        // Esta lista existe para ESCOLHER uma memória entre
                        // outras, e o título é o único discriminador. Sem ele
                        // a linha fica anônima e a escolha vira sorteio —
                        // então aqui a data entra no lugar.
                        child: Text(
                          m.hasTitle ? m.title : stopDateLabel(m.occurredAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SJText.title(color: s.ink),
                        ),
                      ),
                      SJButton(
                        label: 'Adicionar',
                        variant: SJButtonVariant.text,
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                  await Api.instance
                                      .addJourneyPoint(j.id, m.memoryId);
                                  setState(() => _loose = _loose!
                                      .where((x) => x.memoryId != m.memoryId)
                                      .toList());
                                }),
                      ),
                    ],
                  ),
                ),
              ),
          Center(
            child: SJButton(
              label: 'Fechar',
              variant: SJButtonVariant.text,
              onPressed: () => setState(() => _loose = null),
            ),
          ),
        ],
      ),
    );
  }

  // ── Excluir ───────────────────────────────────────────────────────────────

  Widget _deleteSection(SJScheme s, JourneyDetail j) {
    if (!_confirmDelete) {
      return Center(
        child: SJPressable(
          semanticLabel: 'Excluir jornada',
          pressedScale: 0.94,
          onTap: () => setState(() => _confirmDelete = true),
          child: Container(
            constraints: const BoxConstraints(minHeight: SJIconButton.target),
            padding: const EdgeInsets.symmetric(horizontal: SJSpace.x3),
            alignment: Alignment.center,
            child: Text(
              'Excluir jornada',
              style: SJText.bodySm(color: s.danger, weight: FontWeight.w600),
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        Text(
          'Excluir esta jornada? As memórias não são apagadas.',
          textAlign: TextAlign.center,
          style: SJText.bodySm(color: s.ink, weight: FontWeight.w600),
        ),
        const SizedBox(height: SJSpace.x3),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: SJSpace.x3,
          children: [
            // A ação em destaque é a que não destrói nada.
            IntrinsicWidth(
              child: SJButton(
                label: 'Manter jornada',
                onPressed: () => setState(() => _confirmDelete = false),
              ),
            ),
            IntrinsicWidth(
              child: SJButton(
                label: 'Sim, excluir',
                variant: SJButtonVariant.secondary,
                onPressed: _busy
                    ? null
                    : () async {
                        try {
                          await Api.instance.deleteJourney(j.id);
                          if (mounted) Navigator.of(context).pop();
                        } on ApiError catch (e) {
                          if (mounted) setState(() => _error = e.message);
                        }
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Espera ────────────────────────────────────────────────────────────────

  /// Nada na mão: o esqueleto tem o ritmo da página — a capa, a frase, o
  /// corpo.
  Widget _skeleton(double coverHeight) => Semantics(
        label: 'Carregando a jornada',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: SJSpace.x4),
            JourneySkeletonBox(height: coverHeight * 0.6, radius: SJRadius.lg),
            const SizedBox(height: SJSpace.x6),
            const JourneySkeletonBox(height: SJSpace.x6, width: 220),
            const SizedBox(height: SJSpace.x3),
            const JourneySkeletonBox(height: SJSpace.x4, width: 280),
            const SizedBox(height: SJSpace.x8),
            _bodySkeleton(),
          ],
        ),
      );

  /// A capa veio da estante; falta o resto. Só o corpo espera.
  Widget _bodySkeleton() => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JourneySkeletonBox(height: 160, radius: SJRadius.lg),
          SizedBox(height: SJSpace.x5),
          JourneySkeletonBox(height: SJSpace.x5, width: 180),
          SizedBox(height: SJSpace.x3),
          JourneySkeletonBox(height: 120, radius: SJRadius.lg),
        ],
      );
}
