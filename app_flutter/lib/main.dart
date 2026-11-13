import 'package:flutter/material.dart';
import 'package:some_journey/design/gallery.dart';

import 'api.dart';
import 'design/sj_theme.dart';
import 'design/theme.dart';
import 'design/theme_controller.dart';
import 'design/tokens.dart';
import 'screens/change_password.dart';
import 'screens/forgot_password.dart';
import 'screens/journey_detail.dart';
import 'screens/journey_edit.dart';
import 'screens/journey_new.dart';
import 'screens/journeys.dart';
import 'screens/login.dart';
import 'screens/memory_detail.dart';
import 'screens/memory_edit.dart';
import 'screens/memory_new.dart';
import 'screens/phases.dart';
import 'screens/profile.dart';
import 'screens/register.dart';
import 'screens/settings.dart';
import 'screens/tabs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final tema = SjThemeController();
  // A preferência de aparência é lida ANTES do primeiro quadro, senão quem
  // escolheu o atlas noturno abre o app num estalo creme e vê a tela trocar na
  // frente dele. Um segundo de teto: isto é cosmético, e esperar mais por
  // cosmética é pior que começar claro. Se estourar, `loadSaved` continua
  // correndo e o notifier corrige depois — tarde é melhor que nunca.
  try {
    await tema.loadSaved().timeout(const Duration(seconds: 1));
  } catch (_) {
    // Armazenamento indisponível (aba privada, política de site): modo padrão.
  }

  runApp(SomeJourneyApp(tema: tema));
}

class SomeJourneyApp extends StatelessWidget {
  const SomeJourneyApp({super.key, required this.tema});

  final SjThemeController tema;

  @override
  Widget build(BuildContext context) {
    // `ListenableBuilder` por fora reconstrói o `MaterialApp` (que precisa do
    // `themeMode` novo); `SjThemeScope` por dentro entrega o controlador às
    // telas. Os dois, e nesta ordem: o escopo sozinho avisaria os dependentes
    // mas não trocaria o tema, e o builder sozinho trocaria o tema sem dar a
    // ninguém como mudá-lo.
    return ListenableBuilder(
      listenable: tema,
      builder: (context, _) => SjThemeScope(
        controller: tema,
        child: _app(),
      ),
    );
  }

  Widget _app() {
    return MaterialApp(
      title: 'Some Journey',
      debugShowCheckedModeBanner: false,
      // Design system: DOIS modos saem do mesmo mapeamento de tokens.
      // `theme` = papel quente (claro, PADRÃO do produto); `darkTheme` = atlas
      // noturno. O legado `lib/theme.dart` já foi reapontado para a paleta clara,
      // então as telas atuais respiram papel — o default agora é `ThemeMode.light`.
      // O modo escuro por tela chega na etapa editorial (SJTheme.of(context)).
      theme: buildSjTheme(sjLight),
      darkTheme: buildSjTheme(sjDark),
      themeMode: tema.mode,
      // AQUI é onde o modo escuro passa a existir de verdade.
      //
      // `themeMode` sozinho trocaria só o Material por baixo. As telas leem
      // `SJTheme.of(context)`, e sem ninguém provendo o esquema esse `of` cai
      // no fallback claro — o app inteiro continuaria creme dentro de um tema
      // escuro, sem erro nenhum. O `builder` embrulha o Navigator, então toda
      // rota (inclusive o livro do cadastro, que é translúcida) nasce com o
      // esquema certo.
      //
      // O esquema vem do `schemeFor` do próprio controlador, não de
      // `Theme.of(context).brightness`: as duas respostas saem das mesmas duas
      // entradas (modo escolhido + brilho da plataforma), mas o `AnimatedTheme`
      // do Material interpola a sua durante a troca, e os nossos tokens não
      // são interpoláveis — meia transição com cor lerped não é nem papel nem
      // atlas.
      builder: (context, child) => SJTheme(
        scheme: tema.schemeFor(context),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _Bootstrap(),
      // Rotas com argumento (id) são resolvidas em onGenerateRoute; as sem
      // argumento ficam no mapa estático.
      //
      // ATENÇÃO — POR QUE O LOGIN É '/login' E NÃO '/':
      // com `home` definido, o MaterialApp responde ao nome de rota '/' com o
      // PRÓPRIO `home`, antes de consultar `routes`/`onGenerateRoute`. Então
      // `pushReplacementNamed('/')` no fim do bootstrap trocava a tela de
      // carregamento... pela mesma tela de carregamento — spinner para sempre.
      // Em debug um assert alertaria sobre `home` + '/' juntos; em release o
      // assert é removido e a falha era SILENCIOSA (foi o que travou o build web).
      // O login tem nome próprio; todo o app navega para '/login'.
      routes: {
        '/login': (_) => const LoginScreen(),
        '/forgot': (_) => const ForgotPasswordScreen(),
        '/change-password': (_) => const ChangePasswordScreen(),
        '/tabs': (_) => const TabsScreen(),
        '/journeys': (_) => const JourneysScreen(),
        '/journey-new': (_) => const JourneyNewScreen(),
        // Perfil (avatar no topo do atlas) e, atrás da engrenagem dele,
        // as configurações.
        '/profile': (_) => const ProfileScreen(),
        '/settings': (_) => const SettingsScreen(),
        // Fases da vida: a porta fica no Perfil, porque fase é história de
        // quem a viveu, não ajuste do app.
        '/phases': (_) => const PhasesScreen(),
        // Vitrine do design system (componentes/tokens) — criada por outro
        // agente em design/gallery.dart. Rota estática, sem argumento.
        '/design-gallery': (_) => const DesignGalleryScreen(),
      },
      onGenerateRoute: (settings) {
        // O cadastro entra em cena como LIVRO, e por isso não pode ser uma
        // rota comum: o `MaterialPageRoute` deslizaria o login para fora e
        // apagaria a tela de baixo (`opaque: true`), deixando a capa subir
        // contra o vazio. Aqui a rota é TRANSLÚCIDA e sem transição própria —
        // o login continua pintado atrás, escurecendo, e a única animação é a
        // do `SJBook`. Fica em onGenerateRoute porque o mapa `routes` só
        // aceita construtores, não rotas com comportamento.
        if (settings.name == '/register') {
          return PageRouteBuilder<String?>(
            settings: settings,
            opaque: false,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => const RegisterScreen(),
          );
        }
        final id = settings.arguments as String?;
        Widget? page;
        switch (settings.name) {
          case '/memory':
            page = MemoryDetailScreen(memoryId: id!);
          case '/memory-edit':
            page = MemoryEditScreen(memoryId: id!);
          case '/memory-new':
            page = MemoryNewScreen(journeyId: id);
          case '/journey':
            page = JourneyDetailScreen(journeyId: id!);
          case '/journey-edit':
            page = JourneyEditScreen(journeyId: id!);
        }
        if (page == null) return null;
        final built = page;
        return MaterialPageRoute(builder: (_) => built, settings: settings);
      },
    );
  }
}

/// Carrega o token salvo e decide a tela inicial: Atlas se logado, senão Login.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  /// Decide a tela inicial SEM NUNCA travar aqui.
  ///
  /// `loadToken()` depende de armazenamento da plataforma (shared_preferences →
  /// localStorage na web). Se isso lançar (armazenamento bloqueado, modo privado,
  /// política de site) ou simplesmente não responder, um `await` nu deixaria o app
  /// eternamente nesta tela de carregamento — foi exatamente o que aconteceu no
  /// build web: fundo creme e um spinner girando para sempre.
  ///
  /// Agora o boot é resiliente: qualquer falha OU demora acima de 5s cai no
  /// caminho seguro (login). Perder a sessão salva é um incômodo pequeno; não
  /// conseguir abrir o app é fatal.
  Future<void> _decide() async {
    try {
      await Api.instance.loadToken().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Sessão indisponível: segue para o login (sem token).
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(Api.instance.hasToken ? '/tabs' : '/login');
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
