import 'package:flutter/material.dart';
import 'package:some_journey/design/gallery.dart';

import 'api.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'screens/change_password.dart';
import 'screens/forgot_password.dart';
import 'screens/journey_detail.dart';
import 'screens/journey_new.dart';
import 'screens/journeys.dart';
import 'screens/login.dart';
import 'screens/memory_detail.dart';
import 'screens/memory_edit.dart';
import 'screens/memory_new.dart';
import 'screens/register.dart';
import 'screens/tabs.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SomeJourneyApp());
}

class SomeJourneyApp extends StatelessWidget {
  const SomeJourneyApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      themeMode: ThemeMode.light,
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
        '/register': (_) => const RegisterScreen(),
        '/forgot': (_) => const ForgotPasswordScreen(),
        '/change-password': (_) => const ChangePasswordScreen(),
        '/tabs': (_) => const TabsScreen(),
        '/journeys': (_) => const JourneysScreen(),
        '/journey-new': (_) => const JourneyNewScreen(),
        // Vitrine do design system (componentes/tokens) — criada por outro
        // agente em design/gallery.dart. Rota estática, sem argumento.
        '/design-gallery': (_) => const DesignGalleryScreen(),
      },
      onGenerateRoute: (settings) {
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
