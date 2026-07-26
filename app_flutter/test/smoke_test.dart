import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:some_journey/main.dart';

/// # Smoke test do app.
///
/// Garante o que nenhum teste de unidade pega: que o app INICIA e chega a uma
/// tela usável. Este teste existe porque o build web ficou preso na tela de
/// carregamento do bootstrap — em release os `assert`s são removidos, então uma
/// configuração inválida de rotas falhava em silêncio. Aqui os asserts estão
/// ligados e qualquer erro de build aparece.
void main() {
  setUp(() {
    // shared_preferences precisa de um backend em teste; sem isto o
    // getInstance() lança e o bootstrap cairia no caminho de erro.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('o app inicia e chega na tela de login (sem sessão salva)',
      (tester) async {
    await tester.pumpWidget(const SomeJourneyApp());

    // Bootstrap: decide a rota inicial e navega.
    // NÃO usar pumpAndSettle aqui: a tela de bootstrap tem um indicador de
    // progresso que anima INDEFINIDAMENTE, e o pumpAndSettle esperaria por uma
    // árvore sem animações — travaria o teste para sempre. Pumps com duração
    // fixa dão tempo ao Future do bootstrap e à transição de rota.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // Sem token salvo, a porta é o login: os dois campos e a ação principal.
    // Os componentes escrevem overlines e rótulos de botão em CAIXA ALTA de fato
    // (label.toUpperCase()), então é assim que o teste os encontra.
    expect(find.text('ENTRAR'), findsOneWidget,
        reason: 'o botão primário do login deveria estar visível');
    expect(find.text('E-MAIL'), findsOneWidget);
    expect(find.text('SENHA'), findsOneWidget);
  });

  testWidgets('com sessão salva, o app abre direto no atlas', (tester) async {
    SharedPreferences.setMockInitialValues({'sj_access_token': 'fake-token'});

    await tester.pumpWidget(const SomeJourneyApp());
    // NÃO usar pumpAndSettle aqui: a tela de bootstrap tem um indicador de
    // progresso que anima INDEFINIDAMENTE, e o pumpAndSettle esperaria por uma
    // árvore sem animações — travaria o teste para sempre. Pumps com duração
    // fixa dão tempo ao Future do bootstrap e à transição de rota.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // O shell de abas (Tempo · Criar · Atlas) é o destino de quem já entrou.
    // A barra escreve os rótulos em caixa alta de fato (label.toUpperCase()).
    expect(find.text('ATLAS'), findsWidgets);
    expect(find.text('TEMPO'), findsWidgets);
  });
}
