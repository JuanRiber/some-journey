// O modo escuro, do armazenamento até a cor que a tela pinta.
//
// O defeito que este arquivo existe para impedir já estava no app: os dois
// esquemas existiam, a galeria desenhava os dois, o controlador sabia salvar a
// preferência — e `main.dart` fixava `ThemeMode.light`. Metade do design
// system estava escrita e fora do produto.
//
// E a armadilha dentro da armadilha: trocar só o `themeMode` NÃO resolveria.
// As telas leem `SJTheme.of(context)`, que cai num fallback claro quando
// ninguém provê o esquema — o app continuaria creme dentro de um tema escuro,
// sem erro nenhum, e um teste que olhasse só o `ThemeData` passaria. Por isso
// os testes daqui perguntam pela COR QUE A TELA PINTA, atravessando o app de
// verdade (`SomeJourneyApp`, rotas reais), e não pela configuração.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:some_journey/design/theme_controller.dart';
import 'package:some_journey/design/tokens.dart';
import 'package:some_journey/main.dart';
import 'package:some_journey/screens/login.dart';
import 'package:some_journey/screens/settings.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// Sobe o app de verdade e espera o bootstrap decidir a rota.
  ///
  /// Sem `pumpAndSettle`: a tela de bootstrap tem um indicador que gira para
  /// sempre, e assentar nunca aconteceria.
  Future<void> abrirApp(WidgetTester tester, SjThemeController tema) async {
    await tester.pumpWidget(SomeJourneyApp(tema: tema));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  /// A cor que a porta de entrada realmente pinta no fundo.
  Color fundoDoLogin(WidgetTester tester) {
    final scaffold = tester.widget<Scaffold>(
      find.descendant(of: find.byType(LoginScreen), matching: find.byType(Scaffold)),
    );
    return scaffold.backgroundColor!;
  }

  group('o escuro chega até a tela', () {
    testWidgets('o app nasce no papel quente', (tester) async {
      await abrirApp(tester, SjThemeController());
      expect(fundoDoLogin(tester), sjLight.bg);
    });

    testWidgets('trocar o modo repinta a tela, não só o ThemeData',
        (tester) async {
      final tema = SjThemeController();
      await abrirApp(tester, tema);
      expect(fundoDoLogin(tester), sjLight.bg);

      await tema.setMode(ThemeMode.dark);
      await tester.pump();

      expect(fundoDoLogin(tester), sjDark.bg,
          reason: 'a tela continuou creme dentro de um tema escuro — é o '
              'fallback do SJTheme.of() falando, não o esquema ativo');
    });

    testWidgets('a preferência salva vale já no primeiro quadro',
        (tester) async {
      // É por isto que `main()` espera o `loadSaved()` antes do `runApp`: quem
      // escolheu o atlas não pode abrir o app num estalo creme.
      SharedPreferences.setMockInitialValues({'sj_theme_mode': 'dark'});
      final tema = SjThemeController();
      await tema.loadSaved();

      await abrirApp(tester, tema);

      expect(fundoDoLogin(tester), sjDark.bg);
    });

    testWidgets('no automático, quem manda é o brilho da plataforma',
        (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final tema = SjThemeController();
      await tema.setMode(ThemeMode.system);
      await abrirApp(tester, tema);

      expect(fundoDoLogin(tester), sjDark.bg);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pump();
      expect(fundoDoLogin(tester), sjLight.bg);
    });
  });

  group('o controle em Configurações', () {
    /// Abre o app e navega para Configurações pela rota de verdade.
    Future<void> abrirConfiguracoes(
      WidgetTester tester,
      SjThemeController tema,
    ) async {
      await abrirApp(tester, tema);
      tester.state<NavigatorState>(find.byType(Navigator).first)
          .pushNamed('/settings');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> escolher(WidgetTester tester, String rotulo) async {
      await tester.ensureVisible(find.text(rotulo));
      await tester.pump();
      await tester.tap(find.text(rotulo));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('os três modos aparecem e só o ativo está marcado',
        (tester) async {
      await abrirConfiguracoes(tester, SjThemeController());

      expect(find.text('Papel (claro)'), findsOneWidget);
      expect(find.text('Atlas (escuro)'), findsOneWidget);
      expect(find.text('Automático (sistema)'), findsOneWidget);

      // Um marcado, dois vazios — nada de "em breve" nesta seção.
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
      final aparencia = find.ancestor(
        of: find.text('Papel (claro)'),
        matching: find.byType(Column),
      );
      expect(
        find.descendant(of: aparencia.last, matching: find.text('em breve')),
        findsNothing,
      );
    });

    testWidgets('escolher o atlas troca o app e grava a escolha',
        (tester) async {
      final tema = SjThemeController();
      await abrirConfiguracoes(tester, tema);

      await escolher(tester, 'Atlas (escuro)');

      expect(tema.mode, ThemeMode.dark);
      // A própria tela de Configurações já está escura.
      final scaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(scaffold.backgroundColor, sjDark.bg);

      // E a escolha sobreviveu ao app: é isto que o próximo boot vai ler.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sj_theme_mode'), 'dark');
    });

    testWidgets('o automático diz em qual dos dois está', (tester) async {
      // "Sistema" é a única escolha que não revela o resultado pelo nome.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final tema = SjThemeController();
      await abrirConfiguracoes(tester, tema);
      expect(find.textContaining('Agora:'), findsNothing);

      await escolher(tester, 'Automático (sistema)');

      expect(tema.mode, ThemeMode.system);
      expect(find.text('Agora: atlas (escuro)'), findsOneWidget);
    });

    testWidgets('o modo já ativo não aceita toque', (tester) async {
      // Toque sem efeito é o jeito mais rápido de alguém achar que travou.
      final tema = SjThemeController();
      await abrirConfiguracoes(tester, tema);

      final ativo = find.ancestor(
        of: find.text('Papel (claro)'),
        matching: find.byType(InkWell),
      );
      expect(tester.widget<InkWell>(ativo.first).onTap, isNull);
    });
  });

  group('o controlador', () {
    test('o padrão do produto é o papel quente', () {
      expect(SjThemeController().mode, ThemeMode.light);
    });

    test('preferência salva ilegível não derruba nem inventa', () async {
      SharedPreferences.setMockInitialValues({'sj_theme_mode': 'xablau'});
      final tema = SjThemeController();
      await tema.loadSaved();
      expect(tema.mode, ThemeMode.light);
    });

    test('o modo é gravado por NOME, não por índice do enum', () async {
      // Guardar `index` economizaria três linhas e quebraria em silêncio no
      // dia em que alguém reordenasse `ThemeMode`: todo mundo acordaria num
      // modo diferente do que escolheu.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tema = SjThemeController();
      await tema.setMode(ThemeMode.system);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sj_theme_mode'), 'system');
    });

    test('alternar a partir do automático inverte o que se VÊ', () async {
      // Sem isto, quem está no automático-escuro tocaria o botão e receberia
      // "escuro" de novo — um toque que não faz nada.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tema = SjThemeController();
      await tema.setMode(ThemeMode.system);
      await tema.toggle(platformBrightness: Brightness.dark);
      expect(tema.mode, ThemeMode.light);
    });

    test('avisa a árvore só quando o modo muda de verdade', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tema = SjThemeController();
      var avisos = 0;
      tema.addListener(() => avisos++);

      await tema.setMode(ThemeMode.dark);
      await tema.setMode(ThemeMode.dark);

      expect(avisos, 1);
    });
  });
}
