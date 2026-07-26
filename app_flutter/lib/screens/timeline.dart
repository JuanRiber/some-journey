import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/illustrations.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../models.dart';

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
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<Memory>? _memories;
  String _error = '';
  bool _loading = true;

  /// Largura da goteira da espinha (fio + ponto) e o respiro até o conteúdo.
  static const double _railWidth = 22;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = '';
      // Esqueleto só na primeira carga: num refresh o álbum antigo continua lá.
      if (_memories == null) _loading = true;
    });
    try {
      final data = await Api.instance.listMemories();
      if (!mounted) return;
      setState(() {
        _memories = data;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// Nova memória (ação do estado vazio e do rodapé). Recarrega ao voltar para o
  /// álbum já abrir com a página nova.
  Future<void> _createMemory() async {
    await Navigator.of(context).pushNamed('/memory-new');
    if (!mounted) return;
    await _load();
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
    );
  }

  /// Corpo por estado. Vazio/erro ocupam o resto da viewport (centralizados) —
  /// um estado vazio encostado no topo parece bug, não convite.
  List<Widget> _body(SJScheme s) {
    if (_error.isNotEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: SJEmptyState(
            illustration: const SJIllustration(kind: SJIllustrationKind.error),
            title: 'Não conseguimos abrir seu álbum.',
            body: _error,
            actionLabel: 'Tentar de novo',
            onAction: _load,
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
    final children = <Widget>[];
    int? lastYear;
    for (var i = 0; i < memories.length; i++) {
      final m = memories[i];
      final year = _yearOf(m.occurredAt);
      if (year != lastYear) {
        children.add(_chapterHeader(
          s,
          year,
          count: memories.where((x) => _yearOf(x.occurredAt) == year).length,
          first: lastYear == null,
        ));
        lastYear = year;
      }
      children.add(_entry(s, m));
    }
    children.add(_footer(s));

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          SJSpace.screenX,
          0,
          SJSpace.screenX,
          SJSpace.x16,
        ),
        sliver: SliverList(delegate: SliverChildListDelegate(children)),
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
    if (memories == null || memories.isEmpty || _error.isNotEmpty) {
      return 'As memórias do seu atlas em ordem viva.';
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
  Widget _entry(SJScheme s, Memory m) {
    final hasPhoto = m.imageUrl != null;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rail(s),
          const SizedBox(width: SJSpace.x3),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: SJSpace.x6),
              child: hasPhoto ? _photoEntry(s, m) : _typographicEntry(s, m),
            ),
          ),
        ],
      ),
    );
  }

  /// Espinha contínua + ponto da entrada. O fio segue de ponta a ponta da linha
  /// (por isso o `Positioned.fill`), então entradas consecutivas se conectam.
  Widget _rail(SJScheme s) => SizedBox(
        width: _railWidth,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned.fill(
              child: Center(child: Container(width: 1, color: s.line)),
            ),
            Padding(
              // Alinha o ponto com a primeira linha de texto/topo da foto.
              padding: const EdgeInsets.only(top: SJSpace.x5),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: s.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      );

  /// Entrada FOTO-PROTAGONISTA: a imagem ocupa a entrada inteira em retrato 4:5;
  /// data (overline) e lugar (subtítulo) vivem SOBRE a foto, sem roubar espaço.
  Widget _photoEntry(SJScheme s, Memory m) => SJPhotoCard(
        title: m.title,
        overline: _dayMonth(m.occurredAt),
        subtitle: _coords(m.latitude, m.longitude),
        aspectRatio: 4 / 5,
        onTap: () => _openMemory(m.id),
        imageChild: Image.network(
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
      semanticLabel: '${m.title}, ${_dayMonth(m.occurredAt)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SJOverline(_dayMonth(m.occurredAt)),
          const SizedBox(height: SJSpace.x2),
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
