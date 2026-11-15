// As fotos de uma memória como polaroids: pequenas, tortas e estáveis.
//
// O que estes testes seguram: a inclinação é sempre a MESMA para a mesma foto
// (a memória reabre com a mesa igual), fica dentro do que parece "largada"
// sem virar de lado, e tocar numa polaroid abre aquela foto — não a primeira.

import 'package:flutter/material.dart' hide MemoryImage;
import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/features/photos/polaroid_pile.dart';
import 'package:some_journey/models.dart';
import 'package:some_journey/widgets/sj_image.dart';

const _grau = 3.141592653589793 / 180;

void main() {
  group('a inclinação', () {
    test('é a mesma toda vez para a mesma foto', () {
      expect(inclinacaoDe('foto-1'), inclinacaoDe('foto-1'));
      expect(deslocamentoDe('foto-1'), deslocamentoDe('foto-1'));
    });

    test('fica entre 1,5° e 6°, para um lado ou para o outro', () {
      final angulos = [
        for (var i = 0; i < 200; i++) inclinacaoDe('9f1c-$i-a7e2'),
      ];
      for (final a in angulos) {
        expect(a.abs(), greaterThanOrEqualTo(1.5 * _grau - 1e-9));
        expect(a.abs(), lessThanOrEqualTo(6.0 * _grau + 1e-9));
      }
      // "Jogadas" é variedade: não podem cair todas para o mesmo lado.
      expect(angulos.where((a) => a > 0), isNotEmpty);
      expect(angulos.where((a) => a < 0), isNotEmpty);
      expect(angulos.toSet().length, greaterThan(20));
    });

    test('o desalinhamento vertical é pequeno', () {
      for (var i = 0; i < 200; i++) {
        final d = deslocamentoDe('id-$i');
        expect(d, inInclusiveRange(-6, 6));
      }
    });
  });

  test('a polaroid e a tela cheia usam a mesma tag, seja qual for o token', () {
    expect(
      heroDaFoto('https://x.supabase.co/obj/memories/u/1.jpg?token=AAA'),
      heroDaFoto('https://x.supabase.co/obj/memories/u/1.jpg?token=BBB'),
    );
  });

  group('a pilha', () {
    Future<void> montar(WidgetTester tester, List<MemoryImage> fotos,
        ValueChanged<int> onOpen) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: PolaroidPile(images: fotos, onOpen: onOpen),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('sem foto, não desenha nada', (tester) async {
      await montar(tester, const [], (_) {});
      expect(find.byType(Hero), findsNothing);
    });

    testWidgets('uma polaroid por foto, e o toque abre a foto tocada',
        (tester) async {
      final fotos = [
        for (var i = 0; i < 3; i++)
          MemoryImage(id: 'f$i', url: 'https://x.test/memories/f$i.jpg?t=1'),
      ];
      final abertas = <int>[];
      await montar(tester, fotos, abertas.add);

      expect(find.byType(Hero), findsNWidgets(3));
      // Pequenas: duas cabem lado a lado numa tela de celular.
      final largura = tester.getSize(find.byType(AspectRatio).first).width;
      expect(largura, lessThan(180));

      await tester.tap(find.bySemanticsLabel('Abrir foto 3 de 3 em tela cheia'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(abertas, [2]);
    });

    testWidgets('uma foto sozinha ganha mais espaço', (tester) async {
      await montar(
        tester,
        [MemoryImage(id: 'so', url: 'https://x.test/memories/so.jpg')],
        (_) {},
      );
      final largura = tester.getSize(find.byType(AspectRatio)).width;
      expect(largura, greaterThan(180));
    });
  });
}
