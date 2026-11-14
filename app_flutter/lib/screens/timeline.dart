import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/illustrations.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../features/phases/phase_domain.dart';
import '../features/phases/phase_store.dart';
import '../features/phases/phase_widgets.dart';
import '../features/sync/data_changes.dart';
import '../models.dart';
import '../widgets/api_error_view.dart';
import '../widgets/sj_image.dart';
import '../widgets/surge.dart';
import 'memory_new.dart';

const _meses = ['JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN', 'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ'];

/// occurred_at é canonicamente o DIA em UTC; formatamos pelas partes UTC para
/// a data não "vazar" para outro dia conforme o fuso do aparelho.
String _dayMonth(String iso) {
  final d = DateTime.parse(iso).toUtc();
  return '${d.day.toString().padLeft(2, '0')} ${_meses[d.month - 1]}';
}

int _yearOf(String iso) => DateTime.parse(iso).toUtc().year;

/// Coordenada em linguagem de atlas ("23.55° S · 46.63° O") em vez de dois
/// números com sinal. É o mesmo dado — só deixou de parecer log de sistema.
String _coords(double lat, double lng) {
  final ns = lat >= 0 ? 'N' : 'S';
  final eo = lng >= 0 ? 'L' : 'O';
  return '${lat.abs().toStringAsFixed(2)}° $ns · ${lng.abs().toStringAsFixed(2)}° $eo';
}

/// Colapsa o corpo da memória numa linha de apoio (o texto inteiro é o prêmio da
/// tela de detalhe; aqui ele só dá um gosto do que vem).
String _excerpt(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ');

/// # Timeline — o ÁLBUM do atlas
///
/// PORQUÊ esta tela existe: o mapa mostra ONDE; a timeline mostra a HISTÓRIA. Ela
/// é lida como um álbum encadernado, dividido em CAPÍTULOS (um por ano) — não
/// como uma lista infinita de registros.
///
/// Decisões de anatomia:
/// - **Abertura de capítulo**: o ano é um numeral mono grande no acento, seguido
///   de um fio (hairline) que atravessa a página e da contagem de momentos em
///   overline. O fio INTERROMPE a espinha das entradas de propósito: é a virada
///   de página.
/// - **Fotografia protagonista**: quando a memória tem foto, a entrada é um
///   [SJPhotoCard] grande (retrato 4:5) onde a imagem manda e o texto só
///   complementa sobre o scrim. Sem foto, a entrada vira uma nota tipográfica em
///   papel (data em overline + título em serifa + trecho + coordenada) — quieta,
///   nunca um "ícone falso de livro".
/// - **Espinha contínua**: um fio vertical na goteira esquerda com um ponto por
///   entrada amarra o álbum e mantém a leitura cronológica; no papel quente ele
///   fica em `scheme.line` (quase uma marca de dobra).
///
/// Estados: carregando (esqueleto de capítulo), erro (bússola quebrada +
/// "Tentar de novo"), vazio (lua e estrelas ENSINANDO a primeira página) e
/// conteúdo, sempre com pull-to-refresh.
///
/// **A lente das fases:** quem nomeou fases da vida pode reler o álbum por
/// uma delas — a faculdade, o intercâmbio. Os capítulos continuam sendo os
/// anos; a fase só escolhe quais páginas entram. Sem fase cadastrada a lente
/// não aparece, e a tela é exatamente o que sempre foi.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen>
    with AtualizaQuandoMuda<TimelineScreen> {
  List<Memory>? _memories;
  ApiError? _error;
  bool _loading = true;

  /// Cursor da próxima página; nulo quando o álbum acabou.
  String? _nextCursor;
  bool _loadingMore = false;

  /// Erro da PAGINAÇÃO, separado de [_error] de propósito: falhar ao buscar a
  /// próxima página não pode apagar as páginas já lidas da tela.
  String _moreError = '';

  /// Largura da goteira da espinha (fio + ponto) e o respiro até o conteúdo.
  static const double _railWidth = 22;

  final _phases = PhaseStore.instance;

  /// A fase pela qual o álbum está sendo lido; null é a vida toda.
  String? _phaseId;

  /// A lente acabou de mudar e a página nova ainda não chegou. O álbum antigo
  /// FICA na tela, esmaecido, em vez de virar esqueleto: trocar de lente é
  /// folhear, e uma página em branco no meio do gesto parece travamento.
  bool _trocandoLente = false;

  /// Entradas que já apareceram uma vez. Só a memória que chega de novo faz o
  /// surgimento — rolar de volta, ou reler o álbum, não repete a animação.
  final Set<String> _vistas = {};

  /// Algo mudou no servidor por este app (uma memória criada pelo botão
  /// central, editada, apagada): relê em silêncio, sem esqueleto.
  @override
  void dadosMudaram() => _load();

  @override
  void initState() {
    super.initState();
    _phases.addListener(_onPhases);
    _load();
  }

  @override
  void dispose() {
    _phases.removeListener(_onPhases);
    super.dispose();
  }

  /// As fases mudaram (criadas, renomeadas, apagadas noutra tela). Se a da
  /// lente sumiu, o álbum volta para a vida toda em vez de ficar pedindo uma
  /// fase que responde 404.
  void _onPhases() {
    if (!mounted) return;
    final valida = lensFor(_phases.value, _phaseId);
    if (valida != _phaseId) {
      _setLens(valida);
    } else {
      setState(() {});
    }
  }

  /// Troca a lente e relê do começo. As páginas e o cursor da lente anterior
  /// não servem para a nova — o cursor só vale com o mesmo filtro.
  void _setLens(String? phaseId) {
    if (phaseId == _phaseId) return;
    setState(() {
      _phaseId = phaseId;
      _trocandoLente = _memories != null;
      _nextCursor = null;
      _moreError = '';
    });
    _load();
  }

  Future<void> _load() async {
    final lente = _phaseId;
    setState(() {
      _error = null;
      // Esqueleto só na primeira carga: num refresh o álbum antigo continua lá.
      if (_memories == null) _loading = true;
    });
    // As fases vêm junto, sem segurar o álbum: a lente se redesenha quando
    // chegarem, e uma falha nelas não impede ninguém de ver as memórias.
    _phases.refresh();
    // Numa releitura, traz tantas quantas já estavam na tela (até o teto da
    // API): quem rolou fundo no álbum não pode vê-lo encolher para a primeira
    // página e pular de lugar só porque uma memória mudou.
    final atuais = _trocandoLente ? 0 : (_memories?.length ?? 0);
    final limite = atuais > 30 ? (atuais > 100 ? 100 : atuais) : null;
    try {
      final page = await Api.instance.listMemories(limit: limite, phaseId: lente);
      // A lente mudou enquanto esta página vinha: ela é de outro álbum.
      if (!mounted || lente != _phaseId) return;
      setState(() {
        _memories = page.items;
        _nextCursor = page.nextCursor;
        _moreError = '';
        _loading = false;
        _trocandoLente = false;
      });
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
        _loading = false;
        _trocandoLente = false;
      });
    }
  }

  /// Busca a próxima página e ANEXA ao álbum.
  ///
  /// Sai cedo quando não há cursor (acabou) ou já há uma busca em voo — o
  /// gatilho é de rolagem e dispara muitas vezes por segundo.
  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    final lente = _phaseId;
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreError = '';
    });
    try {
      final page = await Api.instance.listMemories(cursor: cursor, phaseId: lente);
      if (!mounted) return;
      // Página de outra lente não entra neste álbum.
      if (lente != _phaseId) {
        setState(() => _loadingMore = false);
        return;
      }
      setState(() {
        _memories = [...?_memories, ...page.items];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      if (lente != _phaseId) {
        setState(() => _loadingMore = false);
        return;
      }
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

  /// Nova memória (ação do estado vazio e do rodapé). O álbum se relê sozinho
  /// quando ela é gravada (AtualizaQuandoMuda) — voltar sem gravar não gasta
  /// uma ida à rede.
  /// Com a lente ligada, a memória nova já nasce marcada na fase que a pessoa
  /// está lendo — senão ela registraria o momento e ele sumiria do álbum
  /// filtrado que ela acabou de deixar.
  Future<void> _createMemory() async {
    await Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: '/memory-new'),
      builder: (_) => MemoryNewScreen(initialPhaseId: _phaseId),
    ));
  }

  void _openMemory(String id) =>
      Navigator.of(context).pushNamed('/memory', arguments: id);

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: s.primary,
        backgroundColor: s.surface,
        child: NotificationListener<ScrollNotification>(
          // Antecipa a próxima página antes de bater o fim: a página seguinte
          // costuma chegar antes de o dedo alcançar o fundo, e o álbum não dá
          // aquele solavanco de lista que trava e destrava.
          onNotification: (n) {
            if (n.metrics.axis == Axis.vertical &&
                n.metrics.pixels >= n.metrics.maxScrollExtent - 600) {
              _loadMore();
            }
            return false;
          },
          child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                SJSpace.screenX,
                SJSpace.x8,
                SJSpace.screenX,
                0,
              ),
              sliver: SliverToBoxAdapter(child: _header(s)),
            ),
            ..._body(s),
          ],
          ),
        ),
      ),
    );
  }

  /// Corpo por estado. Vazio/erro ocupam o resto da viewport (centralizados) —
  /// um estado vazio encostado no topo parece bug, não convite.
  List<Widget> _body(SJScheme s) {
    final falha = _error;
    if (falha != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ApiErrorView(
            error: falha,
            fallbackTitle: 'Não conseguimos abrir seu álbum.',
            onRetry: _load,
          ),
        ),
      ];
    }
    if (_loading) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            SJSpace.screenX,
            SJSpace.x8,
            SJSpace.screenX,
            SJSpace.x16,
          ),
          sliver: SliverToBoxAdapter(child: _TimelineSkeleton(scheme: s)),
        ),
      ];
    }
    final memories = _memories ?? const <Memory>[];
    final fase = phaseById(_phases.value, _phaseId);
    if (memories.isEmpty && fase != null) {
      // Vazio COM lente não é álbum vazio: é uma fase sem página ainda. O
      // convite é outro, e a saída é voltar para a vida toda.
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: SJEmptyState(
            title: 'Nada guardado nesta fase ainda.',
            body: 'Marque memórias ou jornadas com “${fase.name}” — na edição '
                'de cada uma — e elas aparecem aqui.',
            actionLabel: 'Ver a vida toda',
            onAction: () => _setLens(null),
          ),
        ),
      ];
    }
    if (memories.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: SJEmptyState(
            illustration: const SJIllustration(
              kind: SJIllustrationKind.noMemories,
            ),
            title: 'Seu álbum espera a primeira página.',
            body: 'Registre um momento — um lugar, uma data, uma foto — e ele '
                'abre o primeiro capítulo desta história.',
            actionLabel: 'Registrar primeira memória',
            onAction: _createMemory,
          ),
        ),
      ];
    }

    // Monta capítulos (ano) + entradas na ordem que a API devolveu.
    //
    // O ano de cada memória é lido UMA vez. A contagem por capítulo era um
    // laço dentro do laço — cada memória relia a data de todas as outras —, e
    // isso a cada reconstrução: com 100 memórias, 10 mil leituras de data
    // por quadro.
    final anos = [for (final m in memories) _yearOf(m.occurredAt)];
    final porAno = <int, int>{};
    for (final a in anos) {
      porAno[a] = (porAno[a] ?? 0) + 1;
    }
    final children = <Widget>[];
    int? lastYear;
    for (var i = 0; i < memories.length; i++) {
      final m = memories[i];
      final year = anos[i];
      if (year != lastYear) {
        children.add(KeyedSubtree(
          key: ValueKey('ano-$year'),
          child: _chapterHeader(
            s,
            year,
            count: porAno[year]!,
            first: lastYear == null,
          ),
        ));
        lastYear = year;
      }
      children.add(_entry(s, m));
    }
    // O rodapé é o FIM do álbum: só entra quando não há mais o que carregar.
    // Enquanto houver, o lugar dele é da continuação.
    children.add(_nextCursor == null ? _footer(s) : _more(s));

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          SJSpace.screenX,
          0,
          SJSpace.screenX,
          SJSpace.x16,
        ),
        // Trocando de lente, o álbum anterior esmaece em vez de sumir.
        sliver: SliverAnimatedOpacity(
          opacity: _trocandoLente ? 0.4 : 1,
          duration: SJMotion.fast,
          sliver: SliverList(delegate: SliverChildListDelegate(children)),
        ),
      ),
    ];
  }

  // ── Cabeçalho da tela ─────────────────────────────────────────────────────

  Widget _header(SJScheme s) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SJOverline('Album', numeral: '02'),
          const SizedBox(height: SJSpace.x2),
          Text('Sua timeline', style: SJText.display(color: s.ink)),
          const SizedBox(height: SJSpace.x2),
          Text(_narrative(), style: _diaryItalic(s)),
          if (_phases.value.isNotEmpty) ...[
            const SizedBox(height: SJSpace.x5),
            PhaseLens(
              phases: _phases.value,
              selected: _phaseId,
              onChanged: _setLens,
            ),
          ],
        ],
      );

  /// Serifa itálica das linhas afetivas (composta só a partir dos tokens).
  TextStyle _diaryItalic(SJScheme s) => TextStyle(
        fontFamily: SJType.serif,
        fontFamilyFallback: SJType.serifFallback,
        fontSize: SJType.bodySize,
        height: SJType.bodyLine / SJType.bodySize,
        fontStyle: FontStyle.italic,
        color: s.inkSoft,
      );

  /// Linha narrativa do álbum: momentos, capítulos e o arco de anos — nunca
  /// "156 memórias".
  String _narrative() {
    final memories = _memories;
    final fase = phaseById(_phases.value, _phaseId);
    // Enquanto a página da lente nova não chega, a lista na tela é a antiga:
    // contá-la sob o nome da fase nova diria um número que não é dela.
    if (_trocandoLente) {
      return fase == null
          ? 'As memórias do seu atlas em ordem viva.'
          : 'O que você guardou na fase “${fase.name}”.';
    }
    if (memories == null || memories.isEmpty || _error != null) {
      return fase == null
          ? 'As memórias do seu atlas em ordem viva.'
          : 'O que você guardou na fase “${fase.name}”.';
    }
    if (fase != null) {
      return memories.length == 1
          ? 'Uma página na fase “${fase.name}”.'
          : '${memories.length} momentos na fase “${fase.name}”.';
    }
    if (memories.length == 1) return 'A primeira página do seu álbum.';
    final years = memories.map((m) => _yearOf(m.occurredAt)).toSet().toList()
      ..sort();
    if (years.length == 1) {
      return '${memories.length} momentos guardados em ${years.first}.';
    }
    return '${memories.length} momentos em ${years.length} capítulos, '
        'de ${years.first} a ${years.last}.';
  }

  // ── Abertura de capítulo ──────────────────────────────────────────────────

  /// O ano como numeral editorial: mono, tamanho de display, no acento. O fio à
  /// direita atravessa a página e a overline conta quantos momentos moram nele.
  Widget _chapterHeader(
    SJScheme s,
    int year, {
    required int count,
    required bool first,
  }) =>
      Padding(
        padding: EdgeInsets.only(
          top: first ? SJSpace.x8 : SJSpace.x12,
          bottom: SJSpace.x5,
        ),
        child: Semantics(
          header: true,
          label: '$year, $count ${count == 1 ? 'momento' : 'momentos'}',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '$year',
                style: TextStyle(
                  fontFamily: SJType.mono,
                  fontFamilyFallback: SJType.monoFallback,
                  fontSize: SJType.displaySize,
                  height: SJType.displayLine / SJType.displaySize,
                  letterSpacing: 2,
                  color: s.accent,
                ),
              ),
              const SizedBox(width: SJSpace.x4),
              // Fio do capítulo: a "linha da encadernação" que corta a página.
              Expanded(child: Container(height: 1, color: s.line)),
              const SizedBox(width: SJSpace.x4),
              Text(
                count == 1 ? '1 momento' : '$count momentos',
                style: SJText.overline(color: s.inkSoft),
              ),
            ],
          ),
        ),
      );

  // ── Entradas ──────────────────────────────────────────────────────────────

  /// Uma entrada do álbum. A espinha (fio + ponto) fica na goteira; o conteúdo
  /// muda de natureza conforme EXISTIR foto ou não.
  ///
  /// A espinha é desenhada POR TRÁS do conteúdo, num Stack que mede só ele: o
  /// fio vai de ponta a ponta da entrada (top 0, bottom 0), então entradas
  /// consecutivas se conectam. Antes era um `IntrinsicHeight`, que mede o
  /// layout duas vezes por entrada — a cada quadro de rolagem.
  Widget _entry(SJScheme s, Memory m) {
    final hasPhoto = m.imageUrl != null;
    final nova = _vistas.add(m.id);
    return SJSurge(
      key: ValueKey(m.id),
      ativo: nova,
      child: Stack(
        children: [
          Positioned(
            left: (_railWidth - 1) / 2,
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: s.line),
          ),
          Positioned(
            // Alinha o ponto com a primeira linha de texto/topo da foto.
            left: (_railWidth - 9) / 2,
            top: SJSpace.x5,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: s.primary, shape: BoxShape.circle),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: _railWidth + SJSpace.x3,
              bottom: SJSpace.x6,
            ),
            child: hasPhoto ? _photoEntry(s, m) : _typographicEntry(s, m),
          ),
        ],
      ),
    );
  }

  /// Entrada FOTO-PROTAGONISTA: a imagem ocupa a entrada inteira em retrato 4:5;
  /// data (overline) e lugar (subtítulo) vivem SOBRE a foto, sem roubar espaço.
  Widget _photoEntry(SJScheme s, Memory m) => SJPhotoCard(
        title: m.title,
        overline: _dayMonth(m.occurredAt),
        subtitle: _coords(m.latitude, m.longitude),
        aspectRatio: 4 / 5,
        onTap: () => _openMemory(m.id),
        imageChild: SJNetworkImage(
          m.imageUrl!,
          fit: BoxFit.cover,
          // A foto "revela" ao chegar (fade curto) em vez de estalar na tela.
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
              AnimatedOpacity(
            opacity: frame == null && !wasSynchronouslyLoaded ? 0 : 1,
            duration: SJMotion.base,
            curve: SJMotion.standard,
            child: child,
          ),
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : ColoredBox(
                  color: s.surfaceAlt,
                  child: Center(
                    child: SJSpinner(size: 20, color: s.inkFaint),
                  ),
                ),
          errorBuilder: (context, _, _) => ColoredBox(
            color: s.surfaceAlt,
            child: Center(
              child: Text(
                'FOTO INDISPONÍVEL',
                style: SJText.overline(color: s.inkFaint),
              ),
            ),
          ),
        ),
      );

  /// Entrada sem foto: nota tipográfica em papel. Data em overline, título em
  /// serifa (o protagonista aqui é a palavra), trecho do texto e a coordenada.
  Widget _typographicEntry(SJScheme s, Memory m) {
    final excerpt = _excerpt(m.text);
    return SJCard(
      padding: const EdgeInsets.all(SJSpace.x5),
      onTap: () => _openMemory(m.id),
      // Sem titulo, o rotulo acessivel e a data — nunca uma virgula solta.
      semanticLabel: m.hasTitle
          ? '${m.title}, ${_dayMonth(m.occurredAt)}'
          : _dayMonth(m.occurredAt),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SJOverline(_dayMonth(m.occurredAt)),
          const SizedBox(height: SJSpace.x2),
          // O cartao ja abre com a data no overline: sem titulo ele some, em
          // vez de deixar uma linha em branco que parece defeito.
          if (m.hasTitle)
            Text(
              m.title,
              style: SJText.h2(color: s.ink),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (excerpt.isNotEmpty) ...[
            const SizedBox(height: SJSpace.x2),
            Text(
              excerpt,
              style: SJText.bodySm(color: s.inkSoft),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: SJSpace.x4),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: s.secondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: SJSpace.x2),
              Expanded(
                child: Text(
                  _coords(m.latitude, m.longitude),
                  style: SJText.caption(color: s.inkFaint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Fecho do álbum: a página seguinte está em branco de propósito — e há um
  /// caminho claro para preenchê-la.
  /// Continuação do álbum: enquanto há mais páginas, este é o pé da lista.
  ///
  /// Em erro NÃO some o que já foi lido — mostra o motivo e um caminho de volta,
  /// porque a rolagem sozinha não daria ao leitor como tentar de novo.
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

  Widget _footer(SJScheme s) => Padding(
        padding: const EdgeInsets.only(top: SJSpace.x6),
        child: Column(
          children: [
            Container(width: 32, height: 1, color: s.line),
            const SizedBox(height: SJSpace.x6),
            Text(
              'A próxima página é o lugar onde você ainda vai estar.',
              style: _diaryItalic(s),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SJSpace.x5),
            SJButton(
              label: 'Registrar um momento',
              variant: SJButtonVariant.secondary,
              onPressed: _createMemory,
            ),
          ],
        ),
      );
}

// ───────────────────────────────────────────────────────────────────────────
// Espera elegante
// ───────────────────────────────────────────────────────────────────────────

/// Esqueleto do álbum: a MESMA anatomia do conteúdo (numeral de capítulo, fio,
/// bloco de foto em retrato, nota tipográfica) em tom de areia com um pulso
/// lento. Assim a transição para o conteúdo real não reorganiza a página.
class _TimelineSkeleton extends StatefulWidget {
  const _TimelineSkeleton({required this.scheme});

  final SJScheme scheme;

  @override
  State<_TimelineSkeleton> createState() => _TimelineSkeletonState();
}

class _TimelineSkeletonState extends State<_TimelineSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _block({required double width, required double height, double radius = SJRadius.sm}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: widget.scheme.surfaceAlt,
          borderRadius: BorderRadius.circular(radius),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.scheme;
    return Semantics(
      label: 'Carregando seu álbum',
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1.0).animate(
          CurvedAnimation(parent: _c, curve: SJMotion.standard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Abertura de capítulo fantasma.
            Row(
              children: [
                _block(width: 108, height: SJSpace.x8),
                const SizedBox(width: SJSpace.x4),
                Expanded(child: Container(height: 1, color: s.line)),
              ],
            ),
            const SizedBox(height: SJSpace.x6),
            // Entrada de foto fantasma (mesmo retrato 4:5 do conteúdo real).
            AspectRatio(
              aspectRatio: 4 / 5,
              child: _block(
                width: double.infinity,
                height: double.infinity,
                radius: SJRadius.lg,
              ),
            ),
            const SizedBox(height: SJSpace.x6),
            // Nota tipográfica fantasma.
            _block(width: double.infinity, height: 120, radius: SJRadius.lg),
          ],
        ),
      ),
    );
  }
}
