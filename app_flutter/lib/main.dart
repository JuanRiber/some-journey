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
      routes: {
        '/': (_) => const LoginScreen(),
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

  Future<void> _decide() async {
    await Api.instance.loadToken();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(Api.instance.hasToken ? '/tabs' : '/');
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
