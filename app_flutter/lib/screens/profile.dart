import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/illustrations.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../features/profile/profile_models.dart';

const _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

/// # Perfil — a identidade do viajante.
///
/// **Por que existe:** não é uma tela de conta. É onde a pessoa se VÊ dentro do
/// Some Journey — metade perfil de viajante, metade passaporte, metade painel
/// pessoal. Em poucos segundos deve contar a história de quem usa o app.
///
/// **O que o usuário sente:** orgulho e vontade de continuar. Os números não são
/// métricas de vaidade: são lugares vividos.
///
/// **Ação principal:** continuar a jornada em aberto. Secundárias: abrir o Atlas
/// e as configurações (engrenagem discreta).
///
/// **Dados:** TUDO vem de `GET /me/profile`, agregado no banco. A tela não conta
/// nada, não baixa memórias e não inventa valores — se um número não existe no
/// backend, ele não aparece aqui.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _profile;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = '');
    try {
      final data = await Api.instance.getProfile();
      if (mounted) setState(() => _profile = data);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível carregar seu perfil.');
    }
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
          child: _body(s),
        ),
      ),
    );
  }

  Widget _body(SJScheme s) {
    if (_error.isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.all(SJSpace.screenX),
        children: [
          _topBar(s),
          const SizedBox(height: SJSpace.x8),
          SJEmptyState(
            illustration: const SJIllustration(kind: SJIllustrationKind.error, size: 120),
            title: 'Seu perfil não abriu',
            body: _error,
            actionLabel: 'Tentar de novo',
            onAction: _load,
          ),
        ],
      );
    }
    final profile = _profile;
    if (profile == null) {
      return ListView(
        padding: const EdgeInsets.all(SJSpace.screenX),
        children: [_topBar(s), const SizedBox(height: SJSpace.x12), _skeleton(s)],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SJSpace.screenX, SJSpace.x2, SJSpace.screenX, SJSpace.x12,
      ),
      children: [
        _topBar(s),
        const SizedBox(height: SJSpace.x4),
        _header(s, profile),
        const SizedBox(height: SJSpace.x8),
        _travellerCard(s, profile),
        const SizedBox(height: SJSpace.x8),
        _stats(s, profile),
        if (profile.currentJourney != null) ...[
          const SizedBox(height: SJSpace.x8),
          _currentJourney(s, profile.currentJourney!),
        ],
        const SizedBox(height: SJSpace.x8),
        _passport(s, profile),
        const SizedBox(height: SJSpace.x8),
        _achievements(s),
        const SizedBox(height: SJSpace.x8),
        _quickActions(s),
        const SizedBox(height: SJSpace.x8),
        _footer(s, profile),
      ],
    );
  }

  /// Voltar + a engrenagem discreta (as configurações NÃO moram no perfil).
  Widget _topBar(SJScheme s) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Semantics(
            button: true,
            label: 'Voltar',
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back, color: s.ink, size: 22),
            ),
          ),
          Semantics(
            button: true,
            label: 'Configurações',
            child: IconButton(
              onPressed: () => Navigator.of(context).pushNamed('/settings'),
              icon: Icon(Icons.settings_outlined, color: s.inkSoft, size: 22),
            ),
          ),
        ],
      );

  Widget _header(SJScheme s, Profile p) {
    final identity = p.identity;
    return Column(
      children: [
        // Avatar: foto quando existir; até lá, as iniciais em papel emoldurado.
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            color: s.surfaceAlt,
            shape: BoxShape.circle,
            border: Border.all(color: s.frame, width: 2),
            boxShadow: SJElevation.e1(s),
            image: identity.avatarUrl == null
                ? null
                : DecorationImage(
                    image: NetworkImage(identity.avatarUrl!), fit: BoxFit.cover),
          ),
          alignment: Alignment.center,
          child: identity.avatarUrl != null
              ? null
              : Text(identity.initials, style: SJText.h1(color: s.accent)),
        ),
        const SizedBox(height: SJSpace.x4),
        Text(identity.name, style: SJText.h1(color: s.ink), textAlign: TextAlign.center),
        if (identity.username != null) ...[
          const SizedBox(height: SJSpace.x1),
          Text('@${identity.username}', style: SJText.bodySm(color: s.inkSoft)),
        ],
        const SizedBox(height: SJSpace.x2),
        Text(
          identity.bio ?? _defaultTagline(p),
          textAlign: TextAlign.center,
          style: SJText.body(color: s.inkSoft).copyWith(
            fontFamily: SJType.serif,
            fontFamilyFallback: SJType.serifFallback,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  /// A frase pessoal padrão nasce dos DADOS, não de um texto fixo — quem ainda
  /// não registrou nada recebe um convite, não um perfil vazio.
  String _defaultTagline(Profile p) {
    final year = (p.identity.memberSince ?? p.identity.joinedAt).year;
    if (p.stats.memories == 0) return 'Sua história começa no primeiro lugar registrado.';
    return 'Colecionando lugares desde $year.';
  }

  /// Cartão de identidade do viajante: o resumo HUMANO, antes dos números soltos.
  Widget _travellerCard(SJScheme s, Profile p) {
    final stats = p.stats;
    final year = (p.identity.memberSince ?? p.identity.joinedAt).year;
    final lines = <(IconData, String)>[
      (Icons.explore_outlined, 'Explorador desde $year'),
      if (stats.cities > 0)
        (Icons.place_outlined,
            '${stats.cities} ${stats.cities == 1 ? "cidade registrada" : "cidades registradas"}'),
      if (stats.journeysFinished > 0)
        (Icons.flag_outlined, '${stats.journeysFinished} jornadas concluídas'),
      if (stats.memories > 0)
        (Icons.photo_camera_outlined, '${stats.memories} memórias preservadas'),
      if (stats.trackedMeters > 0)
        (Icons.timeline, '${p.trackedLabel} percorridos'),
      if (p.lastAdventure != null && p.lastAdventure!.label.isNotEmpty)
        (Icons.flight_takeoff, 'Última aventura: ${p.lastAdventure!.label}'),
    ];

    return SJCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SJOverline('Identidade de viajante'),
          const SizedBox(height: SJSpace.x4),
          for (final (icon, text) in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: SJSpace.x3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 17, color: s.accent),
                  const SizedBox(width: SJSpace.x3),
                  Expanded(child: Text(text, style: SJText.bodySm(color: s.ink))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _stats(SJScheme s, Profile p) {
    final st = p.stats;
    final items = <(String, String)>[
      ('Memórias', '${st.memories}'),
      ('Jornadas', '${st.journeys}'),
      ('Cidades', '${st.cities}'),
      ('Países', '${st.countries}'),
      ('Fotos', '${st.photos}'),
      ('Dias no app', '${st.activeDays}'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SJSectionHeader(overline: 'Sua coleção', title: 'Em números'),
        const SizedBox(height: SJSpace.x4),
        Wrap(
          spacing: SJSpace.x3,
          runSpacing: SJSpace.x3,
          children: [
            for (final (label, value) in items)
              _StatTile(label: label, value: value),
          ],
        ),
        // Honestidade operacional: o passaporte fica incompleto até o backfill.
        if (st.pendingGeocode > 0) ...[
          const SizedBox(height: SJSpace.x3),
          Text(
            '${st.pendingGeocode} ${st.pendingGeocode == 1 ? "memória ainda está" : "memórias ainda estão"} '
            'descobrindo o lugar — o passaporte se completa em instantes.',
            style: SJText.caption(color: s.inkFaint),
          ),
        ],
      ],
    );
  }

  Widget _currentJourney(SJScheme s, CurrentJourney journey) => SJCard(
        onTap: () =>
            Navigator.of(context).pushNamed('/journey', arguments: journey.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SJOverline('Continue sua jornada'),
            const SizedBox(height: SJSpace.x2),
            Text(journey.title, style: SJText.h2(color: s.ink)),
            const SizedBox(height: SJSpace.x2),
            Text(
              journey.pointsCount == 1
                  ? '1 memória neste capítulo'
                  : '${journey.pointsCount} memórias neste capítulo',
              style: SJText.bodySm(color: s.inkSoft),
            ),
            const SizedBox(height: SJSpace.x4),
            SJButton(
              label: 'Continuar',
              onPressed: () =>
                  Navigator.of(context).pushNamed('/journey', arguments: journey.id),
            ),
          ],
        ),
      );

  /// Passaporte: TODOS os continentes. O que falta explorar é convite, não
  /// ausência de dado.
  Widget _passport(SJScheme s, Profile p) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SJSectionHeader(overline: 'Passaporte', title: 'Continentes'),
          const SizedBox(height: SJSpace.x4),
          SJCard(
            child: Column(
              children: [
                for (final stamp in p.passport)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: SJSpace.x2),
                    child: Row(
                      children: [
                        Icon(
                          stamp.visited ? Icons.check_circle : Icons.circle_outlined,
                          size: 18,
                          color: stamp.visited ? s.moss : s.inkFaint,
                        ),
                        const SizedBox(width: SJSpace.x3),
                        Expanded(
                          child: Text(
                            stamp.continent,
                            style: SJText.body(
                              color: stamp.visited ? s.ink : s.inkFaint,
                            ),
                          ),
                        ),
                        if (stamp.visited) const SJBadge('Carimbado'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );

  /// Conquistas: aparecem VAZIAS de propósito — ver o que existe para alcançar
  /// faz parte da narrativa (e o backend ainda não as calcula, então nada aqui
  /// é inventado).
  Widget _achievements(SJScheme s) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SJSectionHeader(overline: 'Conquistas', title: 'Em breve'),
          const SizedBox(height: SJSpace.x4),
          Wrap(
            spacing: SJSpace.x3,
            runSpacing: SJSpace.x3,
            children: [
              for (final name in const [
                'Primeira memória',
                '100 memórias',
                'Primeira jornada',
                '1000 km',
                '10 cidades',
              ])
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SJSpace.x4, vertical: SJSpace.x3,
                  ),
                  decoration: BoxDecoration(
                    color: s.surfaceAlt,
                    borderRadius: BorderRadius.circular(SJRadius.md),
                    border: Border.all(color: s.line),
                  ),
                  child: Text(name, style: SJText.caption(color: s.inkFaint)),
                ),
            ],
          ),
        ],
      );

  Widget _quickActions(SJScheme s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SJButton(
            label: 'Ver meu atlas',
            variant: SJButtonVariant.secondary,
            expand: true,
            onPressed: () => Navigator.of(context).pushNamed('/tabs'),
          ),
          const SizedBox(height: SJSpace.x3),
          SJButton(
            label: 'Configurações',
            variant: SJButtonVariant.text,
            expand: true,
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      );

  Widget _footer(SJScheme s, Profile p) {
    final joined = p.identity.joinedAt;
    return Center(
      child: Text(
        'Entrou em ${_meses[joined.month - 1]} de ${joined.year} · versão 1.0',
        style: SJText.caption(color: s.inkFaint),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// Esqueleto: a silhueta do perfil enquanto carrega (nunca um spinner solto —
  /// a tela já mostra a FORMA do que vem).
  Widget _skeleton(SJScheme s) {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          margin: const EdgeInsets.only(bottom: SJSpace.x3),
          decoration: BoxDecoration(
            color: s.surfaceAlt,
            borderRadius: BorderRadius.circular(SJRadius.sm),
          ),
        );
    return Column(
      children: [
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(color: s.surfaceAlt, shape: BoxShape.circle),
        ),
        const SizedBox(height: SJSpace.x5),
        bar(180, 26),
        bar(240, 16),
        const SizedBox(height: SJSpace.x6),
        bar(double.infinity, 140),
        const SizedBox(height: SJSpace.x4),
        bar(double.infinity, 120),
      ],
    );
  }
}

/// Um número da coleção. Serifa grande no valor (é o que se lê primeiro), mono
/// discreto no rótulo.
class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Container(
      width: 104,
      padding: const EdgeInsets.symmetric(
        horizontal: SJSpace.x3, vertical: SJSpace.x4,
      ),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(SJRadius.md),
        border: Border.all(color: s.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: SJText.h2(color: s.ink)),
          const SizedBox(height: SJSpace.x1),
          Text(label.toUpperCase(), style: SJText.overline(color: s.inkSoft)),
        ],
      ),
    );
  }
}
