// O botão do Google: o que ele faz, e o que ele se recusa a fingir.
//
// O fluxo do Google não roda em teste — não há navegador do Google nem
// credencial. O que dá para verificar, e é o que importa, é tudo em volta
// dele: que sem client id o botão fica DESLIGADO em vez de ligado e quebrado,
// que o token chega a quem tem de trocá-lo por sessão, que cancelar não vira
// mensagem de erro, e que falha vira.
//
// É por isso que existe a interface `SJGoogleSignIn`: sem ela, nada disto
// seria observável, e o botão seria um pedaço do app que ninguém jamais
// exercita até alguém tocar nele em produção.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/design/components.dart';
import 'package:some_journey/design/sj_theme.dart';
import 'package:some_journey/design/tokens.dart';
import 'package:some_journey/features/auth/google_button.dart';
import 'package:some_journey/features/auth/google_signin.dart';

/// Dublê do SDK: devolve o token combinado ou levanta a falha combinada.
class _Falso implements SJGoogleSignIn {
  _Falso({this.token, this.erro});

  final String? token;
  final GoogleFalha? erro;
  int chamadas = 0;

  @override
  Future<String> idToken() async {
    chamadas++;
    if (erro != null) throw GoogleErro(erro!);
    return token!;
  }
}

void main() {
  late List<String> tokens;
  late List<GoogleFalha> falhas;

  setUp(() {
    tokens = [];
    falhas = [];
  });

  Future<void> montar(
    WidgetTester tester, {
    required bool habilitado,
    SJGoogleSignIn? servico,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: SJTheme(
        scheme: sjLight,
        child: Scaffold(
          body: GoogleBotao(
            habilitado: habilitado,
            servico: servico,
            onToken: tokens.add,
            onFalha: falhas.add,
          ),
        ),
      ),
    ));
  }

  group('sem credencial configurada', () {
    testWidgets('fica desenhado e desligado, dizendo por quê', (tester) async {
      // O estado padrão de quem ainda não criou o client id no Google Cloud.
      // Ligar o botão antes disso seria um botão que não faz nada — que é
      // pior que um botão ausente.
      await montar(tester, habilitado: false);

      expect(find.text('Continuar com Google'), findsOneWidget);
      expect(find.text('EM BREVE'), findsOneWidget);
      // Não é botão: nenhum `SJButton` carrega esse rótulo.
      final rotulos = tester
          .widgetList<SJButton>(find.byType(SJButton))
          .map((b) => b.label);
      expect(rotulos, isNot(contains('Continuar com Google')));
    });

    testWidgets('não chama o SDK nem por acidente', (tester) async {
      final sdk = _Falso(token: 'tok');
      await montar(tester, habilitado: false, servico: sdk);
      expect(sdk.chamadas, 0);
    });
  });

  group('com credencial', () {
    testWidgets('vira botão de verdade e entrega o token', (tester) async {
      await montar(tester, habilitado: true, servico: _Falso(token: 'tok-123'));

      await tester.tap(find.text('CONTINUAR COM GOOGLE'));
      await tester.pump();

      expect(tokens, ['tok-123']);
      expect(falhas, isEmpty);
    });

    testWidgets('cancelar NÃO é erro', (tester) async {
      // Fechar a janela do Google é uma decisão da pessoa. Transformar isso
      // numa mensagem vermelha diz que ela errou quando ela só mudou de ideia.
      await montar(
        tester,
        habilitado: true,
        servico: _Falso(erro: GoogleFalha.cancelado),
      );

      await tester.tap(find.text('CONTINUAR COM GOOGLE'));
      await tester.pump();

      expect(falhas, isEmpty);
      expect(tokens, isEmpty);
    });

    testWidgets('falha de verdade avisa quem desenha a tela', (tester) async {
      await montar(
        tester,
        habilitado: true,
        servico: _Falso(erro: GoogleFalha.falhou),
      );

      await tester.tap(find.text('CONTINUAR COM GOOGLE'));
      await tester.pump();

      expect(falhas, [GoogleFalha.falhou]);
      expect(tokens, isEmpty);
    });

    testWidgets('plataforma sem fluxo direto se identifica', (tester) async {
      // O SDK não entrega login direto em toda plataforma. Dizer "falhou"
      // mandaria a pessoa tentar de novo para sempre.
      await montar(
        tester,
        habilitado: true,
        servico: _Falso(erro: GoogleFalha.naoSuportado),
      );

      await tester.tap(find.text('CONTINUAR COM GOOGLE'));
      await tester.pump();

      expect(falhas, [GoogleFalha.naoSuportado]);
    });

    testWidgets('ocupado não aceita um segundo toque', (tester) async {
      // Dois toques seriam duas trocas de token e duas navegações.
      final sdk = _Falso(token: 'tok');
      await tester.pumpWidget(MaterialApp(
        home: SJTheme(
          scheme: sjLight,
          child: Scaffold(
            body: GoogleBotao(
              habilitado: true,
              ocupado: true,
              servico: sdk,
              onToken: tokens.add,
              onFalha: falhas.add,
            ),
          ),
        ),
      ));

      await tester.tap(find.text('CONTINUAR COM GOOGLE'), warnIfMissed: false);
      await tester.pump();

      expect(sdk.chamadas, 0);
    });
  });

  test('o client id vem do build, e vazio é o estado normal', () {
    // Sem `--dart-define=GOOGLE_CLIENT_ID`, a suíte roda no mesmo estado de
    // quem ainda não configurou nada — que é como o botão nasce.
    expect(googleClientId, isEmpty);
    expect(googleConfigurado, isFalse);
  });
}
