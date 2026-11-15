import 'package:flutter/material.dart' hide MemoryImage;

import '../api.dart';
import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../features/collection/collection_domain.dart';
import '../features/sync/data_changes.dart';
import '../models.dart';
import '../widgets/api_error_view.dart';
import '../widgets/sj_image.dart';
import 'timeline.dart';

/// # Coleção — o que existe por trás de cada número do Perfil
///
/// **Por que existe:** "37 cidades" num quadrado é um convite que não abria
/// nada. Aqui cada número vira a lista do que ele conta — as cidades, os
/// países, as fotos, os dias — e cada item abre as próprias memórias no
/// álbum ([TimelineScreen] recortado).
///
/// As listas vêm agrupadas do backend (`GET /me/places`, `GET /me/days`); só
/// as fotos são uma página de memórias com foto, porque cada foto é de uma
/// memória e é ela que abre.

/// Itálico serifado das linhas afetivas, composto só a partir dos tokens.
TextStyle _diario(SJScheme s) => TextStyle(
      fontFamily: SJType.serif,
      fontFamilyFallback: SJType.serifFallback,
      fontSize: SJType.bodySmSize,
      height: SJType.bodySmLine / SJType.bodySmSize,
      fontStyle: FontStyle.italic,
      color: s.inkSoft,
    );

/// Voltar + overline + título + a linha que conta a lista.
Widget _cabecalho(
  BuildContext context,
  SJScheme s, {
  required String overline,
  required String title,
  required String line,
}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Semantics(
              button: true,
              label: 'Voltar',
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.arrow_back, color: s.ink, size: 22),
              ),
            ),
          ],
        ),
        const SizedBox(height: SJSpace.x4),
        SJOverline(overline),
        const SizedBox(height: SJSpace.x2),
        Text(title, style: SJText.h1(color: s.ink)),
        const SizedBox(height: SJSpace.x2),
        Text(line, style: _diario(s)),
        const SizedBox(height: SJSpace.x8),
      ],
    );

/// Abre o álbum recortado. Comum às três listas.
void _abrirAlbum(BuildContext context, AlbumCut cut) {
  Navigator.of(context).push(MaterialPageRoute(
    settings: const RouteSettings(name: '/memories'),
    builder: (_) => TimelineScreen(cut: cut),
  ));
}

/// Uma linha da coleção: nome em serifa, apoio em caption e a contagem à
/// direita. O cartão inteiro é o alvo de toque.
Widget _linha(
  SJScheme s, {
  required String title,
  String? subtitle,
  required int memories,
  required VoidCallback onTap,
  Widget? leading,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: SJSpace.x3),
      child: SJCard(
        padding: const EdgeInsets.symmetric(
          horizontal: SJSpace.x5, vertical: SJSpace.x4,
        ),
        onTap: onTap,
        semanticLabel: [
          title,
          ?subtitle,
          countLabel(memories, 'memória', 'memórias'),
        ].join(', '),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: SJSpace.x4)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SJText.h2(color: s.ink)),
                  if (subtitle != null) ...[
                    const SizedBox(height: SJSpace.x1),
                    Text(subtitle, style: SJText.caption(color: s.inkSoft)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: SJSpace.x3),
            Text(
              countLabel(memories, 'memória', 'memórias').toUpperCase(),
              style: SJText.overline(color: s.inkSoft),
            ),
            const SizedBox(width: SJSpace.x3),
            Text('→', style: SJText.button(color: s.secondary, size: 17)),
          ],
        ),
      ),
    );

/// O código do país em mono, num selo de papel — no lugar de uma bandeira,
/// que depende de fonte de emoji que nem toda plataforma tem.
Widget _selo(SJScheme s, String code) => Container(
      width: 40,
      padding: const EdgeInsets.symmetric(vertical: SJSpace.x2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: s.surfaceAlt,
        borderRadius: BorderRadius.circular(SJRadius.sm),
        border: Border.all(color: s.line),
      ),
      child: Text(code.toUpperCase(), style: SJText.overline(color: s.accent)),
    );

Widget _carregando() => const Padding(
      padding: EdgeInsets.only(top: SJSpace.x12),
      child: Center(child: SJSpinner()),
    );

// ── Cidades e países ─────────────────────────────────────────────────────────

enum PlaceKind { cities, countries }

/// As cidades ou os países da coleção, do mais vivido para o menos.
class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key, required this.kind});

  final PlaceKind kind;

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen>
    with AtualizaQuandoMuda<PlacesScreen> {
  Places? _places;
  ApiError? _error;

  @override
  void dadosMudaram() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final places = await Api.instance.getPlaces();
      if (mounted) setState(() => _places = places);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() => _error = e);
    }
  }

  bool get _cidades => widget.kind == PlaceKind.cities;

  String _line() {
    final p = _places;
    if (p == null) {
      return _cidades
          ? 'As cidades onde você guardou memórias.'
          : 'Os países onde você guardou memórias.';
    }
    final n = _cidades ? p.cities.length : p.countries.length;
    if (n == 0) return 'Nenhum lugar registrado ainda.';
    return _cidades
        ? '${countLabel(n, 'cidade', 'cidades')}, da mais vivida para a menos.'
        : '${countLabel(n, 'país', 'países')}, do mais vivido para o menos.';
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: s.primary,
          backgroundColor: s.surface,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              SJSpace.screenX, SJSpace.x2, SJSpace.screenX, SJSpace.x12,
            ),
            children: [
              _cabecalho(
                context,
                s,
                overline: 'Sua coleção',
                title: _cidades ? 'Cidades' : 'Países',
                line: _line(),
              ),
              ..._body(s),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(SJScheme s) {
    final places = _places;
    final falha = _error;
    if (falha != null && places == null) {
      return [
        ApiErrorView(
          error: falha,
          fallbackTitle: 'Seus lugares não abriram.',
          onRetry: _load,
          illustrationSize: 120,
        ),
      ];
    }
    if (places == null) return [_carregando()];
    final vazio = _cidades ? places.cities.isEmpty : places.countries.isEmpty;
    if (vazio) {
      return [
        SJEmptyState(
          title: 'Nenhum lugar ainda.',
          body: 'Cada memória registrada descobre onde aconteceu — a cidade e o '
              'país aparecem aqui logo depois.',
          actionLabel: 'Registrar memória',
          onAction: () => Navigator.of(context).pushNamed('/memory-new'),
        ),
      ];
    }
    if (_cidades) {
      return [
        for (final c in places.cities)
          _linha(
            s,
            title: c.city,
            subtitle: c.country,
            memories: c.memories,
            onTap: () => _abrirAlbum(
              context,
              AlbumCut(overline: 'Cidade', title: c.city, filter: c.filter),
            ),
          ),
      ];
    }
    return [
      for (final c in places.countries)
        _linha(
          s,
          title: c.name,
          subtitle: countLabel(c.cities, 'cidade', 'cidades'),
          memories: c.memories,
          leading: _selo(s, c.countryCode),
          onTap: () => _abrirAlbum(
            context,
            AlbumCut(overline: 'País', title: c.name, filter: c.filter),
          ),
        ),
    ];
  }
}

// ── Fotos ────────────────────────────────────────────────────────────────────

/// Todas as fotos, em grade, da memória mais recente para a mais antiga. Cada
/// foto abre a memória dela.
class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key});

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen>
    with AtualizaQuandoMuda<PhotosScreen> {
  static const _filtro = MemoryFilter(hasImages: true);

  List<Memory>? _memories;
  String? _nextCursor;
  bool _loadingMore = false;
  String _moreError = '';
  ApiError? _error;

  @override
  void dadosMudaram() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    // Numa releitura, traz tantas quantas já estavam na tela (até o teto da
    // API): a grade não pode encolher e pular de lugar.
    final atuais = _memories?.length ?? 0;
    final limite = atuais > 30 ? (atuais > 100 ? 100 : atuais) : null;
    try {
      final page = await Api.instance.listMemories(limit: limite, filter: _filtro);
      if (!mounted) return;
      setState(() {
        _memories = page.items;
        _nextCursor = page.nextCursor;
        _moreError = '';
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() => _error = e);
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreError = '';
    });
    try {
      final page = await Api.instance.listMemories(cursor: cursor, filter: _filtro);
      if (!mounted) return;
      setState(() {
        _memories = [...?_memories, ...page.items];
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

  /// Cada foto com a memória a que pertence, na ordem do álbum.
  List<(MemoryImage, Memory)> _fotos() => [
        for (final m in _memories ?? const <Memory>[])
          for (final img in m.images) (img, m),
      ];

  String _line(int fotos) {
    if (_memories == null) return 'Cada foto abre a memória de onde ela veio.';
    if (fotos == 0) return 'Nenhuma foto guardada ainda.';
    // Com mais páginas por vir, o total ainda não está na tela.
    if (_nextCursor != null) return 'Da mais recente para a mais antiga.';
    return '${countLabel(fotos, 'foto', 'fotos')}, da mais recente para a mais antiga.';
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final fotos = _fotos();
    return Scaffold(
      backgroundColor: s.bg,
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
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    SJSpace.screenX, SJSpace.x2, SJSpace.screenX, 0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _cabecalho(
                      context,
                      s,
                      overline: 'Sua coleção',
                      title: 'Fotos',
                      line: _line(fotos.length),
                    ),
                  ),
                ),
                ..._body(s, fotos),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(SJScheme s, List<(MemoryImage, Memory)> fotos) {
    final falha = _error;
    if (falha != null && _memories == null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SJSpace.screenX),
            child: ApiErrorView(
              error: falha,
              fallbackTitle: 'Suas fotos não abriram.',
              onRetry: _load,
              illustrationSize: 120,
            ),
          ),
        ),
      ];
    }
    if (_memories == null) return [SliverToBoxAdapter(child: _carregando())];
    if (fotos.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SJSpace.screenX),
            child: SJEmptyState(
              title: 'Nenhuma foto ainda.',
              body: 'As fotos que você junta às memórias aparecem todas aqui, '
                  'como num rolo de filme.',
              actionLabel: 'Registrar memória',
              onAction: () => Navigator.of(context).pushNamed('/memory-new'),
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: SJSpace.screenX),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            mainAxisSpacing: SJSpace.x2,
            crossAxisSpacing: SJSpace.x2,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _foto(s, fotos[i].$1, fotos[i].$2),
            childCount: fotos.length,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          SJSpace.screenX, SJSpace.x6, SJSpace.screenX, SJSpace.x12,
        ),
        sliver: SliverToBoxAdapter(child: _rodape(s)),
      ),
    ];
  }

  Widget _foto(SJScheme s, MemoryImage img, Memory m) => SJPressable(
        key: ValueKey(img.id),
        onTap: () => Navigator.of(context).pushNamed('/memory', arguments: m.id),
        semanticLabel: m.hasTitle ? 'Foto de ${m.title}' : 'Foto de uma memória',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(SJRadius.sm),
          child: ColoredBox(
            color: s.surfaceAlt,
            child: SJNetworkImage(
              img.url,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.image_not_supported_outlined, color: s.inkFaint),
            ),
          ),
        ),
      );

  Widget _rodape(SJScheme s) {
    if (_moreError.isNotEmpty) {
      return Center(
        child: SJButton(
          label: 'Tentar de novo',
          variant: SJButtonVariant.text,
          onPressed: _loadMore,
        ),
      );
    }
    if (_nextCursor != null) return const Center(child: SJSpinner());
    return const SizedBox.shrink();
  }
}

// ── Dias no app ──────────────────────────────────────────────────────────────

/// Os dias em que a pessoa registrou algo, agrupados por mês. Cada dia abre
/// as memórias registradas nele.
class DaysScreen extends StatefulWidget {
  const DaysScreen({super.key});

  @override
  State<DaysScreen> createState() => _DaysScreenState();
}

class _DaysScreenState extends State<DaysScreen>
    with AtualizaQuandoMuda<DaysScreen> {
  List<DayEntry>? _days;
  ApiError? _error;

  @override
  void dadosMudaram() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final days = await Api.instance.getDays();
      if (mounted) setState(() => _days = days);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() => _error = e);
    }
  }

  String _line() {
    final days = _days;
    if (days == null) return 'Os dias em que você registrou alguma coisa.';
    if (days.isEmpty) return 'Nenhum dia registrado ainda.';
    return '${countLabel(days.length, 'dia', 'dias')} em que você registrou '
        'alguma coisa.';
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: s.primary,
          backgroundColor: s.surface,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              SJSpace.screenX, SJSpace.x2, SJSpace.screenX, SJSpace.x12,
            ),
            children: [
              _cabecalho(
                context,
                s,
                overline: 'Sua coleção',
                title: 'Dias no app',
                line: _line(),
              ),
              ..._body(s),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(SJScheme s) {
    final days = _days;
    final falha = _error;
    if (falha != null && days == null) {
      return [
        ApiErrorView(
          error: falha,
          fallbackTitle: 'Seus dias não abriram.',
          onRetry: _load,
          illustrationSize: 120,
        ),
      ];
    }
    if (days == null) return [_carregando()];
    if (days.isEmpty) {
      return [
        SJEmptyState(
          title: 'Nenhum dia ainda.',
          body: 'Todo dia em que você registra uma memória entra aqui.',
          actionLabel: 'Registrar memória',
          onAction: () => Navigator.of(context).pushNamed('/memory-new'),
        ),
      ];
    }
    final children = <Widget>[];
    String? mes;
    for (final d in days) {
      final esteMes = monthLabel(d.day);
      if (esteMes != mes) {
        children.add(Padding(
          padding: EdgeInsets.only(
            top: mes == null ? 0 : SJSpace.x6,
            bottom: SJSpace.x3,
          ),
          child: SJOverline(esteMes),
        ));
        mes = esteMes;
      }
      children.add(_linha(
        s,
        title: dayLabel(d.day),
        subtitle: weekdayLabel(d.day),
        memories: d.memories,
        onTap: () => _abrirAlbum(
          context,
          AlbumCut(
            overline: 'Registrado em',
            title: dayLabel(d.day),
            filter: d.filter,
          ),
        ),
      ));
    }
    return children;
  }
}
