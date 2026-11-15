// O link do e-mail de recuperação de senha abre a tela de nova senha.
//
// O e-mail entrega `…/#/reset-password?token=…`. Antes, essa rota não existia
// no app: o link abria no login, e a pessoa tinha de voltar ao e-mail, copiar
// o token de dentro da URL e colá-lo num campo chamado "código" — quem
// esqueceu a senha desistia ali. Agora o link cai direto na etapa de escolher
// a senha, e o token viaja até o backend sem passar pela mão de ninguém.
//
// A regra de quando isso acontece é pura e está em startup_domain_test.dart;
// aqui o app é montado de verdade, como o navegador o abre.

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/design/theme_controller.dart';
import 'package:some_journey/features/phases/phase_store.dart';
import 'package:some_journey/main.dart';
import 'package:some_journey/screens/forgot_password.dart';
import 'package:some_journey/screens/login.dart';
import 'package:some_journey/screens/tabs.dart';

const _link = '/reset-password?token=tok-DO_link';

void main() {
  /// O corpo de cada POST /auth/reset-password que chegou ao servidor falso.
  late List<Map<String, dynamic>> resets;

  /// "MÉTODO caminho" de tudo o MAIS que chegou a ele.
  late List<String> outras;
  late int statusDoReset;
  late http.Client anterior;

  setUp(() {
    resets = [];
    outras = [];
    statusDoReset = 204;
    Api.instance.debugSetToken(null);
    PhaseStore.instance.clear();
    anterior = Api.instance.swapClient(MockClient((r) async {
      if (r.url.path == '/auth/reset-password') {
        resets.add(jsonDecode(r.body) as Map<String, dynamic>);
        return statusDoReset == 204
            ? http.Response('', 204)
            : http.Response(
                jsonEncode({'detail': 'Link inválido ou expirado.'}),
                statusDoReset,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
      }
      // O token guardado neste arquivo está sempre VENCIDO: é o caso de quem
      // esqueceu a senha. Qualquer tela protegida que nascer toma 401.
      outras.add('${r.method} ${r.url.path}');
      return http.Response(jsonEncode({'detail': 'Not authenticated'}), 401,
          headers: {'content-type': 'application/json'});
    }));
  });

  tearDown(() {
    Api.instance.swapClient(anterior);
    Api.instance.debugSetToken(null);
    PhaseStore.instance.clear();
  });

  /// Abre o app como o navegador abre ao clicar no link: a rota do hash chega
  /// como rota inicial da plataforma.
  Future<void> abrirEm(WidgetTester tester, String rota) async {
    tester.platformDispatcher.defaultRouteNameTestValue = rota;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    await tester.pumpWidget(SomeJourneyApp(tema: SjThemeController()));
    // Sem pumpAndSettle: o bootstrap tem um indicador que gira para sempre.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> salvar(WidgetTester tester, String senha) async {
    // SJTextField embrulha um CupertinoTextField: o que se acha é EditableText.
    await tester.enterText(find.byType(EditableText), senha);
    final botao = find.text('SALVAR NOVA SENHA');
    await tester.ensureVisible(botao);
    await tester.pump();
    await tester.tap(botao);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('o link abre a nova senha, sem pedir o código de volta',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await abrirEm(tester, _link);

    expect(tester.takeException(), isNull);
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text('Escolha uma nova senha'), findsOneWidget);
    // Um campo só: a senha. O código veio no link. (O rótulo do campo é um
    // overline, desenhado em maiúsculas.)
    expect(find.text('CÓDIGO DO E-MAIL'), findsNothing);
    expect(find.text('NOVA SENHA'), findsOneWidget);
    expect(find.byType(EditableText), findsOneWidget);
    // E a tela não finge que acabou de enviar um e-mail.
    expect(find.textContaining('já está a caminho'), findsNothing);
  });

  testWidgets('a rota fica registrada sem o token no nome', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await abrirEm(tester, _link);

    // É o nome da rota que vai para a barra de endereço do navegador.
    final rota = ModalRoute.of(tester.element(find.byType(ForgotPasswordScreen)));
    expect(rota?.settings.name, '/reset-password');
  });

  testWidgets('salvar manda o token do link e volta ao login', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await abrirEm(tester, _link);
    await salvar(tester, 'senha-nova-123');

    expect(resets, [
      {'token': 'tok-DO_link', 'new_password': 'senha-nova-123'},
    ]);
    expect(find.byType(ForgotPasswordScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('token vencido guardado não derruba a tela de nova senha',
      (tester) async {
    // Visto no navegador: com o atlas por baixo, ele pedia seus dados com o
    // token vencido, tomava 401 e mandava tudo para o login — a tela de nova
    // senha ia junto, um instante depois de abrir.
    SharedPreferences.setMockInitialValues({'sj_access_token': 'token-vencido'});

    await abrirEm(tester, _link);

    expect(outras, isEmpty,
        reason: 'nenhuma tela protegida nasce por baixo da nova senha');
    expect(find.byType(TabsScreen), findsNothing);
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text('Escolha uma nova senha'), findsOneWidget);
  });

  testWidgets('com um token guardado, a troca encerra a sessão local',
      (tester) async {
    SharedPreferences.setMockInitialValues({'sj_access_token': 'token-salvo'});

    await abrirEm(tester, _link);
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);

    await salvar(tester, 'senha-nova-123');

    // A senha nova invalida a sessão no servidor: guardar o token antigo
    // abriria o app no atlas só para cada tela tomar 401.
    expect(Api.instance.hasToken, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sj_access_token'), isNull);
    expect(find.byType(TabsScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('link vencido: o erro aparece e dá para pedir outro', (tester) async {
    SharedPreferences.setMockInitialValues({});
    statusDoReset = 400;

    await abrirEm(tester, _link);
    await salvar(tester, 'senha-nova-123');

    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text('Link inválido ou expirado.'), findsOneWidget);

    final outro = find.text('Pedir outro link');
    await tester.ensureVisible(outro);
    await tester.pump();
    await tester.tap(outro);
    await tester.pump();

    // De volta ao começo do fluxo comum: pede o e-mail.
    expect(find.text('Esqueceu a senha?'), findsOneWidget);
    expect(find.text('E-MAIL'), findsOneWidget);
  });

  testWidgets('a rota sem token não abre a nova senha', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await abrirEm(tester, '/reset-password');

    expect(tester.takeException(), isNull);
    expect(find.byType(ForgotPasswordScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
