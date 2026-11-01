// O piso de contraste do design system existia só como frase no docstring.
//
// `tokens.dart` sempre disse que as cores foram "checadas para contraste de
// texto (alvo WCAG AA 4.5:1 no corpo; overlines ≥3:1)". A checagem era à mão, e
// à mão escapou: o `inkFaint` do modo claro passou meses em 2,73:1 sobre `bg` e
// 2,53:1 sobre `surfaceAlt` — que é onde ele escreve o placeholder de TODO
// campo do app. Nada acusou. O analisador não lê cor, a galeria renderiza igual,
// e um cinza-areia sobre creme parece apenas "discreto" para quem desenhou e
// sabe o que está escrito ali.
//
// Esta suíte fecha esse buraco pelo único lado que não depende de alguém
// lembrar: recalcula a razão de contraste de cada par tinta↔superfície, nos
// DOIS modos, a partir dos valores reais dos tokens. Trocar um token para um
// tom mais bonito e menos legível deixou de ser possível em silêncio.
//
// O que NÃO está coberto aqui, para não prometer demais: composições. O texto
// de `SJButton.secondary` é `primary` sobre um véu de `primary` a 10% — um
// fundo que não é token nenhum, e que no modo escuro fica em 2,57:1 sobre
// `surface`. Isso é contraste de COMPONENTE e pede um teste que monte a árvore;
// este arquivo só responde pelo contrato dos tokens.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/design/tokens.dart';

/// Luminância relativa, conforme a definição da WCAG 2.1
/// (W3C/WAI, <https://www.w3.org/TR/WCAG21/#dfn-relative-luminance>).
///
/// PORQUÊ a conta é feia: não é média de canais e não é o `L` do HSL. Cada
/// canal sRGB passa ANTES pela correção de gama — trecho linear abaixo de
/// 0,03928, potência 2,4 acima dele — e só depois entra na soma ponderada
/// (o verde pesa 0,7152 porque o olho enxerga quase toda a luminância nele).
/// Pular a etapa de gama é o erro clássico de quem reimplementa isto: ele
/// infla os tons médios e aprovaria justamente o `inkFaint` que este arquivo
/// existe para reprovar. O teste `a fórmula` abaixo é a trava contra isso.
double _luminancia(Color c) {
  double canal(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
}

/// Razão de contraste da WCAG 2.1
/// (<https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio>): `(Lc + 0,05) /
/// (Le + 0,05)`, do mais claro para o mais escuro. Vai de 1:1 (cores iguais)
/// a 21:1 (preto sobre branco). A ordem dos argumentos não importa.
double _contraste(Color a, Color b) {
  final la = _luminancia(a);
  final lb = _luminancia(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Piso do próprio design system para texto terciário, hints e overlines.
const double _pisoMinimo = 3.0;

/// Piso AA para corpo de texto — o alvo declarado no topo de `tokens.dart`.
const double _pisoCorpo = 4.5;

Map<String, Color> _superficies(SJScheme s) => {
      'bgDeep': s.bgDeep,
      'bg': s.bg,
      'surface': s.surface,
      'surfaceAlt': s.surfaceAlt,
    };

Map<String, Color> _tintas(SJScheme s) => {
      'ink': s.ink,
      'inkSoft': s.inkSoft,
      'inkFaint': s.inkFaint,
      'secondary': s.secondary,
      'accent': s.accent,
      'danger': s.danger,
      'moss': s.moss,
      'highlight': s.highlight,
    };

/// Em QUAIS superfícies cada tinta de texto precisa vencer o piso.
///
/// A lista não é "todas contra todas" de propósito — um piso que o uso real não
/// cobra vira pressão para escurecer cor de marca sem motivo, e o teste perde a
/// autoridade. Quem escreve onde foi lido em `lib/`:
///
/// - `highlight` fica FORA de `bgDeep`: é a itálica de humor da jornada
///   (`journeyMoodStyle`) e o preenchimento de chip/badge — pousa em cartão e em
///   página, nunca na barra. Sobre `bgDeep` no modo claro ele mede 2,96:1; se um
///   dia o humor for parar numa barra, é esta linha que precisa mudar primeiro.
/// - `inkFaint` entra em `bgDeep` mesmo escrevendo pouco ali, porque é onde o
///   ícone de música mora (`memory_music_section`) e porque é a superfície mais
///   apertada do modo claro: fixar a tinta mais fraca pela pior superfície é o
///   que impede a correção de nascer já no limite.
///
/// `frame` e `line` não aparecem em lista nenhuma: moldura decorativa e
/// hairline não são texto, e cobrá-las em 3:1 apagaria exatamente a discrição
/// que é o papel delas.
const Map<String, List<String>> _ondeCadaTintaEscreve = {
  'ink': ['bgDeep', 'bg', 'surface', 'surfaceAlt'],
  'inkSoft': ['bgDeep', 'bg', 'surface', 'surfaceAlt'],
  'inkFaint': ['bgDeep', 'bg', 'surface', 'surfaceAlt'],
  'secondary': ['bgDeep', 'bg', 'surface', 'surfaceAlt'],
  'accent': ['bgDeep', 'bg', 'surface', 'surfaceAlt'],
  'danger': ['bgDeep', 'bg', 'surface', 'surfaceAlt'],
  'moss': ['bgDeep', 'bg', 'surface', 'surfaceAlt'],
  'highlight': ['bg', 'surface', 'surfaceAlt'],
};

/// Mensagem de falha que já entrega o diagnóstico: sem isto, um vermelho diz
/// "2.73 is not greater than 3.0" e ninguém sabe qual par quebrou.
String _razao(String modo, String tinta, String fundo, double r) =>
    '$modo: $tinta sobre $fundo = ${r.toStringAsFixed(2)}:1';

void _pisoDeTexto(String modo, SJScheme s) {
  final superficies = _superficies(s);
  final tintas = _tintas(s);

  group('modo $modo', () {
    for (final entrada in _ondeCadaTintaEscreve.entries) {
      final tinta = tintas[entrada.key]!;
      for (final nomeFundo in entrada.value) {
        test('${entrada.key} sobre $nomeFundo vence o piso de 3:1', () {
          final r = _contraste(tinta, superficies[nomeFundo]!);
          expect(
            r,
            greaterThanOrEqualTo(_pisoMinimo),
            reason: _razao(modo, entrada.key, nomeFundo, r),
          );
        });
      }
    }

    // `ink` e `inkSoft` são corpo e apoio de corpo — para eles o alvo declarado
    // é o AA cheio, não o piso. `inkFaint` fica de fora deste grupo de propósito:
    // subi-lo a 4,5:1 o colaria em `inkSoft` e acabaria com a terceira tinta.
    for (final nome in ['ink', 'inkSoft']) {
      for (final fundo in superficies.entries) {
        test('$nome sobre ${fundo.key} cumpre AA de corpo (4,5:1)', () {
          final r = _contraste(tintas[nome]!, fundo.value);
          expect(
            r,
            greaterThanOrEqualTo(_pisoCorpo),
            reason: _razao(modo, nome, fundo.key, r),
          );
        });
      }
    }

    test('onPrimary sobre primary cumpre AA de corpo (4,5:1)', () {
      // É o rótulo do botão cheio — o texto mais clicado do app.
      final r = _contraste(s.onPrimary, s.primary);
      expect(
        r,
        greaterThanOrEqualTo(_pisoCorpo),
        reason: _razao(modo, 'onPrimary', 'primary', r),
      );
    });

    test('a hierarquia das tintas sobrevive à correção de contraste', () {
      // A saída preguiçosa para um par reprovado é empurrar a tinta fraca para
      // cima até ela virar a de cima. Se `inkFaint` alcançar `inkSoft`, o
      // design system passa a ter duas tintas e não três — e o teste de piso
      // ficaria verde justamente por ter destruído o que protegia.
      final faint = _contraste(s.inkFaint, s.bg);
      final soft = _contraste(s.inkSoft, s.bg);
      final forte = _contraste(s.ink, s.bg);
      expect(faint, lessThan(soft), reason: _razao(modo, 'inkFaint', 'bg', faint));
      expect(soft, lessThan(forte), reason: _razao(modo, 'inkSoft', 'bg', soft));
      // Margem real entre as duas tintas quietas, não um fio de diferença.
      expect(
        soft / faint,
        greaterThanOrEqualTo(1.3),
        reason: '$modo: inkSoft/inkFaint = ${(soft / faint).toStringAsFixed(2)}',
      );
    });
  });
}

void main() {
  group('a fórmula', () {
    // Ancoras publicadas pela própria WCAG. A terceira é a que importa: #767676
    // e #777777 estão a um passo um do outro e caem em lados opostos do 4,5:1.
    // Uma implementação sem a etapa de gama daria ~2,05:1 para os dois e
    // reprovaria meio design system; uma que troque 2,4 por 2,2 erra o
    // desempate. Nenhum par de tokens separa as duas versões tão bem quanto
    // este.
    test('preto sobre branco é 21:1', () {
      expect(
        _contraste(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21.0, 0.001),
      );
    });

    test('cor contra ela mesma é 1:1', () {
      expect(
        _contraste(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)),
        closeTo(1.0, 0.001),
      );
    });

    test('#767676 passa e #777777 reprova o AA sobre branco', () {
      const branco = Color(0xFFFFFFFF);
      expect(_contraste(const Color(0xFF767676), branco), closeTo(4.542, 0.002));
      expect(_contraste(const Color(0xFF777777), branco), closeTo(4.478, 0.002));
    });

    test('a ordem dos argumentos não muda a razão', () {
      const a = Color(0xFF2B2724);
      const b = Color(0xFFF5F0E6);
      expect(_contraste(a, b), closeTo(_contraste(b, a), 1e-12));
    });
  });

  // O número que originou esta suíte, preso no lugar: se alguém devolver o
  // antigo #9C917E ao token, o grupo "modo claro" acusa — e este teste explica
  // por quê, com a conta à vista.
  test('o inkFaint antigo reprovava, o atual passa', () {
    const antigo = Color(0xFF9C917E);
    expect(_contraste(antigo, sjLight.bg), closeTo(2.73, 0.01));
    expect(_contraste(antigo, sjLight.surfaceAlt), closeTo(2.53, 0.01));
    expect(_contraste(sjLight.inkFaint, sjLight.bg), greaterThanOrEqualTo(3.0));
    expect(
      _contraste(sjLight.inkFaint, sjLight.surfaceAlt),
      greaterThanOrEqualTo(3.0),
    );
  });

  _pisoDeTexto('claro', sjLight);
  _pisoDeTexto('escuro', sjDark);
}
