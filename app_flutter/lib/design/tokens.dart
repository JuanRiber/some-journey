/// # Some Journey — Design Tokens (fonte única da verdade)
///
/// Este arquivo é o CORAÇÃO do design system. Nenhum valor de cor, espaçamento,
/// raio, tipografia, elevação ou movimento deve ser escrito "solto" nas telas —
/// tudo vem daqui. O `mobile/src/theme/tokens.ts` (Expo) espelha estes MESMOS
/// valores, então as duas plataformas ficam idênticas.
///
/// Dois modos, uma linguagem:
/// - **Claro = "papel quente"** (PADRÃO): creme/off-white, tinta marrom quente,
///   vinho como ação, azul-lago, couro/mostarda, musgo. A sensação de um diário
///   de viagens de papel envelhecido.
/// - **Escuro = "atlas noturno"**: navy profundo, creme como tinta, vinho/ciano
///   vivos, ouro nas molduras. A identidade da landing.
///
/// As cores são orgânicas — terra, vinho, lago, musgo — mas com croma de
/// verdade: acento que não se distingue do marrom não é acento. Checadas para
/// contraste de texto (alvo WCAG AA 4.5:1 no corpo; overlines ≥3:1 por serem
/// grandes/bold).
/// "Checadas" era à mão, e à mão escapou: quem cobra esse piso agora é
/// `test/contrast_test.dart`, que recalcula a razão de cada par tinta↔superfície
/// nos dois modos. Mudou um valor aqui, é lá que o estrago aparece.
library;

import 'package:flutter/widgets.dart';

/// Papéis semânticos de cor. Uma tela pede `scheme.primary`, nunca "#6E2C3A" —
/// assim trocar de tema (claro/escuro) é automático.
@immutable
class SJScheme {
  const SJScheme({
    required this.brightness,
    required this.bgDeep,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.line,
    required this.frame,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.accent,
    required this.moss,
    required this.highlight,
    required this.danger,
    required this.shadow,
  });

  final Brightness brightness;

  // Neutros (fundo → tinta)
  final Color bgDeep; // atrás de tudo, barras
  final Color bg; // superfície principal da página
  final Color surface; // cards (levemente destacados do fundo)
  final Color surfaceAlt; // inputs, placeholders, superfície recuada
  final Color ink; // texto primário
  final Color inkSoft; // texto secundário
  final Color inkFaint; // texto terciário / hints
  final Color line; // hairlines, divisores
  final Color frame; // molduras decorativas (foto/mapa/ilustração)

  // Acentos (papéis, não nomes de cor)
  final Color primary; // AÇÃO principal / jornada ativa (vinho)
  final Color onPrimary; // texto sobre `primary`
  final Color secondary; // links, pontos soltos (azul-lago / ciano)
  final Color accent; // overlines, numerais, selos (couro / ouro)
  final Color moss; // natureza / sucesso (verde musgo)
  final Color highlight; // eras / chips quentes (mostarda / terracota)
  final Color danger; // erro / destrutivo

  final Color shadow; // cor base das sombras (muito suave)
}

/// Modo CLARO — "papel quente" (padrão do app).
///
/// PORQUÊ os acentos subiram de croma: a primeira paleta era toda de tons
/// escurecidos e pouco saturados sobre creme acinzentado — legível, mas vista
/// inteira a tela lia como uma cor só. O papel continua papel e a tinta
/// continua tinta; o que mudou é que cada acento agora tem cor de verdade
/// (vinho que é vinho, não marrom) e o cartão levanta do fundo. Os pisos de
/// contraste são os mesmos e continuam cobrados em `test/contrast_test.dart`.
const SJScheme sjLight = SJScheme(
  brightness: Brightness.light,
  bgDeep: Color(0xFFEFE3CC),
  bg: Color(0xFFF8F2E4), // creme papel, mais quente e menos cinza
  surface: Color(0xFFFFFCF6), // quase branco: o card levanta do papel
  surfaceAlt: Color(0xFFF2E8D4), // areia clara (inputs)
  ink: Color(0xFF2A2420), // marrom quase-preto quente
  inkSoft: Color(0xFF6B5E4C),
  // A tinta mais quieta do conjunto já foi a única abaixo do piso (2,73:1
  // sobre `bg`) — e é sobre `surfaceAlt` que ela escreve o placeholder dos
  // campos. Fica no MÍNIMO que passa de 3:1 em todas as superfícies claras
  // (3,04 / 3,45 / 3,77 / 3,17), mantendo o matiz e a distância para
  // `inkSoft`: continua sendo a terciária, não virou uma segunda secundária.
  inkFaint: Color(0xFF8E806A),
  line: Color(0x1A2A2420), // tinta a 10%
  frame: Color(0xFFD2AE68), // couro claro decorativo, puxado para o dourado
  primary: Color(0xFFA3213F), // vinho vivo (ação)
  onPrimary: Color(0xFFFFF8EC),
  secondary: Color(0xFF11718F), // azul-lago
  accent: Color(0xFF8F5B0E), // couro âmbar (legível como overline)
  moss: Color(0xFF2A744E), // verde musgo
  highlight: Color(0xFFC4671A), // terracota
  danger: Color(0xFFC2331C),
  shadow: Color(0xFF2A2420),
);

/// Modo ESCURO — "atlas noturno" (espelha a landing / mobile colors.ts).
const SJScheme sjDark = SJScheme(
  brightness: Brightness.dark,
  bgDeep: Color(0xFF080D18),
  bg: Color(0xFF0D1524),
  surface: Color(0xFF16213A),
  surfaceAlt: Color(0xFF1B2740),
  ink: Color(0xFFF3ECDC),
  inkSoft: Color(0xFF9AA3B8),
  inkFaint: Color(0xFF6B7488),
  line: Color(0x1FF3ECDC), // creme a 12%
  frame: Color(0xFF8C7440),
  primary: Color(0xFFB7314F), // vinho vivo
  onPrimary: Color(0xFFF3ECDC),
  secondary: Color(0xFF4FB3C7), // ciano dos lagos
  accent: Color(0xFFE3B04B), // ouro
  moss: Color(0xFF6BA583),
  highlight: Color(0xFFD9A94E),
  danger: Color(0xFFE4604E),
  shadow: Color(0xFF000000),
);

/// Famílias tipográficas. Serifa editorial para títulos/afeto; sans para
/// interface; mono para overlines/selos (o "01 / OS MOMENTOS" da landing).
/// A serifa é a Fraunces, embutida (`pubspec.yaml`): uma fonte de sistema não
/// existe em todo lugar, e onde faltava — a web inteira — o título caía em
/// sans sem aviso. A sans e a mono ainda são de sistema; os nomes abaixo são o
/// ponto único de troca.
abstract final class SJType {
  static const serif = 'Fraunces';
  static const List<String> serifFallback = [
    'Georgia',
    'Times New Roman',
    'serif',
  ];
  static const sans = 'Inter'; // cai no system sans até a fonte ser embutida
  static const List<String> sansFallback = [
    'SF Pro Text',
    'Roboto',
    'Segoe UI',
    'sans-serif',
  ];
  static const mono = 'Menlo';
  static const List<String> monoFallback = ['Consolas', 'Courier New', 'monospace'];

  // Escala tipográfica (tamanho / altura de linha). Muito contraste entre
  // título (serifa grande) e corpo (sans calmo).
  static const double displaySize = 34, displayLine = 40;
  static const double h1Size = 28, h1Line = 34;
  static const double h2Size = 22, h2Line = 28;
  static const double titleSize = 18, titleLine = 24;
  static const double bodySize = 16, bodyLine = 24;
  static const double bodySmSize = 14, bodySmLine = 20;
  static const double captionSize = 13, captionLine = 18;
  static const double overlineSize = 11, overlineLine = 16;
  static const double overlineTracking = 1.6;
}

/// Espaçamento base 4pt (ritmo do grid). Use SEMPRE estes nomes.
abstract final class SJSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
  static const double x16 = 64;
  // Margem horizontal padrão das telas.
  static const double screenX = 24;
}

/// Escala de bordas. Cards com cantos "discretamente arredondados".
abstract final class SJRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
  static const double pill = 999;
}

/// Movimento com propósito: durações e curvas (estilo Apple/Arc — decelerate
/// enfático). Microinterações usam mola.
abstract final class SJMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 360);
  static const Duration page = Duration(milliseconds: 420);

  /// Cerimônia — abrir e fechar o livro do cadastro (`SJBook`).
  ///
  /// PORQUÊ a escala ganhou um degrau acima de `page`: as outras durações são
  /// de TRANSIÇÃO, onde o tempo é custo e o alvo é não ser notado. Esta é de
  /// ENCENAÇÃO — a única animação do app que o usuário deve ver acontecer.
  /// Uma capa de livro tem massa; abri-la em 420ms parece uma carta de baralho
  /// virando. O teto é o cadastro: passando de ~1s, quem só quer criar a conta
  /// espera pela animação — e esse é o momento em que ela deixa de ser um
  /// presente e vira pedágio.
  static const Duration ceremony = Duration(milliseconds: 900);

  static const Cubic standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Cubic enter = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Cubic exit = Cubic(0.3, 0.0, 0.8, 0.15);
}

/// Sombras extremamente suaves (o app respira; nada de sombra dura).
abstract final class SJElevation {
  /// Card em repouso.
  static List<BoxShadow> e1(SJScheme s) => [
        BoxShadow(
          color: s.shadow.withValues(alpha: s.brightness == Brightness.dark ? 0.40 : 0.06),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  /// Elemento flutuante (bottom sheet, FAB, diálogo).
  static List<BoxShadow> e2(SJScheme s) => [
        BoxShadow(
          color: s.shadow.withValues(alpha: s.brightness == Brightness.dark ? 0.52 : 0.10),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ];
}
