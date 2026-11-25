// O contraste que só existe DEPOIS de montar o componente.
//
// `contrast_test.dart` responde pelos tokens: cada tinta contra cada
// superfície. O botão tonal (`SJButton.secondary`) escapava dele, porque o
// fundo do botão não é token nenhum — é um véu do vinho por cima da superfície
// onde ele pousa. No atlas noturno o resultado era vinho sobre navy avinhado,
// 2,6:1: "Escolher a música" e "Gravar percurso" estavam na tela e não se
// liam. Aqui a árvore é montada, o véu é composto sobre a superfície de
// verdade e a conta é feita com as cores que chegam ao pixel.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/design/components.dart';
import 'package:some_journey/design/sj_theme.dart';
import 'package:some_journey/design/tokens.dart';

/// Luminância relativa da WCAG 2.1 — a mesma conta de `contrast_test.dart`
/// (correção de gama por canal, depois a soma ponderada).
double _luminancia(Color c) {
  double canal(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
}

double _contraste(Color a, Color b) {
  final la = _luminancia(a);
  final lb = _luminancia(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Piso AA para texto: o rótulo de um botão é corpo, não ornamento.
const double _piso = 4.5;

void main() {
  for (final (modo, esquema) in [('claro', sjLight), ('escuro', sjDark)]) {
    final superficies = {
      'bg': esquema.bg,
      'surface': esquema.surface,
      'surfaceAlt': esquema.surfaceAlt,
    };

    for (final MapEntry(key: nome, value: superficie) in superficies.entries) {
      testWidgets('botão tonal no $modo, sobre $nome: o rótulo se lê',
          (tester) async {
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: SJTheme(
            scheme: esquema,
            child: ColoredBox(
              color: superficie,
              child: Center(
                child: SJButton(
                  label: 'Gravar percurso',
                  variant: SJButtonVariant.secondary,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ));

        final rotulo = tester.widget<Text>(find.text('GRAVAR PERCURSO'));
        final caixa = tester.widget<Container>(find
            .ancestor(
                of: find.text('GRAVAR PERCURSO'),
                matching: find.byType(Container))
            .first);
        final veu = (caixa.decoration! as BoxDecoration).color!;
        // O que o olho vê atrás da letra: o véu composto sobre a superfície.
        final fundo = Color.alphaBlend(veu, superficie);

        final razao = _contraste(rotulo.style!.color!, fundo);
        expect(razao, greaterThanOrEqualTo(_piso),
            reason: 'rótulo sobre o véu do botão: ${razao.toStringAsFixed(2)}:1');
      });
    }
  }
}
