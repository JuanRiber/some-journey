// Excluir a conta, do toque em Configurações até a tela de login.
//
// É a ação mais destrutiva do app, e por isso o que este arquivo prende não é
// só "funciona": é que ela NÃO acontece por acidente (o botão só acende com as
// duas confirmações), que o que vai para o servidor é o que a pessoa digitou,
// e que, quando dá certo, não sobra no aparelho nada de quem saiu.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/design/theme_controller.dart';
import 'package:some_journey/features/phases/phase_store.dart';
import 'package:some_journey/features/tracks/track_domain.dart';
import 'package:some_journey/features/tracks/track_outbox.dart';
import 'package:some_journey/main.dart';
import 'package:some_journey/screens/delete_account.dart';
import 'package:some_journey/screens/login.dart';
import 'package:some_journey/screens/settings.dart';

const _email = 'ana@example.com';

Map<String, dynamic> _perfil({required bool temSenha}) => {
      'identity': {
        'id': 'u1',
        'name': 'Ana Lima',
        'email': _email,
        'joined_at': '2026-03-14T12:00:00Z',
        'has_password': temSenha,
      },
      'stats': {'memories': 3, 'journeys': 1},
      'passport': <dynamic>[],
    };

// SJButton desenha o rótulo em maiúsculas.
const _excluir = 'EXCLUIR MINHA CONTA PARA SEMPRE';
const _manter = 'MANTER MINHA CONTA';

void main() {
  late http.Client anterior;
  late bool temSenha;

  /// Como o servidor responde à exclusão: null = 204.
  late http.Response? recusa;

  /// "MÉTODO caminho" do que chegou, e os corpos da exclusão.
  late List<String> chamadas;
  late List<Map<String, dynamic>> pedidos;

  setUp(() {
    temSenha = true;
    recusa = null;
    chamadas = [];
    pedidos = [];
    SharedPreferences.setMockInitialValues({'sj_access_token': 'token-salvo'});
    Api.instance.debugSetToken(null);
    PhaseStore.instance.clear();
    anterior = Api.instance.swapClient(MockClient((r) async {
      final caminho = r.url.path;
      chamadas.add('${r.method} $caminho');
      if (caminho == '/auth/delete-account') {
        pedidos.add(jsonDecode(r.body) as Map<String, dynamic>);
        return recusa ?? http.Response('', 204);
      }
      final Object corpo = caminho == '/me/profile'
          ? _perfil(temSenha: temSenha)
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

  /// Sobe o app com sessão salva e chega à tela pelo caminho de verdade:
  /// Configurações › Conta › Excluir conta.
  Future<void> abrir(WidgetTester tester) async {
    await tester.pumpWidget(SomeJourneyApp(tema: SjThemeController()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    tester.state<NavigatorState>(find.byType(Navigator).first)
        .pushNamed('/settings');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Excluir conta'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    chamadas.clear();
  }

  Future<void> digitar(WidgetTester tester, int campo, String texto) async {
    await tester.enterText(find.byType(EditableText).at(campo), texto);
    await tester.pump();
  }

  Future<void> tocar(WidgetTester tester, String rotulo) async {
    await tester.ensureVisible(find.text(rotulo));
    await tester.pump();
    await tester.tap(find.text(rotulo));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('Configurações leva à tela, e ela diz o que some', (tester) async {
    await abrir(tester);

    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(find.textContaining('suas memórias, com as fotos'), findsOneWidget);
    expect(find.textContaining('Não tem volta'), findsOneWidget);
    // Dois campos: o e-mail e a senha.
    expect(find.byType(EditableText), findsNWidgets(2));
  });

  group('não acontece por acidente', () {
    testWidgets('sem nada digitado o botão não faz nada', (tester) async {
      await abrir(tester);

      await tocar(tester, _excluir);

      expect(pedidos, isEmpty);
      expect(find.byType(DeleteAccountScreen), findsOneWidget);
    });

    testWidgets('e-mail de outra conta não acende o botão', (tester) async {
      await abrir(tester);
      await digitar(tester, 0, 'outra@example.com');
      await digitar(tester, 1, 'minha-senha-123');

      await tocar(tester, _excluir);

      expect(pedidos, isEmpty);
    });

    testWidgets('e-mail certo sem a senha ainda não basta', (tester) async {
      await abrir(tester);
      await digitar(tester, 0, _email);

      await tocar(tester, _excluir);

      expect(pedidos, isEmpty);
    });

    testWidgets('"Manter minha conta" volta sem pedir nada ao servidor',
        (tester) async {
      await abrir(tester);
      await digitar(tester, 0, _email);
      await digitar(tester, 1, 'minha-senha-123');

      await tocar(tester, _manter);

      expect(chamadas, isEmpty);
      expect(find.byType(DeleteAccountScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(Api.instance.hasToken, isTrue);
    });
  });

  group('quando a pessoa confirma', () {
    testWidgets('manda o que foi digitado e termina no login, sem sessão',
        (tester) async {
      await abrir(tester);
      // Com maiúsculas e espaço, como sai de um teclado de celular.
      await digitar(tester, 0, ' Ana@Example.com ');
      await digitar(tester, 1, 'minha-senha-123');

      await tocar(tester, _excluir);

      expect(pedidos, [
        {'email': 'Ana@Example.com', 'password': 'minha-senha-123'},
      ]);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(DeleteAccountScreen), findsNothing);
      expect(find.textContaining('foram excluídos'), findsOneWidget);
      expect(Api.instance.hasToken, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sj_access_token'), isNull);
      expect(await const FlutterSecureStorage().readAll(), isEmpty,
          reason: 'nada de quem saiu fica no cofre do aparelho');
    });

    testWidgets('não avisa logout nenhum: os tokens foram com a conta',
        (tester) async {
      await abrir(tester);
      await digitar(tester, 0, _email);
      await digitar(tester, 1, 'minha-senha-123');

      await tocar(tester, _excluir);

      expect(chamadas, ['POST /auth/delete-account']);
    });

    testWidgets('conta que entra pelo Google: sem campo de senha, só o e-mail',
        (tester) async {
      temSenha = false;
      await abrir(tester);

      expect(find.byType(EditableText), findsOneWidget);
      expect(find.textContaining('entra pelo Google'), findsOneWidget);

      await digitar(tester, 0, _email);
      await tocar(tester, _excluir);

      expect(pedidos, [
        {'email': _email},
      ], reason: 'sem a chave "password": não há senha a conferir');
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('quando o servidor recusa', () {
    testWidgets('senha errada: o erro aparece e NADA muda', (tester) async {
      recusa = http.Response(
          jsonEncode({'detail': 'A senha está incorreta.'}), 401,
          headers: {'content-type': 'application/json; charset=utf-8'});
      await abrir(tester);
      await digitar(tester, 0, _email);
      await digitar(tester, 1, 'senha-errada');

      await tocar(tester, _excluir);

      expect(find.text('A senha está incorreta.'), findsOneWidget);
      expect(find.byType(DeleteAccountScreen), findsOneWidget);
      expect(Api.instance.hasToken, isTrue, reason: 'a sessão estava boa');
      expect(chamadas, ['POST /auth/delete-account'],
          reason: 'este 401 não é de sessão: renovar seria gastar um refresh '
              'token para repetir a mesma senha errada');
    });

    testWidgets('dá para corrigir a senha e tentar de novo', (tester) async {
      recusa = http.Response(
          jsonEncode({'detail': 'A senha está incorreta.'}), 401,
          headers: {'content-type': 'application/json; charset=utf-8'});
      await abrir(tester);
      await digitar(tester, 0, _email);
      await digitar(tester, 1, 'senha-errada');
      await tocar(tester, _excluir);

      recusa = null;
      await digitar(tester, 1, 'senha-certa-123');
      await tocar(tester, _excluir);

      expect(pedidos.last['password'], 'senha-certa-123');
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('servidor fora: avisa e mantém a conta e a sessão',
        (tester) async {
      recusa = http.Response('{"detail":"x"}', 503);
      await abrir(tester);
      await digitar(tester, 0, _email);
      await digitar(tester, 1, 'minha-senha-123');

      await tocar(tester, _excluir);

      expect(find.textContaining('fora do ar'), findsOneWidget);
      expect(find.byType(DeleteAccountScreen), findsOneWidget);
      expect(Api.instance.hasToken, isTrue);
    });
  });

  testWidgets('os pontos de GPS que esperavam envio saem do aparelho',
      (tester) async {
    await abrir(tester);
    const caixa = PrefsTrackOutbox();
    await caixa.save('j1', 'trecho-1', [
      TrackSample(
        latitude: -3.73,
        longitude: -38.52,
        recordedAt: DateTime.utc(2026, 8, 28, 12),
      ),
    ]);
    await digitar(tester, 0, _email);
    await digitar(tester, 1, 'minha-senha-123');

    await tocar(tester, _excluir);

    expect(await caixa.load('j1'), isNull);
  });
}
