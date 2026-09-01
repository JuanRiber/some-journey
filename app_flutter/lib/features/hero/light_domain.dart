/// # Iluminação do herói — DOMÍNIO (Dart puro, zero Flutter).
///
/// Mesma decisão do atlas e do percurso: a lógica mora aqui e o desenho fica
/// bobo. Aqui dá para afirmar "no túnel sobra só o abajur" como aritmética, e
/// não como impressão ao olhar a tela.
///
/// ## O que este módulo resolve
///
/// O pedido não era "animar o herói" — era que **o interior e o exterior
/// interajam em iluminação**. A luz que entra pela janela muda conforme a
/// paisagem passa: campo aberto ilumina quente, a montanha esfria, o túnel
/// apaga tudo menos o abajur, o entardecer inunda de âmbar.
///
/// Num vídeo pronto essa luz viria assada e não responderia a nada. Aqui ela é
/// função da posição do rolamento — o mesmo relógio move os dois, e é isso que
/// faz o vagão e a paisagem virarem um espaço só.
///
/// ## Por que cores cruas aqui, se a regra é "nunca cor solta"
///
/// A regra vale para papéis do PRODUTO: ação, perigo, link. A cor do sol num
/// campo às três da tarde não é papel do produto, é física do mundo lá fora.
/// O que continua vindo de token é a moldura, a sombra e o véu noturno.
library;

import 'dart:math' as math;

/// Uma cor de luz, sem `dart:ui` — canais em 0..255.
///
/// Sem `Color` de propósito: mantém este arquivo importável por um teste puro,
/// e transforma "quente" e "frio" em asserções aritméticas.
class LightTint {
  const LightTint(this.r, this.g, this.b);

  final double r;
  final double g;
  final double b;

  /// Positivo = quente (mais vermelho que azul). É a medida que os testes usam
  /// para afirmar que o entardecer é o ponto mais quente do ciclo.
  double get warmth => (r - b) / 255;

  double get luminance => (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;

  static LightTint lerp(LightTint a, LightTint b, double t) => LightTint(
        a.r + (b.r - a.r) * t,
        a.g + (b.g - a.g) * t,
        a.b + (b.b - a.b) * t,
      );

  @override
  bool operator ==(Object other) =>
      other is LightTint && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() =>
      'LightTint(${r.toStringAsFixed(1)}, ${g.toStringAsFixed(1)}, ${b.toStringAsFixed(1)})';
}

/// Uma zona de iluminação, ancorada numa posição DA TIRA de paisagem.
///
/// Ancorar na tira, e não no tempo, é o que permite dizer "o túnel fica aos 55%
/// do desenho" — que é como alguém olha para a arte. Em coordenadas de
/// rolamento ninguém consegue visualizar onde a zona cai.
class LightZone {
  const LightZone({
    required this.at,
    required this.name,
    required this.tint,
    required this.exposure,
    required this.saturation,
    required this.lamp,
  });

  /// Posição na tira, 0..1.
  final double at;

  /// Para o teste falar a língua da arte: 'campo', 'tunel'...
  final String name;

  final LightTint tint;

  /// Quanta luz entra pela janela. 1.0 é a cena neutra; acima disso estoura de
  /// propósito no campo aberto.
  final double exposure;

  /// 0 = o mundo perde a cor (túnel), 1 = cor cheia.
  final double saturation;

  /// O abajur de latão. É camada própria justamente porque um banho uniforme
  /// não consegue apagar o vagão e manter a luminária acesa.
  final double lamp;
}

/// O estado da luz num instante — imutável, comparável, determinístico.
class LightSample {
  const LightSample({
    required this.tint,
    required this.exposure,
    required this.saturation,
    required this.lamp,
  });

  final LightTint tint;
  final double exposure;
  final double saturation;
  final double lamp;

  double get warmth => tint.warmth;

  /// A matriz 4×5 no formato de `ColorFilter.matrix`.
  ///
  /// A linha do alfa é a IDENTIDADE — `[0, 0, 0, 1, 0]`. É ela que preserva o
  /// recorte da janela: se alguém mexer aqui, o buraco fecha e a paisagem some
  /// atrás do vagão. Há teste para isso.
  ///
  /// Por canal: `saida = exposicao · [(1-sat)·luma + sat·canal] · k + piso`,
  /// onde `k` normaliza o tinte pelo canal mais forte (evita estouro) e `piso`
  /// é a luz ambiente quente do abajur — é o que impede o túnel de virar breu
  /// mesmo sem a camada da luminária.
  List<double> get colorMatrix {
    final maior = math.max(tint.r, math.max(tint.g, tint.b));
    final kr = maior == 0 ? 0.0 : tint.r / maior;
    final kg = maior == 0 ? 0.0 : tint.g / maior;
    final kb = maior == 0 ? 0.0 : tint.b / maior;

    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final cinza = 1 - saturation;

    double ganho(double k, double proprio) => exposure * k * proprio;

    // Piso ambiente do abajur: quente, discreto, e some quando a luminária some.
    final piso = 26.0 * lamp;

    return <double>[
      ganho(kr, cinza * lr + saturation), ganho(kr, cinza * lg),
      ganho(kr, cinza * lb), 0, piso,
      //
      ganho(kg, cinza * lr), ganho(kg, cinza * lg + saturation),
      ganho(kg, cinza * lb), 0, piso * 0.82,
      //
      ganho(kb, cinza * lr), ganho(kb, cinza * lg),
      ganho(kb, cinza * lb + saturation), 0, piso * 0.55,
      //
      0, 0, 0, 1, 0,
    ];
  }

  static LightSample lerp(LightSample a, LightSample b, double t) => LightSample(
        tint: LightTint.lerp(a.tint, b.tint, t),
        exposure: a.exposure + (b.exposure - a.exposure) * t,
        saturation: a.saturation + (b.saturation - a.saturation) * t,
        lamp: a.lamp + (b.lamp - a.lamp) * t,
      );

  @override
  bool operator ==(Object other) =>
      other is LightSample &&
      other.tint == tint &&
      other.exposure == exposure &&
      other.saturation == saturation &&
      other.lamp == lamp;

  @override
  int get hashCode => Object.hash(tint, exposure, saturation, lamp);

  @override
  String toString() => 'LightSample($tint, exp: '
      '${exposure.toStringAsFixed(2)}, sat: ${saturation.toStringAsFixed(2)}, '
      'lamp: ${lamp.toStringAsFixed(2)})';
}

/// A trilha de iluminação ao longo da tira.
class LightTrack {
  /// Precisa de ao menos duas zonas para haver interpolação. Não dá para
  /// afirmar isso num `assert` de construtor `const` (acesso a `.length` não é
  /// avaliável em tempo de compilação), então a garantia fica nos testes.
  const LightTrack(this.zones);

  final List<LightZone> zones;

  /// Suavização com derivada zero nas pontas.
  ///
  /// Linear deixaria um vinco visível ao cruzar cada zona: a luz mudaria de
  /// ritmo num piscar. Com smoothstep ela ASSENTA dentro de um ambiente e
  /// TRANSICIONA entre eles.
  static double _suave(double t) => t * t * (3 - 2 * t);

  /// A luz na posição [t] da tira. Envolve circularmente: `at(1.3) == at(0.3)`.
  ///
  /// O laço fecha por CONSTRUÇÃO, não por convenção: entre a última zona e a
  /// primeira a distância é `1 - ultima.at + primeira.at`. Ninguém precisa
  /// lembrar de duplicar a zona inicial no fim — e portanto ninguém pode
  /// esquecer.
  LightSample at(double t) {
    final p = t - t.floorToDouble();

    // A zona corrente é a última cujo `at` não passou de p; se nenhuma, a
    // última da lista (estamos no trecho que dá a volta).
    var i = -1;
    for (var k = 0; k < zones.length; k++) {
      if (zones[k].at <= p) i = k;
    }

    final daVolta = i == -1 || i == zones.length - 1;
    final a = daVolta ? zones.last : zones[i];
    final b = daVolta ? zones.first : zones[i + 1];

    final inicio = a.at;
    final vao = daVolta ? 1 - a.at + b.at : b.at - a.at;
    if (vao <= 0) return _amostra(a);

    // Distância percorrida desde `a`, já considerando a virada.
    final andado = p >= inicio ? p - inicio : 1 - inicio + p;
    final f = _suave((andado / vao).clamp(0.0, 1.0));

    return LightSample.lerp(_amostra(a), _amostra(b), f);
  }

  static LightSample _amostra(LightZone z) => LightSample(
        tint: z.tint,
        exposure: z.exposure,
        saturation: z.saturation,
        lamp: z.lamp,
      );

  /// A mesma trilha vista do atlas noturno.
  ///
  /// A arte é a mesma nos dois temas e não há variante escura. Um herói em
  /// pleno sol no meio de uma tela noturna pareceria erro de renderização — o
  /// mesmo argumento que fez o mapa ganhar filtro de tema.
  LightTrack toNight() => LightTrack([
        for (final z in zones)
          LightZone(
            at: z.at,
            name: z.name,
            // Puxa o tinte na direção do azul de meia-noite.
            tint: LightTint.lerp(z.tint, const LightTint(90, 110, 150), 0.35),
            exposure: z.exposure * 0.55,
            saturation: z.saturation * 0.85,
            // O abajur NUNCA apaga à noite: ele passa a ser a fonte principal.
            lamp: math.max(z.lamp, 0.6),
          ),
      ]);

  /// Que fração da tira está no CENTRO da janela quando o laço está em [phase].
  ///
  /// Existe para as zonas poderem ser autoradas em coordenadas da TIRA — "o
  /// túnel fica aos 55% do desenho" — em vez de coordenadas do rolamento, que
  /// ninguém consegue visualizar.
  static double windowCenter(double phase, double apertureFraction) {
    final v = (phase + apertureFraction / 2) % 1.0;
    return v < 0 ? v + 1 : v;
  }

  /// A viagem: campo, montanha, túnel, entardecer, e de volta ao campo.
  ///
  /// O túnel são DUAS zonas quase coladas de propósito — entrada abrupta, como
  /// um túnel de verdade. O entardecer são zonas largas, porque a luz do fim de
  /// tarde muda devagar.
  static const scenic = LightTrack([
    LightZone(
      at: 0.00,
      name: 'campo',
      tint: LightTint(255, 236, 198),
      exposure: 1.18,
      saturation: 1.0,
      lamp: 0.10,
    ),
    LightZone(
      at: 0.26,
      name: 'montanha',
      tint: LightTint(198, 220, 248),
      exposure: 0.86,
      saturation: 0.82,
      lamp: 0.22,
    ),
    LightZone(
      at: 0.50,
      name: 'tunel-entrada',
      tint: LightTint(120, 132, 156),
      exposure: 0.10,
      saturation: 0.18,
      lamp: 0.95,
    ),
    LightZone(
      at: 0.56,
      name: 'tunel-saida',
      tint: LightTint(150, 160, 180),
      exposure: 0.24,
      saturation: 0.35,
      lamp: 0.88,
    ),
    LightZone(
      at: 0.74,
      name: 'entardecer',
      tint: LightTint(255, 186, 116),
      exposure: 1.02,
      saturation: 1.0,
      lamp: 0.40,
    ),
  ]);
}
