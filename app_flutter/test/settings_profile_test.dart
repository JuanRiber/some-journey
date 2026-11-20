// Configurações › Conta leva à edição de perfil.
//
// "Alterar nome" e "Alterar foto" ficaram meses marcados "em breve" enquanto a
// tela que faz as duas coisas já existia, aberta só pelo botão do Perfil. O
// que este arquivo prende é a ligação: a linha existe, é tocável, abre a
// edição com o perfil ATUAL — e, se o perfil não vier, a pessoa continua em
// Configurações com um aviso, em vez de cair numa tela vazia.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/design/theme_controller.dart';
import 'package:some_journey/features/phases/phase_store.dart';
import 'package:some_journey/main.dart';
import 'package:some_journey/screens/profile_edit.dart';
import 'package:some_journey/screens/settings.dart';

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

const _linha = 'Nome, foto e @username';

void main() {
  late http.Client anterior;

  /// Quando ligado, `GET /me/profile` responde 500.
  late bool perfilFalha;

  setUp(() {
    perfilFalha = false;
    SharedPreferences.setMockInitialValues({'sj_access_token': 'token-salvo'});
    Api.instance.debugSetToken(null);
    PhaseStore.instance.clear();
    anterior = Api.instance.swapClient(MockClient((r) async {
      final caminho = r.url.path;
      if (caminho == '/me/profile' && perfilFalha) {
        return http.Response(jsonEncode({'detail': 'Erro interno.'}), 500,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
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

  /// Sobe o app com sessão salva e abre Configurações pela rota de verdade.
  ///
  /// Sem `pumpAndSettle`: o bootstrap tem um indicador que gira para sempre
  /// (ver smoke_test.dart).
  Future<void> abrirConfiguracoes(WidgetTester tester) async {
    await tester.pumpWidget(SomeJourneyApp(tema: SjThemeController()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    tester.state<NavigatorState>(find.byType(Navigator).first)
        .pushNamed('/settings');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tocarNaLinha(WidgetTester tester) async {
    await tester.ensureVisible(find.text(_linha));
    await tester.pump();
    await tester.tap(find.text(_linha));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('nome e foto deixaram de ser "em breve": há uma linha tocável',
      (tester) async {
    await abrirConfiguracoes(tester);

    expect(find.text('Alterar nome'), findsNothing);
    expect(find.text('Alterar foto'), findsNothing);
    expect(
      find.ancestor(of: find.text(_linha), matching: find.byType(InkWell)),
      findsOneWidget,
      reason: 'a linha precisa responder ao toque',
    );
  });

  testWidgets('a linha abre a edição com o perfil atual', (tester) async {
    await abrirConfiguracoes(tester);

    await tocarNaLinha(tester);

    expect(find.byType(ProfileEditScreen), findsOneWidget);
    // SJTextField embrulha um CupertinoTextField: o que existe é EditableText.
    final campos = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .map((c) => c.controller.text);
    expect(campos, containsAll(<String>['Ana Lima', 'ana']));
  });

  testWidgets('sem perfil, fica em Configurações e avisa', (tester) async {
    await abrirConfiguracoes(tester);
    perfilFalha = true;

    await tocarNaLinha(tester);

    expect(find.byType(ProfileEditScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);

    // A linha volta a responder: a falha não pode deixá-la travada.
    perfilFalha = false;
    await tester.pump(const Duration(seconds: 5));
    await tocarNaLinha(tester);
    expect(find.byType(ProfileEditScreen), findsOneWidget);
  });
}
