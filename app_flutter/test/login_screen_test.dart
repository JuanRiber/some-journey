// A porta de entrada, nas duas composições.
//
// A tela de login é a única que TODO mundo vê, inclusive quem ainda não é
// usuário — e é a que mais depende de largura: acima de 900pt ela é um pôster
// (foto sangrando, promessa à esquerda, cartão à direita), abaixo vira coluna
// única. Duas composições na mesma tela é duas chances de uma montar e a outra
// não, e a que quebra é sempre a que ninguém abriu no emulador.
//
// O caso que originou metade deste arquivo: na coluna única o cartão rolava
// por dentro E a página rolava por fora — dois viewports verticais encaixados,
// que o Flutter recusa com "unbounded height". No pôster, onde o cartão tem
// altura fixa, o mesmo código estava certo. Nenhum teste de widget existente
// montava a tela estreita, então a tela simplesmente não abria no celular e a
// suíte ficava verde.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:some_journey/design/components.dart';
import 'package:some_journey/screens/login.dart';

/// Uma janela de notebook e um celular em pé.
const _poster = Size(1280, 900);
const _celular = Size(390, 800);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> abrir(WidgetTester tester, Size tela) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = tela;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();
  }

  group('as duas composições montam', () {
    testWidgets('pôster: promessa à esquerda e formulário à direita',
        (tester) async {
      await abrir(tester, _poster);
      expect(tester.takeException(), isNull);

      // A promessa só existe no pôster.
      expect(find.text('Atlas pessoal'), findsOneWidget);
      expect(find.textContaining('não são os destinos', findRichText: true),
          findsNothing);
      expect(find.textContaining('Não são os destinos'), findsOneWidget);

      // E o formulário inteiro está lá junto.
      expect(find.text('Que bom\nte ver por aqui.'), findsOneWidget);
      expect(find.text('ENTRAR'), findsOneWidget);
    });

    testWidgets('celular: coluna única, sem a promessa, com o formulário',
        (tester) async {
      await abrir(tester, _celular);
      expect(tester.takeException(), isNull);

      // Os três pilares não cabem num celular e não são desenhados.
      expect(find.text('Atlas pessoal'), findsNothing);
      // O que importa continua: a marca, a saudação e a ação. A barra fica
      // compacta — só identidade; "Criar conta" vive no formulário, a um
      // polegar de distância.
      expect(find.text('Some Journey'), findsWidgets);
      expect(find.text('CRIAR CONTA'), findsNothing);
      expect(find.text('Criar conta'), findsOneWidget);
      expect(find.text('Que bom\nte ver por aqui.'), findsOneWidget);
      expect(find.text('ENTRAR'), findsOneWidget);
    });
  });

  group('as peças ficam onde deviam', () {
    // Dois defeitos que passaram por `flutter analyze`, por toda a suíte e por
    // uma captura de tela parada — e que só aparecem quando se MEDE onde a
    // peça foi parar. Os dois eram a mesma classe de erro: um widget que se
    // mede pelo filho quando devia se medir pela caixa.

    testWidgets('a seta do "Entrar" encosta na borda, não no rótulo',
        (tester) async {
      // O `Stack` do disco se media pelo RÓTULO, então `right: 0` encostava na
      // borda do texto: a seta aparecia colada no "R" de ENTRAR, no meio do
      // botão, parecendo um erro de renderização.
      await abrir(tester, _poster);
      final botao = find.ancestor(
        of: find.text('ENTRAR'),
        matching: find.byType(SJButton),
      );
      final caixa = tester.getRect(botao);
      final seta = tester.getRect(
        find.descendant(of: botao, matching: find.byIcon(Icons.arrow_forward)),
      );
      final rotulo = tester.getRect(
        find.descendant(of: botao, matching: find.text('ENTRAR')),
      );

      expect(caixa.right - seta.center.dx, lessThan(50),
          reason: 'a seta deveria estar encostada na borda direita');
      expect(seta.left - rotulo.right, greaterThan(40),
          reason: 'a seta está colada no rótulo');
      expect(rotulo.center.dx, closeTo(caixa.center.dx, 2),
          reason: 'o rótulo continua centrado no botão');
    });

    testWidgets('o botão da barra vai até a borda da barra', (tester) async {
      // `Flexible` + `Spacer` têm flex 1 cada e RACHAM a sobra pela metade, o
      // que parava o botão no meio da barra. O sintoma não é um erro: é um
      // botão num lugar estranho, que se atribui ao desenho.
      await abrir(tester, _poster);
      final botao = tester.getRect(find.ancestor(
        of: find.text('CRIAR CONTA'),
        matching: find.byType(SJButton),
      ));
      expect(_poster.width - botao.right, lessThan(40),
          reason: 'o botão parou longe da borda: ${_poster.width - botao.right}pt');
    });
  });

  group('a senha', () {
    Finder campoDaSenha() => find.descendant(
          of: find.ancestor(
            of: find.text('SENHA'),
            matching: find.byType(SJTextField),
          ),
          matching: find.byType(EditableText),
        );

    testWidgets('nasce escondida e o olho revela', (tester) async {
      await abrir(tester, _poster);
      expect(tester.widget<EditableText>(campoDaSenha()).obscureText, isTrue);

      await tester.tap(find.bySemanticsLabel('Mostrar a senha'));
      await tester.pump();
      expect(tester.widget<EditableText>(campoDaSenha()).obscureText, isFalse);

      await tester.tap(find.bySemanticsLabel('Ocultar a senha'));
      await tester.pump();
      expect(tester.widget<EditableText>(campoDaSenha()).obscureText, isTrue);
    });
  });

  group('o que ainda não existe diz que não existe', () {
    testWidgets('o Google aparece desenhado, mas marcado "em breve"',
        (tester) async {
      // O backend não tem OAuth — `POST /auth/login` só conhece e-mail e senha.
      // O botão existe porque o desenho pede a composição com o "ou"; o que
      // ele NÃO pode é parecer clicável e não fazer nada.
      await abrir(tester, _poster);
      expect(find.text('Continuar com Google'), findsOneWidget);
      expect(find.text('ou'), findsOneWidget);
      expect(find.text('EM BREVE'), findsOneWidget);

      // Não é um botão: nenhum `SJButton` carrega esse rótulo.
      final botoes = tester
          .widgetList<SJButton>(find.byType(SJButton))
          .map((b) => b.label)
          .toList();
      expect(botoes, isNot(contains('Continuar com Google')));
    });

    testWidgets('a barra não promete rota que não existe', (tester) async {
      // O desenho de referência traz "Início · Diário · Memórias · Atlas ·
      // Sobre". Memórias e Atlas pedem conta; Diário e Sobre não existem.
      // Link morto na primeira tela é promessa quebrada no primeiro toque.
      await abrir(tester, _poster);
      for (final morto in ['Início', 'Diário', 'Sobre']) {
        expect(find.text(morto), findsNothing, reason: 'rota inexistente: $morto');
      }
      // O que a barra carrega é real: identidade e a porta do cadastro.
      expect(find.text('CRIAR CONTA'), findsOneWidget);
    });
  });
}
