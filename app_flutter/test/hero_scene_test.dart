// A cena do herói, montada.
//
// O domínio (`hero_scene_domain_test.dart`) garante a conta. Aqui se garante
// o que só existe com o widget de pé: que a cena se desenha em qualquer ponto
// da viagem sem estourar, que anda quando deve e — mais importante para o
// resto da suíte — que PARA quando deve. Uma cena que nunca repousa pendura
// todo `pumpAndSettle` do app, e a tela de login está por baixo de metade
// deles.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/design/sj_theme.dart';
import 'package:some_journey/design/tokens.dart';
import 'package:some_journey/features/hero/hero_scene.dart';

void main() {
  Future<void> montar(
    WidgetTester tester, {
    double? fase,
    SJScheme esquema = sjLight,
    bool menosMovimento = false,
    Size tela = const Size(1280, 844),
    bool comArte = false,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = tela;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final arvore = MediaQuery(
      data: MediaQueryData(size: tela, disableAnimations: menosMovimento),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SJTheme(
          scheme: esquema,
          child: HeroScene(phase: fase, semanticLabel: 'Ilustração: o vagão'),
        ),
      ),
    );
    if (comArte) {
      // As duas imagens de verdade, decodificadas fora do relógio falso: sem
      // isto elas nunca chegam, e a cena inteira — tiras, malha da respiração,
      // abajur — fica sem ser desenhada no teste.
      await tester.pumpWidget(arvore);
      await tester.runAsync(() async {
        final onde = tester.element(find.byType(HeroScene));
        await precacheImage(const AssetImage(HeroScene.asset), onde);
        await precacheImage(const AssetImage(HeroScene.landscape), onde);
      });
      await tester.pumpWidget(const SizedBox());
    }
    await tester.pumpWidget(arvore);
    await tester.pump();
  }

  testWidgets('desenha a viagem inteira, de dia e de noite, sem estourar',
      (tester) async {
    for (final esquema in [sjLight, sjDark]) {
      for (var fase = 0.0; fase < 1; fase += 1 / 36) {
        await montar(tester, fase: fase, esquema: esquema, comArte: fase == 0);
        expect(tester.takeException(), isNull,
            reason: 'fase $fase, ${esquema.brightness}');
      }
    }
  });

  testWidgets('cabe na faixa do celular e no pôster', (tester) async {
    for (final tela in const [Size(390, 210), Size(1920, 1024), Size(900, 1400)]) {
      await montar(tester, fase: 0.5, tela: tela, comArte: true);
      expect(tester.takeException(), isNull, reason: '$tela');
      expect(tester.getSize(find.byType(HeroScene)), tela);
    }
  });

  group('o relógio', () {
    setUp(() => HeroScene.autoplay = true);
    tearDown(() => HeroScene.autoplay = false);

    testWidgets('sozinha, a cena anda — e continua andando', (tester) async {
      await montar(tester);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 9));
        expect(tester.takeException(), isNull);
        expect(tester.binding.hasScheduledFrame, isTrue);
      }
      // Desmontada, não deixa relógio para trás.
      await tester.pumpWidget(const SizedBox());
      // O quadro que o relógio já tinha pedido ainda passa; depois dele, nada.
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('conduzida por uma fase, fica onde foi posta', (tester) async {
      await montar(tester, fase: 0.3);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('quem pediu menos movimento recebe um quadro só',
        (tester) async {
      await montar(tester, menosMovimento: true);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  testWidgets('com o relógio desligado a cena repousa', (tester) async {
    // É o estado em que TODA a suíte roda (ver `flutter_test_config.dart`).
    expect(HeroScene.autoplay, isFalse);
    await montar(tester);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('para o leitor de tela é uma ilustração, com nome',
      (tester) async {
    final alca = tester.ensureSemantics();
    await montar(tester, fase: 0.1);
    expect(find.bySemanticsLabel('Ilustração: o vagão'), findsOneWidget);
    alca.dispose();
  });
}
