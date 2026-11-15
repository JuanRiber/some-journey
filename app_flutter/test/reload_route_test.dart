// Recarregar o navegador numa rota interna NÃO pode derrubar a sessão.
//
// No build web a rota mora no hash (`#/profile`). Num recarregamento o Flutter
// recebe esse nome como rota inicial e, deixado por conta própria, monta a
// pilha `[bootstrap, perfil]` já no primeiro quadro — antes de o bootstrap ler
// o token salvo. O Perfil nasce, pede `/me/profile` e `/life-phases` sem
// `Authorization`, recebe 401 e faz o que toda tela faz com 401: manda para o
// login. A sessão continuava inteira no armazenamento; quem a derrubava era a
// ordem das coisas.
//
// O servidor falso daqui responde como o de verdade no que importa: sem
// `Authorization` é 401, com ele é o JSON da rota. Assim o teste falha pelo
// mesmo motivo que o navegador falhava, e não por um atalho.

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
import 'package:some_journey/screens/login.dart';
import 'package:some_journey/screens/profile.dart';
import 'package:some_journey/screens/tabs.dart';

const _perfil = {
  'identity': {
    'id': 'u1',
    'name': 'Ana Lima',
    'email': 'ana@example.com',
    'joined_at': '2026-03-14T12:00:00Z',
    'username': 'ana',
  },
  'stats': {'memories': 3, 'journeys': 1},
  'passport': <dynamic>[],
};

void main() {
  /// "MÉTODO caminho" de tudo o que saiu SEM o token.
  late List<String> semToken;
  late http.Client anterior;

  setUp(() {
    semToken = [];
    Api.instance.debugSetToken(null);
    PhaseStore.instance.clear();
    anterior = Api.instance.swapClient(MockClient((r) async {
      if (!r.headers.containsKey('Authorization')) {
        semToken.add('${r.method} ${r.url.path}');
        return http.Response(jsonEncode({'detail': 'Not authenticated'}), 401,
            headers: {'content-type': 'application/json'});
      }
      final caminho = r.url.path;
      final Object corpo = caminho == '/me/profile'
          ? _perfil
          : caminho == '/map'
              ? <String, dynamic>{}
              : <dynamic>[];
      return http.Response(jsonEncode(corpo), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
  });

  tearDown(() {
    Api.instance.swapClient(anterior);
    Api.instance.debugSetToken(null);
    PhaseStore.instance.clear();
  });

  /// Abre o app como o navegador abre depois de um recarregamento: a rota do
  /// hash chega como rota inicial da plataforma.
  Future<void> recarregarEm(WidgetTester tester, String rota) async {
    tester.platformDispatcher.defaultRouteNameTestValue = rota;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    await tester.pumpWidget(SomeJourneyApp(tema: SjThemeController()));
    // Sem pumpAndSettle: o bootstrap tem um indicador que gira para sempre
    // (ver smoke_test.dart). Pumps fixos cobrem a leitura do token, as
    // respostas e as transições de rota.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('recarregar em /profile com sessão salva continua no perfil',
      (tester) async {
    SharedPreferences.setMockInitialValues({'sj_access_token': 'token-salvo'});

    await recarregarEm(tester, '/profile');

    expect(semToken, isEmpty,
        reason: 'nenhuma requisição pode sair antes de o token ser restaurado');
    expect(find.byType(LoginScreen), findsNothing,
        reason: 'com sessão válida, recarregar nunca termina no login');
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Ana Lima'), findsOneWidget,
        reason: 'o perfil carregou de verdade, com o token');
  });

  testWidgets('o perfil restaurado tem o atlas por baixo: voltar não cai no vazio',
      (tester) async {
    SharedPreferences.setMockInitialValues({'sj_access_token': 'token-salvo'});

    await recarregarEm(tester, '/profile');
    expect(find.byType(ProfileScreen), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.byType(TabsScreen), findsOneWidget);
    expect(semToken, isEmpty);
  });

  testWidgets('rota que precisa de argumento não se reconstrói do hash: abre no atlas',
      (tester) async {
    SharedPreferences.setMockInitialValues({'sj_access_token': 'token-salvo'});

    // `/memory` sem id: antes, montar essa rota a partir do hash estourava no
    // `id!` do onGenerateRoute.
    await recarregarEm(tester, '/memory');

    expect(tester.takeException(), isNull);
    expect(semToken, isEmpty);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(TabsScreen), findsOneWidget);
  });

  testWidgets('sem sessão, recarregar numa rota protegida abre o login sem pedir nada',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await recarregarEm(tester, '/profile');

    expect(semToken, isEmpty,
        reason: 'sem token não há o que pedir: a tela protegida nem nasce');
    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
