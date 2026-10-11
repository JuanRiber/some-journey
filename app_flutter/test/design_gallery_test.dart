// A galeria do design system monta sem estourar.
//
// Este teste existe por um erro que chegou até a tela do dono: acrescentei um
// `Slider` do Material à galeria, e ela estoura em execução com "No Material
// widget found" — porque a galeria é construída sobre `package:flutter/widgets`
// e importa `material.dart` APENAS para `Icons`, de propósito.
//
// `flutter analyze` e os testes de unidade não pegam isso: é erro de árvore de
// widgets, só aparece ao montar. A galeria é a bancada de verificação do time e
// não tinha um único teste — agora tem o que importa.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/design/gallery.dart';

void main() {
  testWidgets('monta os dois painéis sem exceção', (tester) async {
    // Superfície alta: a galeria é longa e um overflow também é uma exceção.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: DesignGalleryScreen()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Some Journey'), findsWidgets);
  });

  testWidgets('o portão de revisão da iluminação está presente', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: DesignGalleryScreen()));
    await tester.pump();

    // Dois painéis (claro e escuro), então o bloco aparece duas vezes.
    expect(find.text('A viagem, em luz'), findsNWidgets(2));
    expect(find.textContaining('abajur'), findsWidgets,
        reason: 'o rótulo diz onde o trem está e quanto a luminária pesa');
  });

  testWidgets('a galeria não usa widget do Material que exija ancestral',
      (tester) async {
    // Guarda de regressão direta: se alguém trouxer um Slider, Switch ou
    // ElevatedButton para cá, a montagem quebra — e este teste diz por quê.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: DesignGalleryScreen()));
    await tester.pump();

    expect(find.byType(Slider), findsNothing,
        reason: 'a galeria vive fora do Material; use um controle próprio');
  });
}
