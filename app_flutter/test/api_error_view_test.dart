// A notícia que a tela dá quando a API não respondeu.
//
// Por que este teste existe: toda falha virava o mesmo estado — o título da
// tela ("Não conseguimos abrir seu álbum") com o texto do servidor embaixo.
// Quando a API inteira está fora do ar isso mente: sugere que o problema é o
// álbum, quando nenhuma tela do app está funcionando, e manda a pessoa "tentar
// de novo" a mesma coisa sem dizer que a espera é do outro lado.
//
// A regra que estes testes fixam: quem manda no título é a NATUREZA da falha,
// não a tela. O título da tela só sobrevive quando o erro é da requisição — aí
// ele é, de fato, a informação mais útil.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/design/illustrations.dart';
import 'package:some_journey/widgets/api_error_view.dart';

void main() {
  Future<void> montar(
    WidgetTester tester,
    ApiError erro, {
    VoidCallback? onRetry,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ApiErrorView(
            error: erro,
            fallbackTitle: 'Não conseguimos abrir seu álbum.',
            onRetry: onRetry,
          ),
        ),
      ));

  SJIllustrationKind ilustracao(WidgetTester tester) =>
      tester.widget<SJIllustration>(find.byType(SJIllustration)).kind;

  group('quem manda no título', () {
    testWidgets('servidor fora do ar cala o título da tela', (tester) async {
      await montar(tester, ApiError(503, 'O servidor está fora do ar no momento.'));

      expect(find.text('O servidor está fora do ar.'), findsOneWidget);
      expect(find.text('Não conseguimos abrir seu álbum.'), findsNothing,
          reason: 'o álbum não é o problema quando nada responde');
    });

    testWidgets('sem conexão é notícia sobre a conexão', (tester) async {
      await montar(tester, ApiError(0, 'Sem conexão com o servidor.'));

      expect(find.text('Você está sem conexão.'), findsOneWidget);
    });

    testWidgets('quebra do servidor não vira culpa da tela', (tester) async {
      await montar(tester, ApiError(500, 'Algo quebrou do nosso lado.'));

      expect(find.text('Algo quebrou do nosso lado.'), findsWidgets);
      expect(find.text('Não conseguimos abrir seu álbum.'), findsNothing);
    });

    testWidgets('erro de requisição devolve o título da tela', (tester) async {
      await montar(tester, ApiError(404, 'Jornada não encontrada.'));

      expect(find.text('Não conseguimos abrir seu álbum.'), findsOneWidget,
          reason: 'aqui a tela é a informação mais útil que existe');
      expect(find.text('Jornada não encontrada.'), findsOneWidget);
    });
  });

  group('a ilustração acompanha a natureza da falha', () {
    testWidgets('ausência do servidor é a nuvem cortada', (tester) async {
      for (final e in [
        ApiError(0, 'sem rede'),
        ApiError(0, 'demorou', kind: ApiFailure.timeout),
        ApiError(503, 'fora do ar'),
      ]) {
        await montar(tester, e);
        expect(ilustracao(tester), SJIllustrationKind.offline,
            reason: '${e.kind} é ausência, não quebra');
      }
    });

    testWidgets('o que quebrou é a bússola quebrada', (tester) async {
      await montar(tester, ApiError(500, 'quebrou'));
      expect(ilustracao(tester), SJIllustrationKind.error);

      await montar(tester, ApiError(422, 'campo inválido'));
      expect(ilustracao(tester), SJIllustrationKind.error);
    });
  });

  group('tentar de novo', () {
    testWidgets('sem ação, nenhum botão é oferecido', (tester) async {
      await montar(tester, ApiError(503, 'fora do ar'));

      expect(find.text('Tentar de novo'.toUpperCase()), findsNothing,
          reason: 'oferecer repetição sem ter o que repetir é ruído');
    });

    testWidgets('com ação, o botão chama de volta', (tester) async {
      var tentativas = 0;
      await montar(tester, ApiError(503, 'fora do ar'),
          onRetry: () => tentativas++);

      await tester.tap(find.text('Tentar de novo'.toUpperCase()));
      await tester.pump();

      expect(tentativas, 1);
    });
  });

  testWidgets('a mensagem do erro é o corpo', (tester) async {
    await montar(tester,
        ApiError(503, 'O servidor está fora do ar no momento. Tente de novo em 2 minutos.'));

    expect(
      find.text('O servidor está fora do ar no momento. Tente de novo em 2 minutos.'),
      findsOneWidget,
      reason: 'a espera que o servidor prometeu precisa chegar a quem espera',
    );
  });
}
