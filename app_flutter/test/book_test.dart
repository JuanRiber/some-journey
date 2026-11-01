// A geometria do livro, quadro a quadro — e o que ela protege.
//
// Animação é a coisa mais difícil de testar e a mais fácil de quebrar em
// silêncio: um sinal trocado continua sendo uma rotação de 180° perfeitamente
// válida, o analisador não reclama, e uma captura de tela parada mostra o
// mesmo livro. O defeito só existe NO MEIO do movimento — e é lá que ninguém
// olha depois da primeira vez.
//
// Por isso `SJBookGeometry` é função pura: dá para perguntar a ela o que
// acontece em t=0,37 sem montar nada. Os três testes que valem o arquivo são:
// o SENTIDO do giro (a folha levanta na direção de quem lê, não afunda para
// trás), a MOLDURA que nunca apara o próprio papel, e a folha virada que não
// rouba o toque da página de baixo.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/design/components.dart';
import 'package:some_journey/design/sj_theme.dart';
import 'package:some_journey/design/tokens.dart';

void main() {
  group('sentido do giro', () {
    // A convenção da matriz de perspectiva do Flutter: z NEGATIVO é mais perto
    // de quem olha. Rodando em torno de Y, um ponto a uma distância x da dobra
    // vai para z = −x·sen(θ). A pergunta de cada teste é só esta: no meio do
    // giro, a aresta livre da folha está perto ou longe?
    double zDaArestaLivre(double u, SJBookHinge hinge) {
      final theta = SJBookGeometry.turnAngle(u, hinge);
      // Lombada à direita: o corpo da folha está em x < 0 relativo à dobra.
      final x = hinge == SJBookHinge.right ? -1.0 : 1.0;
      return -x * math.sin(theta);
    }

    test('lombada à direita: a folha levanta na direção do leitor', () {
      expect(zDaArestaLivre(0.5, SJBookHinge.right), lessThan(0));
    });

    test('lombada à esquerda: idem', () {
      expect(zDaArestaLivre(0.5, SJBookHinge.left), lessThan(0));
    });

    test('nunca mergulha: em nenhum instante a aresta vai para trás do livro', () {
      for (var i = 1; i < 100; i++) {
        final u = i / 100;
        for (final h in SJBookHinge.values) {
          expect(
            zDaArestaLivre(u, h),
            lessThanOrEqualTo(0),
            reason: 'u=$u, lombada ${h.name}: a folha afundou para trás',
          );
        }
      }
    });

    test('deitada e virada são meia-volta exata, nos dois sentidos', () {
      expect(SJBookGeometry.turnAngle(0, SJBookHinge.left), 0);
      expect(SJBookGeometry.turnAngle(1, SJBookHinge.left), closeTo(math.pi, 1e-9));
      expect(SJBookGeometry.turnAngle(1, SJBookHinge.right), closeTo(-math.pi, 1e-9));
    });
  });

  group('qual face aparece', () {
    test('a troca acontece na perpendicular, onde a folha é invisível', () {
      // Em 90° a folha tem largura projetada zero. Trocar a face ali é o que
      // torna a troca imperceptível — em qualquer outro ponto seria um salto.
      expect(SJBookGeometry.showsBack(0.49), isFalse);
      expect(SJBookGeometry.showsBack(0.51), isTrue);
      expect(SJBookGeometry.sheen(0.5), closeTo(1.0, 1e-9));
    });

    test('deitada, em qualquer das duas faces, o papel está limpo', () {
      expect(SJBookGeometry.sheen(0), closeTo(0, 1e-9));
      expect(SJBookGeometry.sheen(1), closeTo(0, 1e-9));
    });
  });

  group('a moldura nunca apara o próprio papel', () {
    // O recorte que cresce é o que faz o livro FECHADO ocupar uma página só.
    // Mas ele e a folha correm ao mesmo tempo, e se a moldura ficar para trás
    // ela corta a aresta da folha bem no fim da abertura — um naco de papel
    // some por dois ou três quadros. Foi por isso que `openWidthFactor` ganhou
    // uma curva adiantada, e é isto que prende a curva no lugar.
    //
    // Em unidades de meia-folha (W=1, livro aberto = 2):
    //  - a aresta livre da folha está em x = 1 − cos(θ), θ = π·(1−t)
    //  - o recorte mostra de x = 2·(1 − fator) até x = 2
    double arestaLivre(double t) => 1 - math.cos(math.pi * (1 - t));
    double bordaDoRecorte(double t) => 2 * (1 - SJBookGeometry.openWidthFactor(t));

    test('em todo o percurso a folha cabe dentro do recorte', () {
      for (var i = 0; i <= 100; i++) {
        final t = i / 100;
        expect(
          arestaLivre(t),
          greaterThanOrEqualTo(bordaDoRecorte(t) - 1e-9),
          reason: 't=$t: a moldura cortou ${bordaDoRecorte(t) - arestaLivre(t)} '
              'de meia-folha',
        );
      }
    });

    test('fechado mostra uma página; aberto, as duas', () {
      expect(SJBookGeometry.openWidthFactor(0), 0.5);
      expect(SJBookGeometry.openWidthFactor(1), 1.0);
    });

    test('o recorte corre À FRENTE da abertura, nunca atrás', () {
      for (var i = 1; i < 100; i++) {
        final t = i / 100;
        final linear = 0.5 + 0.5 * t;
        expect(
          SJBookGeometry.openWidthFactor(t),
          greaterThanOrEqualTo(linear),
          reason: 't=$t: a moldura ficou para trás da folha',
        );
      }
    });
  });

  group('a cerimônia', () {
    test('o livro cresce e endireita ao abrir', () {
      expect(SJBookGeometry.lift(0), lessThan(SJBookGeometry.lift(1)));
      expect(SJBookGeometry.lift(1), 1.0);
      expect(SJBookGeometry.tilt(1), 0);
      expect(SJBookGeometry.tilt(0), greaterThan(0));
    });

    test('a entrada em cena acaba no comecinho do movimento', () {
      // Se o fade durasse a abertura inteira, o livro pareceria um fantasma em
      // vez de um objeto sendo levantado — e dava mesmo para ler a tela de
      // login ATRAVÉS da capa de couro. A capa é opaca antes de 20% do
      // caminho; o resto da cerimônia acontece com um objeto sólido em cena.
      expect(SJBookGeometry.fade(0), 0);
      expect(SJBookGeometry.fade(0.2), 1.0);
      expect(SJBookGeometry.fade(1), 1.0);
      expect(SJBookGeometry.fade(0.05), lessThan(1.0));
    });

    test('valores fora da faixa e NaN não viram ângulo maluco', () {
      expect(SJBookGeometry.clamp01(-3), 0);
      expect(SJBookGeometry.clamp01(7), 1);
      expect(SJBookGeometry.clamp01(double.nan), 0);
      expect(SJBookGeometry.turnAngle(9, SJBookHinge.left), closeTo(math.pi, 1e-9));
    });
  });

  group('o livro montado', () {
    /// Monta um livro com um botão em cada página, para perguntar pelo TOQUE —
    /// que é o que o usuário faz — em vez de pela árvore.
    Future<List<String>> montar(
      WidgetTester tester, {
      required double openness,
      required double turn,
      required bool spread,
    }) async {
      final tocados = <String>[];
      await tester.pumpWidget(SJTheme(
        scheme: sjLight,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(900, 600)),
            child: Center(
              child: SizedBox(
                width: 900,
                height: 600,
                child: SJBook(
                  openness: openness,
                  turn: turn,
                  spread: spread,
                  left: GestureDetector(
                    onTap: () => tocados.add('esquerda'),
                    child: const Text('Obrigatórios'),
                  ),
                  right: GestureDetector(
                    onTap: () => tocados.add('direita'),
                    child: const Text('Opcionais'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      return tocados;
    }

    testWidgets('aberto em folha dupla, as duas páginas respondem', (tester) async {
      final tocados = await montar(tester, openness: 1, turn: 0, spread: true);
      await tester.tap(find.text('Obrigatórios'));
      await tester.tap(find.text('Opcionais'));
      expect(tocados, ['esquerda', 'direita']);
    });

    testWidgets('folha EM MOVIMENTO não rouba o toque da página de baixo', (tester) async {
      // O defeito que este teste existe para impedir: no meio da virada a folha
      // ainda mostra a frente, inclinada, e o Flutter acerta o toque dela pela
      // matriz INVERSA. Sem o `IgnorePointer`, o campo da página que está
      // saindo engoliria o toque do botão que já aparece embaixo dela — e o
      // alvo errado fica num lugar que a pessoa nem associa ao que tocou.
      final tocados = await montar(tester, openness: 1, turn: 0.3, spread: false);
      expect(find.text('Obrigatórios'), findsOneWidget, reason: 'ainda é a face à vista');
      await tester.tap(find.text('Obrigatórios'), warnIfMissed: false);
      expect(tocados, isEmpty);
    });

    testWidgets('virada por completo, a página de cima sai da árvore', (tester) async {
      // Passada a perpendicular, quem está de frente é o VERSO — papel limpo.
      // A página que virou não fica escondida atrás de um `Opacity`: ela não é
      // construída, então não há campo fantasma para toque, foco ou leitor.
      final tocados = await montar(tester, openness: 1, turn: 1, spread: false);
      expect(find.text('Obrigatórios'), findsNothing);

      await tester.tap(find.text('Opcionais'));
      expect(tocados, ['direita']);
    });

    testWidgets('fechado, o leitor de tela não anuncia o formulário', (tester) async {
      final handle = tester.ensureSemantics();
      await montar(tester, openness: 0, turn: 0, spread: true);
      expect(find.bySemanticsLabel('Obrigatórios'), findsNothing);
      expect(find.bySemanticsLabel('Opcionais'), findsNothing);

      await montar(tester, openness: 1, turn: 0, spread: true);
      expect(find.bySemanticsLabel('Obrigatórios'), findsOneWidget);
      expect(find.bySemanticsLabel('Opcionais'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('o livro aberto é mais largo que alto, e cabe em tela baixa',
        (tester) async {
      // Sem teto de proporção o livro ia de borda a borda numa janela alta e
      // ficava quase quadrado — e um objeto quase quadrado lê como dois
      // painéis, não como livro aberto. O teto é o que deixa respiro em volta.
      await montar(tester, openness: 1, turn: 0, spread: true);
      final alto = tester.getSize(find
          .descendant(of: find.byType(SJBook), matching: find.byType(ClipRect))
          .first);
      expect(alto.width / alto.height, greaterThan(1.2),
          reason: 'ficou ${alto.width}x${alto.height}');
      expect(alto.height, lessThan(600), reason: 'devia sobrar respiro em 600pt');
    });

    testWidgets('fechado o livro ocupa UMA página; aberto, duas', (tester) async {
      // A moldura é o que faz o livro fechado parecer fechado. O jeito óbvio
      // de escrevê-la — `Align(widthFactor:)` — não funciona aqui: sob
      // constraints apertadas o `RenderPositionedBox` descarta o fator e
      // devolve a largura cheia, sem erro nenhum. O resultado seria meia
      // página de papel em branco ao lado da capa, parada, durante toda a
      // abertura. Nenhum teste de geometria pega isso: a conta estava certa, a
      // moldura é que não obedecia. Por isso este mede a ÁREA RENDERIZADA.
      double larguraDaMoldura(WidgetTester tester) => tester
          .getSize(find
              .descendant(of: find.byType(SJBook), matching: find.byType(ClipRect))
              .first)
          .width;

      await montar(tester, openness: 0, turn: 0, spread: true);
      final fechado = larguraDaMoldura(tester);

      await montar(tester, openness: 1, turn: 0, spread: true);
      final aberto = larguraDaMoldura(tester);

      expect(fechado, closeTo(aberto / 2, 0.5),
          reason: 'fechado=$fechado, aberto=$aberto');
    });

    testWidgets('a capa mostra o título e o subtítulo em caixa alta', (tester) async {
      await tester.pumpWidget(SJTheme(
        scheme: sjLight,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 900,
              height: 600,
              child: SJBook(
                openness: 0,
                spread: true,
                coverSubtitle: 'Criar conta',
                left: Text('Obrigatórios'),
                right: Text('Opcionais'),
              ),
            ),
          ),
        ),
      ));
      expect(find.text('Some Journey'), findsOneWidget);
      expect(find.text('CRIAR CONTA'), findsOneWidget);
    });

    testWidgets('as duas páginas leem o esquema ativo, não uma paleta fixa', (tester) async {
      // Mesma trava de `screen_scheme_test.dart`: montado no escuro, o papel
      // precisa vir de `sjDark`. Com cor constante este teste falha.
      await tester.pumpWidget(SJTheme(
        scheme: sjDark,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 900,
              height: 600,
              child: SJBook(
                openness: 1,
                spread: true,
                left: Text('Obrigatórios'),
                right: Text('Opcionais'),
              ),
            ),
          ),
        ),
      ));
      final papeis = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color != null)
          .map((d) => d.color);
      expect(papeis, contains(sjDark.surface));
      expect(papeis, isNot(contains(sjLight.surface)));
    });
  });
}
