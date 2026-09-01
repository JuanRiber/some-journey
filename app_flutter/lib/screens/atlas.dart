import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/illustrations.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../models.dart';
import '../widgets/api_error_view.dart';
import '../widgets/atlas_map.dart';

/// # Atlas — a capa do produto (aba padrão pós-login)
///
/// PORQUÊ esta tela existe: o mapa É a espinha do Some Journey ("sua vida contada
/// através dos lugares"). Aqui o usuário não "consulta registros", ele OLHA a
/// própria vida espalhada no mundo. Por isso o mapa deixa de ser um widget dentro
/// de uma caixinha e passa a ocupar a maior parte da página (≈56% da altura
/// disponível, com piso/teto para telas extremas), como uma prancha cartográfica
/// montada num caderno — a moldura de couro (`scheme.frame`, desenhada no
/// [AtlasMap]) permanece, porque é ela que dá o ar de mapa impresso.
///
/// Anatomia (de cima para baixo):
/// 1. **Masthead editorial** — overline mono da marca + título em serifa +
///    uma linha NARRATIVA construída a partir do que o [MapResponse] realmente
///    tem (lugares, jornadas, jornadas abertas). Nunca um contador seco.
/// 2. **O mapa** (protagonista) — tocar num pin abre `/memory`.
/// 3. **Legenda** discreta (pontos soltos × jornadas + rastros).
/// 4. **Uma porta de saída narrativa**: "Minhas jornadas".
///
/// Ações primárias = 2 (explorar o mapa · abrir as jornadas). Utilidades de conta
/// (alterar senha, sair) vivem num bottom sheet atrás do selo "CONTA", para não
/// competirem com o conteúdo — o comportamento e as rotas continuam idênticos.
///
/// Estados cobertos: carregando (moldura + bússola que oscila), erro (bússola
/// quebrada + "Tentar de novo"), vazio (ilustração da primeira jornada ENSINANDO
/// o próximo passo) e conteúdo. Pull-to-refresh em todos.
class AtlasScreen extends StatefulWidget {
  const AtlasScreen({super.key});

  @override
  State<AtlasScreen> createState() => _AtlasScreenState();
}

class _AtlasScreenState extends State<AtlasScreen> {
  MapResponse? _map;
  ApiError? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      // Só mostramos o esqueleto quando ainda não há mapa em tela; num
      // pull-to-refresh o conteúdo antigo fica visível (o indicador já informa).
      if (_map == null) _loading = true;
    });
    try {
      final data = await Api.instance.getMap();
      if (!mounted) return;
      setState(() {
        _map = data;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Registrar a primeira memória (ação do estado vazio). Ao voltar, recarrega —
  /// senão o atlas continuaria "em branco" mesmo já tendo um pin.
  Future<void> _createMemory() async {
    await Navigator.of(context).pushNamed('/memory-new');
    if (!mounted) return;
    await _load();
  }

  // As utilidades de conta (alterar senha, sair) MIGRARAM para Configurações,
  // alcançadas pela engrenagem do Perfil. O masthead do atlas agora tem uma
  // única porta de conta: o avatar.

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // O mapa é o protagonista: fica com a maior fatia vertical da página.
          // Clamp para não virar uma faixa em telas curtas nem um oceano em
          // tablets.
          final mapHeight = (constraints.maxHeight * 0.56).clamp(300.0, 620.0);
          return RefreshIndicator(
            onRefresh: _load,
            color: s.primary,
            backgroundColor: s.surface,
            child: CustomScrollView(
              // AlwaysScrollable: mesmo com pouco conteúdo (vazio/erro) o gesto
              // de puxar-para-atualizar continua disponível.
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
                if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ApiErrorView(
                      error: _error!,
                      fallbackTitle: 'Não conseguimos abrir seu atlas.',
                      onRetry: _load,
                    ),
                  )
                else if (_loading)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      SJSpace.screenX,
                      SJSpace.x6,
                      SJSpace.screenX,
                      SJSpace.x10,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _MapSkeleton(scheme: s, height: mapHeight),
                    ),
                  )
                else if ((_map?.totalPoints ?? 0) == 0)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: SJEmptyState(
                      illustration: const SJIllustration(
                        kind: SJIllustrationKind.firstJourney,
                      ),
                      title: 'Seu atlas está em branco.',
                      body:
                          'Todo mapa começa com um lugar que importou. Registre '
                          'o primeiro — ele vira o pin de onde a sua história parte.',
                      actionLabel: 'Registrar primeira memória',
                      onAction: _createMemory,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      SJSpace.screenX,
                      SJSpace.x6,
                      SJSpace.screenX,
                      SJSpace.x12,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _mapBlock(s, mapHeight),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Masthead ──────────────────────────────────────────────────────────────

  Widget _header(SJScheme s) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SJOverline('Some Journey'),
          const SizedBox(height: SJSpace.x2),
          Row(
            children: [
              Expanded(
                child: Text('Seu atlas', style: SJText.display(color: s.ink)),
              ),
              // AVATAR no topo direito: a porta do Perfil (padrão Airbnb/GitHub).
              // As configurações NÃO ficam aqui — vivem atrás da engrenagem do
              // próprio Perfil, para a home ter UMA ação de conta só.
              SJPressable(
                onTap: () => Navigator.of(context).pushNamed('/profile'),
                semanticLabel: 'Seu perfil',
                child: Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.only(left: SJSpace.x2),
                  decoration: BoxDecoration(
                    color: s.surfaceAlt,
                    shape: BoxShape.circle,
                    border: Border.all(color: s.frame, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.person_outline, size: 20, color: s.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: SJSpace.x2),
          if (_loading && _error == null)
            _SkeletonBar(scheme: s, width: 240)
          else if (_error == null && _map != null && _map!.totalPoints > 0)
            Text(_narrative(_map!), style: _diaryItalic(s)),
        ],
      );

  // ── Mapa + arredores ──────────────────────────────────────────────────────

  Widget _mapBlock(SJScheme s, double mapHeight) => _FadeInUp(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: 'Mapa do seu atlas. Toque num pin para abrir a memória.',
              container: true,
              child: AtlasMap(
                data: _map,
                height: mapHeight,
                onSelect: (id) =>
                    Navigator.of(context).pushNamed('/memory', arguments: id),
              ),
            ),
            const SizedBox(height: SJSpace.x4),
            // Legenda em `Wrap`: com texto grande ela quebra em duas linhas em
            // vez de estourar a largura.
            Wrap(
              spacing: SJSpace.x6,
              runSpacing: SJSpace.x2,
              children: [
                _legend(s, s.secondary, 'Pontos soltos'),
                _legend(s, s.primary, 'Jornadas + rastros'),
              ],
            ),
            const SizedBox(height: SJSpace.x8),
            _journeysEntry(s),
          ],
        ),
      );

  Widget _legend(SJScheme s, Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: SJSpace.x2),
          Text(label.toUpperCase(), style: SJText.overline(color: s.inkSoft)),
        ],
      );

  /// Porta de saída narrativa (e única outra ação primária da tela): as jornadas.
  Widget _journeysEntry(SJScheme s) => SJCard(
        padding: const EdgeInsets.symmetric(
          horizontal: SJSpace.x5,
          vertical: SJSpace.x5,
        ),
        onTap: () => Navigator.of(context).pushNamed('/journeys'),
        semanticLabel: 'Minhas jornadas',
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SJOverline('Continuar jornada'),
                  const SizedBox(height: SJSpace.x2),
                  Text(
                    'Minhas jornadas',
                    style: SJText.title(color: s.ink),
                  ),
                  const SizedBox(height: SJSpace.x1),
                  Text(_journeysHint(_map), style: SJText.caption(color: s.inkSoft)),
                ],
              ),
            ),
            const SizedBox(width: SJSpace.x4),
            Text('→', style: SJText.button(color: s.secondary, size: 17)),
          ],
        ),
      );

  // ── Copy narrativa ────────────────────────────────────────────────────────

  /// Serifa em itálico para as linhas afetivas (a "letra do diário"). Composto a
  /// partir dos tokens — nenhum tamanho/cor inventado aqui.
  TextStyle _diaryItalic(SJScheme s) => TextStyle(
        fontFamily: SJType.serif,
        fontFamilyFallback: SJType.serifFallback,
        fontSize: SJType.bodySize,
        height: SJType.bodyLine / SJType.bodySize,
        fontStyle: FontStyle.italic,
        color: s.inkSoft,
      );

  /// A linha que conta a história do mapa em vez de contar objetos. Usa SÓ o que
  /// o [MapResponse] traz: total de pontos, número de jornadas e quantas seguem
  /// abertas (`status == 'active'`).
  String _narrative(MapResponse m) {
    final places = m.totalPoints;
    final journeys = m.journeys.length;
    final active = m.journeys.where((j) => j.status == 'active').length;

    if (places == 1) {
      return journeys == 0
          ? 'O primeiro lugar do seu atlas está marcado.'
          : 'O primeiro lugar do seu atlas já pertence a uma jornada.';
    }

    final head = 'Você marcou $places lugares';
    if (journeys == 0) {
      return '$head — todos soltos, ainda à espera de uma jornada.';
    }
    if (journeys == 1) {
      return active == 1
          ? '$head, reunidos numa jornada que segue aberta.'
          : '$head, reunidos numa jornada.';
    }
    final tail = active == 0
        ? ''
        : active == 1
            ? ' Uma delas segue aberta.'
            : ' $active delas seguem abertas.';
    return '$head, reunidos em $journeys jornadas.$tail';
  }

  /// Apoio do cartão de jornadas: convida em vez de só numerar.
  String _journeysHint(MapResponse? m) {
    if (m == null) return 'Revisite os caminhos que você percorreu.';
    final journeys = m.journeys.length;
    if (journeys == 0) {
      return 'Agrupe seus lugares numa primeira jornada.';
    }
    final active = m.journeys.where((j) => j.status == 'active').length;
    final label = journeys == 1 ? '1 jornada' : '$journeys jornadas';
    return active > 0 ? '$label · $active em curso' : '$label no seu atlas';
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Estados de espera
// ───────────────────────────────────────────────────────────────────────────

/// Esqueleto do mapa: a MOLDURA já aparece no lugar e no tamanho finais (o
/// layout não "pula" quando os tiles chegam) e dentro dela a bússola do
/// [SJIllustration] oscila procurando o rumo — carregar é parte da narrativa,
/// não um spinner genérico no meio do nada.
class _MapSkeleton extends StatelessWidget {
  const _MapSkeleton({required this.scheme, required this.height});

  final SJScheme scheme;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: height,
          decoration: BoxDecoration(
            color: scheme.surfaceAlt,
            border: Border.all(color: scheme.frame, width: 3),
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SJIllustration(
                kind: SJIllustrationKind.loading,
                size: 128,
              ),
              const SizedBox(height: SJSpace.x5),
              Text(
                'TRAÇANDO SEU MAPA',
                style: SJText.overline(color: scheme.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: SJSpace.x4),
        _SkeletonBar(scheme: scheme, width: 200),
      ],
    );
  }
}

/// Barra-fantasma de texto (pulso lentíssimo). Existe para o cabeçalho não
/// piscar entre "nada" e a frase narrativa.
class _SkeletonBar extends StatefulWidget {
  const _SkeletonBar({required this.scheme, required this.width});

  final SJScheme scheme;
  final double width;

  @override
  State<_SkeletonBar> createState() => _SkeletonBarState();
}

class _SkeletonBarState extends State<_SkeletonBar>
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

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: SJMotion.standard),
      ),
      child: Container(
        width: widget.width,
        height: SJSpace.x3,
        decoration: BoxDecoration(
          color: widget.scheme.surfaceAlt,
          borderRadius: BorderRadius.circular(SJRadius.sm),
        ),
      ),
    );
  }
}

/// Entrada suave do conteúdo: sobe 12px e revela em `SJMotion.slow`. É o "mapa
/// sendo revelado sobre o papel" — uma transição explicada, não enfeite.
class _FadeInUp extends StatefulWidget {
  const _FadeInUp({required this.child});

  final Widget child;

  @override
  State<_FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<_FadeInUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SJMotion.slow,
  )..forward();

  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: SJMotion.standard,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _t,
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, 12 * (1 - _t.value)),
            child: child,
          ),
          child: widget.child,
        ),
      );
}
