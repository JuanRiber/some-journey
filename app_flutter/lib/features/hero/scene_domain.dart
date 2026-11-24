/// # A cena do herói — DOMÍNIO (Dart puro, zero Flutter).
///
/// `light_domain.dart` diz que LUZ entra no vagão em cada ponto da viagem. Este
/// arquivo diz ONDE está cada coisa nesse ponto: em que pixel de cada tira de
/// paisagem a janela está, onde está cada bolha do cachimbo, quanto o peito do
/// viajante subiu. Tudo lê o mesmo relógio — é isso que faz o túnel escurecer
/// a janela e o vagão no mesmo quadro, e não "mais ou menos junto".
///
/// ## Não há quadros
///
/// A cena não é uma sequência de imagens: é uma função do tempo. Dado um
/// instante, cada camada sabe onde está, e cada bolha sabe sua posição, seu
/// tamanho e sua opacidade. Consequências que valem mais que a economia de
/// arquivo:
///
/// - **o laço fecha por construção** — toda camada anda um número inteiro de
///   ladrilhos por ciclo, então o fim do ciclo É o começo, sem quadro de emenda;
/// - **nada pula** — posição é função contínua do tempo, e isso se afirma em
///   teste, não se confere olhando;
/// - **nada aparece do nada** — só existe o que a conta diz que existe.
///
/// ## A paisagem é a pintura
///
/// O que passa na janela não é desenhado aqui nem em lugar nenhum do app: são
/// tiras recortadas da própria ilustração (`tool/hero_landscape.py`, que monta
/// o atlas `first-class-landscape.webp`). Este arquivo só sabe as medidas delas
/// ([HeroAtlas]) e a que velocidade cada uma anda ([HeroTravel]) — paralaxe: o
/// trilho passa mais depressa que o prado, que passa mais depressa que a serra.
///
/// ## O salto no escuro
///
/// A serra e as nuvens mal andam. Se fosse só isso, a paisagem do outro lado do
/// túnel seria a mesma, um palmo adiante. Então elas avançam um trecho a mais
/// enquanto a janela está TODA coberta pela parede ([HeroTravel.hidden]) — o
/// trem atravessou a montanha e saiu em outro vale. Ninguém vê o salto porque
/// não há o que ver; há teste para ele só acontecer no escuro.
library;

import 'dart:math' as math;

import 'light_domain.dart';

/// Geometria da ilustração, em pixels da arte (1536×683).
///
/// A cena inteira é desenhada nessas coordenadas e escalada de uma vez; nenhum
/// número daqui depende do tamanho da tela.
abstract final class HeroArtboard {
  static const double width = 1536;
  static const double height = 683;

  /// A caixa do vidro. O recorte de verdade (canto arredondado, peitoril
  /// inclinado, sapato) está no alfa de `first-class-interior.webp`; a paisagem
  /// só precisa cobrir a caixa que o contém.
  static const double glassLeft = 577;
  static const double glassRight = 1536;
  static const double glassTop = 0;
  static const double glassBottom = 590;
  static const double glassWidth = glassRight - glassLeft;
  static const double glassHeight = glassBottom - glassTop;

  /// Linha do horizonte, onde a ilustração original também a põe.
  static const double horizon = 392;

  /// A boca do fornilho do cachimbo. TODA bolha nasce aqui.
  static const double pipeX = 367;
  static const double pipeY = 285;

  /// O abajur de latão.
  static const double lampX = 126;
  static const double lampY = 78;

  /// O que é personagem: nada que flutua pode entrar à esquerda disto na
  /// altura do rosto. O nariz fica em x≈300; a folga é a haste do cachimbo.
  static const double characterEdge = 338;
}

// ---------------------------------------------------------------------------
// Aritmética compartilhada
// ---------------------------------------------------------------------------

double _wrap(double v) {
  final r = v - v.floorToDouble();
  return r < 0 ? r + 1 : r;
}

/// A diferença `a - b` na volta mais curta, em -0.5..0.5.
double _signed(double d) => d - (d + 0.5).floorToDouble();

double _smooth(double t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  return t * t * (3 - 2 * t);
}

/// Número pseudoaleatório fixo para o par (n, sal), em 0..1.
///
/// Sem `Random`: a cena não tem estado, e a centésima bolha tem de ser a mesma
/// bolha em qualquer aparelho e em qualquer ordem de chamada.
double _hash(int n, int salt) {
  final x = math.sin(n * 12.9898 + salt * 78.233) * 43758.5453;
  return x - x.floorToDouble();
}

/// Onda triangular de período 1, em -1..1. É o que dá aresta aos picos: uma
/// soma de senos desenha colina, nunca rocha.
double _tri(double x) => 4 * (x - (x + 0.5).floorToDouble()).abs() - 1;

// ---------------------------------------------------------------------------
// A viagem
// ---------------------------------------------------------------------------

/// Uma camada de paisagem: de que tamanho é, e quanto salta no escuro.
///
/// A velocidade não se escolhe: sai do tamanho. Uma camada anda exatamente
/// `tile × tiles` pixels por ciclo — é o que fecha o laço —, e o que não for
/// salto é o passo visível.
class StripLayer {
  const StripLayer(
    this.name, {
    required this.tile,
    this.tiles = 1,
    this.skip = 0,
    this.origin = 0,
  });

  final String name;

  /// Largura de um ladrilho da camada, em pixels da arte. Para as camadas
  /// pintadas é a largura da tira no atlas.
  final double tile;

  /// Quantos ladrilhos passam por ciclo.
  final int tiles;

  /// Quanto a camada avança durante o túnel, em tiras de referência.
  final double skip;

  /// O pixel do ladrilho que está na borda esquerda do vidro quando o centro
  /// da janela está no começo da trilha de luz (o campo aberto).
  final double origin;

  /// Comprimento da camada, em tiras de referência.
  double get span => tile * tiles / HeroTravel.reference;

  /// Velocidade visível, relativa à tira de referência.
  double get speed => span - skip;

  /// Quanto da camada cabe na janela.
  double get visible => HeroTravel.aperture / span;

  /// O pixel (sem dar a volta) que está na borda esquerda do vidro.
  double _left(double phase) {
    final c = HeroTravel.center(phase);
    return origin + (speed * c + skip * HeroTravel.hidden(c)) * HeroTravel.reference;
  }

  /// O pixel do ladrilho que está na borda esquerda do vidro, em 0..[tile].
  double pixelAt(double phase) {
    final p = _left(phase) % tile;
    return p < 0 ? p + tile : p;
  }

  /// Em que ponto da camada inteira (0..1) está o pixel de fração [s] da
  /// janela (0 = borda esquerda do vidro, 1 = direita).
  double at(double phase, double s) => _wrap(
      (_left(phase) + s * HeroArtboard.glassWidth) / (tile * tiles));

  /// O inverso: em que fração da janela cai o ponto [v] da camada. Fora de
  /// 0..1 o ponto não está à vista; o valor continua útil para quem desenha
  /// algo largo que entra aos poucos.
  double screenOf(double phase, double v) =>
      0.5 + _signed(v - at(phase, 0.5)) * span / HeroTravel.aperture;
}

/// O relógio e a geografia da viagem.
abstract final class HeroTravel {
  /// Um ciclo completo. Devagar de propósito: é uma tela de login, não um
  /// trailer — o movimento existe para a tela respirar, não para ser assistido.
  static const double loopSeconds = 72;

  /// Que fração da tira de referência cabe na janela.
  static const double aperture = 0.09;

  /// O comprimento da tira de referência, em pixels da arte: o que passaria
  /// num ciclo por um ponto que andasse à velocidade 1.
  static const double reference = HeroArtboard.glassWidth / aperture;

  // As camadas pintadas. `tile` é a largura da tira no atlas ([HeroAtlas]);
  // `origin` põe o campo aberto da ilustração original na partida.
  static const clouds =
      StripLayer('nuvens', tile: 1400, skip: 0.0914, origin: 183);
  static const far = StripLayer('serra', tile: 1386, skip: 0.0501, origin: 560);
  static const valley = StripLayer('vale', tile: 2129, origin: 300);
  static const meadowBack = StripLayer('prado-fundo', tile: 1774, tiles: 3);
  static const meadow = StripLayer('prado', tile: 2129, tiles: 5);

  /// O que corre rente ao trem: postes, o corte na rocha, a parede do túnel.
  /// Não é pintura — é o único plano desenhado. A origem centra a camada na
  /// janela, e com isso a posição nela coincide com a da trilha de luz.
  static const track = StripLayer(
    'trilho',
    tile: 3 * reference,
    origin: -HeroArtboard.glassWidth / 2,
  );

  static const layers = [clouds, far, valley, meadowBack, meadow, track];

  /// O túnel, em coordenadas da camada do trilho (que coincidem com as da
  /// trilha de luz: o centro da janela está em `v` quando a luz é `at(v)`).
  static const double tunnelFrom = 0.47;
  static const double tunnelTo = 0.57;

  /// O corte na rocha que leva à boca do túnel, e o que sai dela.
  static const double cuttingFrom = 0.39;
  static const double cuttingTo = 0.65;

  static double phaseAt(double seconds) => _wrap(seconds / loopSeconds);

  /// A posição da tira que está no centro da janela — a mesma conta da luz.
  static double center(double phase) =>
      LightTrack.windowCenter(phase, aperture);

  /// 0 antes do túnel, 1 depois, e a subida inteira acontece com a janela
  /// coberta de ponta a ponta. É o salto no escuro das camadas distantes.
  static double hidden(double c) {
    final meia = track.visible / 2;
    final de = tunnelFrom + meia, ate = tunnelTo - meia;
    return _smooth((_wrap(c) - de) / (ate - de));
  }

  /// Que fração da largura da janela a parede do túnel cobre, 0..1.
  static double darkness(double phase) {
    final a = track.screenOf(phase, tunnelFrom);
    final b = track.screenOf(phase, tunnelTo);
    return (math.min(b, 1.0) - math.max(a, 0.0)).clamp(0.0, 1.0);
  }

  /// Quanto da luz de fora sobra na paisagem.
  ///
  /// A paisagem tem cor própria, mas não luz própria: se o vagão escurece
  /// porque o trem entrou num corte de rocha, o que se vê pela janela está na
  /// mesma sombra. Sem isto a trilha apagava o interior com o campo ainda em
  /// pleno sol do outro lado do vidro — dois lugares, não um.
  static double outsideGain(LightSample luz) =>
      0.30 + 0.70 * _smooth(luz.exposure / 0.86);
}

// ---------------------------------------------------------------------------
// O relevo
// ---------------------------------------------------------------------------

/// O único relevo que ainda é conta: o corte na rocha e a parede do túnel.
/// O resto da paisagem é pintura e vem pronto do atlas.
abstract final class Terrain {
  /// O corte e a parede do túnel, na camada do trilho: altura a partir do PÉ
  /// da janela, em fração dela. Acima de 1 a janela está coberta.
  static double cutting(double v) {
    final p = _wrap(v);
    if (p >= HeroTravel.tunnelFrom && p <= HeroTravel.tunnelTo) return 1.5;
    const teto = 0.84;
    final pedra = 0.035 * _tri(p * 211 + 0.2) + 0.02 * _tri(p * 499 + 0.6);
    if (p < HeroTravel.tunnelFrom) {
      final t = _smooth((p - HeroTravel.cuttingFrom) /
          (HeroTravel.tunnelFrom - HeroTravel.cuttingFrom));
      return t * (teto + pedra);
    }
    final t = _smooth((HeroTravel.cuttingTo - p) /
        (HeroTravel.cuttingTo - HeroTravel.tunnelTo));
    return t * (teto + pedra);
  }
}

// ---------------------------------------------------------------------------
// O que povoa a paisagem
// ---------------------------------------------------------------------------

enum SceneryKind { pole, lamp, light }

/// Uma coisa plantada numa camada.
class Scenery {
  const Scenery(this.kind, this.v, this.depth, this.size, this.seed);

  final SceneryKind kind;

  /// Posição na camada, 0..1.
  final double v;

  /// 0 = no fundo da camada (perto do horizonte), 1 = na frente.
  final double depth;

  /// Tamanho relativo, 1 = o normal do tipo.
  final double size;

  /// Para quem desenha variar cor e forma sem sortear nada.
  final int seed;
}

/// O pouco que é plantado por cima da pintura. Gerado uma vez, sempre igual.
abstract final class HeroScenery {
  /// Postes de telégrafo, um a cada passo fixo — é o metrônomo da velocidade.
  /// Não há poste dentro do corte nem do túnel.
  static const int poleCount = 60;
  static final List<Scenery> poles = [
    for (var i = 0; i < poleCount; i++)
      if (Terrain.cutting((i + 0.5) / poleCount) <= 0)
        Scenery(SceneryKind.pole, (i + 0.5) / poleCount, 1, 1, i),
  ];

  /// As lâmpadas da parede do túnel: no escuro, são elas que dizem que o trem
  /// continua andando.
  static final List<Scenery> lamps = [
    for (var i = 0; i < 8; i++)
      Scenery(
        SceneryKind.lamp,
        HeroTravel.tunnelFrom +
            (i + 0.5) * (HeroTravel.tunnelTo - HeroTravel.tunnelFrom) / 8,
        1,
        1,
        i,
      ),
  ];

  /// As janelas acesas da vila do vale, que só aparecem quando a luz de fora
  /// cai. `v` e `depth` aqui são o afastamento de cada luz em relação à âncora
  /// da vila ([HeroAtlas.villages]), em pixels da arte: a vila não tem casas
  /// desenhadas, e de longe, no escuro, uma vila é isso — luzes.
  static final List<Scenery> village = [
    for (var i = 0; i < 9; i++)
      Scenery(
        SceneryKind.light,
        -26 + 52 * _hash(i, 81),
        -3 + 9 * _hash(i, 82),
        0.7 + 0.7 * _hash(i, 83),
        i,
      ),
  ];
}

// ---------------------------------------------------------------------------
// O atlas da paisagem
// ---------------------------------------------------------------------------

/// Um retângulo do atlas, em pixels dele.
class AtlasRect {
  const AtlasRect(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;
}

/// Onde está cada peça em `first-class-landscape.webp`.
///
/// São os números que `tool/hero_landscape.py` imprime no fim. Estão copiados
/// aqui, e não lidos de um arquivo, porque o atlas é gerado à mão e raramente:
/// mudou uma medida lá, é aqui que ela se atualiza — e o teste que confere a
/// largura de cada tira contra a camada que a rola é o que pega o esquecimento.
abstract final class HeroAtlas {
  static const clouds = AtlasRect(2, 2, 1400, 300);
  static const far = AtlasRect(2, 306, 1386, 218);
  static const valley = AtlasRect(2, 528, 2129, 148);
  static const meadowBack = AtlasRect(2, 680, 1774, 54);
  static const meadow = AtlasRect(2, 738, 2129, 66);

  /// O grão da tinta do céu (cíclico nas duas direções) e a rocha do corte do
  /// túnel (cíclica só na horizontal).
  static const canvas = AtlasRect(1412, 2, 384, 192);
  static const rock = AtlasRect(1412, 198, 384, 204);

  /// A que linha da ARTE corresponde o alto de cada tira.
  static const double cloudsTop = 0;
  static const double farTop = 244;
  static const double valleyTop = 366;
  static const double meadowBackTop = 494;
  static const double meadowTop = HeroArtboard.glassBottom - 66;

  /// O grão é multiplicado sobre o céu e o escurece nesta proporção, em média;
  /// quem pinta o céu compensa.
  static const double canvasMean = 0.9403;

  /// Onde fica a vila na tira do vale (ela aparece duas vezes: ida e volta), e
  /// em que linha da arte.
  static const List<double> villages = [462, 1736];
  static const double villageRow = 470;
}

// ---------------------------------------------------------------------------
// O céu e a luz lá de fora
// ---------------------------------------------------------------------------

/// O céu num ponto da viagem.
class SkySample {
  const SkySample({
    required this.top,
    required this.horizon,
    required this.land,
    required this.clouds,
    required this.sun,
    required this.stars,
  });

  /// O alto e a barra do céu.
  final LightTint top;
  final LightTint horizon;

  /// A cor da luz que cai sobre a terra e sobre as nuvens. Multiplica a cor
  /// da pintura: branco é a pintura como ela é.
  final LightTint land;
  final LightTint clouds;

  /// 0..1: quão baixo está o sol. 1 é o disco pousado no horizonte, na saída
  /// do túnel; conforme cai a zero ele sobe e sai pelo alto da janela.
  final double sun;

  /// 0..1: quanto as estrelas aparecem.
  final double stars;
}

/// O céu ao longo da tira, ancorado nas MESMAS posições da trilha de luz.
///
/// Reusa `LightTrack` como interpolador — mesma suavização, mesmo fechamento
/// de laço — em vez de reescrever a conta com outro nome. As zonas do túnel
/// repetem o tom vizinho: ali a janela está coberta e o céu só precisa não
/// dar um salto ao reaparecer.
///
/// O campo aberto tem EXATAMENTE o céu da ilustração (o azul e o creme foram
/// medidos nela) e luz branca sobre a terra: ali a janela é a pintura original.
/// O resto da viagem é essa mesma pintura sob outra luz.
abstract final class HeroSky {
  static LightZone _z(double at, String n, LightTint t, [double extra = 0]) =>
      LightZone(
          at: at, name: n, tint: t, exposure: extra, saturation: 1, lamp: 0);

  static final _top = LightTrack([
    _z(0.00, 'campo', const LightTint(106, 145, 156)),
    _z(0.26, 'montanha', const LightTint(100, 142, 166)),
    _z(0.50, 'tunel-entrada', const LightTint(92, 124, 148)),
    _z(0.56, 'tunel-saida', const LightTint(84, 88, 130)),
    _z(0.74, 'entardecer', const LightTint(96, 104, 146)),
  ]);

  static final _horizon = LightTrack([
    _z(0.00, 'campo', const LightTint(244, 223, 178)),
    _z(0.26, 'montanha', const LightTint(230, 226, 198)),
    _z(0.50, 'tunel-entrada', const LightTint(206, 210, 200)),
    _z(0.56, 'tunel-saida', const LightTint(248, 172, 102), 1),
    _z(0.74, 'entardecer', const LightTint(250, 190, 112), 1),
  ]);

  static final _land = LightTrack([
    _z(0.00, 'campo', const LightTint(255, 255, 255)),
    _z(0.26, 'montanha', const LightTint(236, 244, 255)),
    _z(0.50, 'tunel-entrada', const LightTint(196, 204, 220)),
    _z(0.56, 'tunel-saida', const LightTint(186, 128, 112)),
    _z(0.74, 'entardecer', const LightTint(196, 144, 120)),
  ]);

  static final _clouds = LightTrack([
    _z(0.00, 'campo', const LightTint(255, 255, 255)),
    _z(0.26, 'montanha', const LightTint(246, 250, 255)),
    _z(0.50, 'tunel-entrada', const LightTint(206, 212, 224)),
    _z(0.56, 'tunel-saida', const LightTint(255, 184, 132)),
    _z(0.74, 'entardecer', const LightTint(255, 198, 150)),
  ]);

  static const _meiaNoite = LightTint(10, 16, 38);
  static const _barraDaNoite = LightTint(34, 46, 82);
  static const _luar = LightTint(62, 80, 124);

  /// O céu quando o centro da janela está em [c]. Em [night] (atlas noturno) a
  /// mesma viagem acontece de madrugada: o entardecer vira uma barra violeta,
  /// o sol não aparece e as estrelas não somem.
  static SkySample at(double c, {bool night = false}) {
    final top = _top.at(c).tint;
    final barra = _horizon.at(c);
    final land = _land.at(c).tint;
    final clouds = _clouds.at(c).tint;
    if (!night) {
      return SkySample(
        top: top,
        horizon: barra.tint,
        land: land,
        clouds: clouds,
        sun: barra.exposure,
        stars: 0,
      );
    }
    return SkySample(
      top: LightTint.lerp(_meiaNoite, top, 0.06),
      horizon: LightTint.lerp(
          _barraDaNoite, barra.tint, 0.10 + 0.22 * barra.exposure),
      land: LightTint.lerp(_luar, land, 0.10),
      clouds: LightTint.lerp(_luar, clouds, 0.14),
      sun: 0,
      stars: 1,
    );
  }
}

// ---------------------------------------------------------------------------
// As bolhas
// ---------------------------------------------------------------------------

/// Uma bolha num instante.
class Bubble {
  const Bubble({
    required this.index,
    required this.age,
    required this.x,
    required this.y,
    required this.radius,
    required this.squash,
    required this.opacity,
  });

  /// Qual bolha é — a mesma do nascimento ao fim, para quem desenha manter o
  /// brilho e a cor dela iguais de um quadro ao outro.
  final int index;

  /// Segundos desde que começou a inflar.
  final double age;

  /// Centro e raio, em pixels da arte.
  final double x;
  final double y;
  final double radius;

  /// Quanto a bolha está achatada: os raios são `radius × (1 ± squash)`. É a
  /// tremida de quando ela se solta do cachimbo, que se apaga em dois segundos.
  final double squash;

  final double opacity;
}

/// As bolhas do cachimbo.
///
/// Cada uma tem a vida inteira decidida pelo próprio número: quando nasce, a
/// que tamanho chega, com que pressa sobe, para que lado deriva. Nada é
/// guardado de um quadro para o outro, então nenhuma bolha pode aparecer do
/// nada, duplicar ou sumir no meio do caminho — só existe o que a conta diz.
abstract final class HeroBubbles {
  /// Intervalo médio entre uma bolha e a próxima.
  static const double interval = 1.3;

  /// Tempo inflando, presa à boca do cachimbo.
  static const double inflate = 1.25;

  /// Teto de vida, para quem enumera saber onde parar de procurar.
  static const double maxLife = 16;

  /// A faixa do topo em que a bolha se desfaz, em vez de ser cortada pela
  /// borda da ilustração.
  static const double fadeBand = 54;

  static double _birth(int n) => (n + 0.7 * _hash(n, 11)) * interval;

  /// A bolha [n] no instante [seconds], ou nula se ainda não nasceu ou já
  /// saiu do quadro.
  static Bubble? bubble(int n, double seconds) {
    final age = seconds - _birth(n);
    if (age < 0 || age > maxLife) return null;

    final rMax = 13 + 27 * math.pow(_hash(n, 3), 1.35);
    final rise = 27 + 11 * _hash(n, 5);
    final drift = 0.45 + 0.85 * _hash(n, 7);
    final sway = 3 + 4 * _hash(n, 9);
    final periodo = 3.2 + 2.4 * _hash(n, 13);
    final fase = 2 * math.pi * _hash(n, 15);

    // Solta, a bolha não parte com a velocidade cheia: ela desprende e só
    // então pega a subida. A integral dessa rampa é o `up` abaixo.
    final solta = math.max(0.0, age - inflate);
    const tau = 0.7;
    final up = rise * (solta - tau * (1 - math.exp(-solta / tau)));

    final cresceu = age < inflate
        ? 0.55 * _smooth(age / inflate)
        : 0.55 + 0.45 * _smooth(solta / 8);
    final r = rMax * cresceu;

    final balanco = sway *
        _smooth(solta / 2.5) *
        (math.sin(2 * math.pi * solta / periodo + fase) - math.sin(fase));

    final x = HeroArtboard.pipeX + up * drift + balanco;
    final y = HeroArtboard.pipeY - r - up;
    if (y + r <= 0) return null;

    // Ao desprender, a película oscila: larga, alta, larga, cada vez menos.
    // Seno, e não cosseno: no instante em que solta ela ainda é redonda.
    final tremida =
        0.11 * math.exp(-solta / 1.1) * math.sin(2 * math.pi * solta / 0.62);

    final nasce = _smooth(age / 0.4);
    // Começa a se desfazer com o alto da bolha a uma faixa da borda, e some
    // com ela inteira lá dentro: bolha grande cortada ao meio pela moldura
    // da tela é o defeito que isto evita.
    final some = _smooth((y + r) / (fadeBand + 2 * r));
    return Bubble(
      index: n,
      age: age,
      x: x,
      y: y,
      radius: r,
      squash: tremida,
      opacity: nasce * some,
    );
  }

  /// Todas as bolhas vivas em [seconds], da mais velha para a mais nova.
  static List<Bubble> at(double seconds) {
    final ultimo = (seconds / interval).floor() + 1;
    final primeiro = ((seconds - maxLife) / interval).floor() - 1;
    return [
      for (var n = primeiro; n <= ultimo; n++) ?bubble(n, seconds),
    ];
  }
}

// ---------------------------------------------------------------------------
// A respiração
// ---------------------------------------------------------------------------

/// Um lugar do corpo que sobe e desce com o ar.
class BreathBump {
  const BreathBump({
    required this.x,
    required this.y,
    required this.rx,
    required this.ry,
    required this.dx,
    required this.dy,
    required this.lag,
  });

  /// Centro e raios da região, em pixels da arte.
  final double x;
  final double y;
  final double rx;
  final double ry;

  /// O deslocamento no centro, com o pulmão cheio menos com ele vazio.
  final double dx;
  final double dy;

  /// Atraso em relação ao peito, em segundos: a barriga vem depois.
  final double lag;

  /// 1 no centro, 0 na borda e fora dela, com derivada zero na borda — é o
  /// que impede uma dobra na pintura onde o movimento acaba.
  double weight(double px, double py) {
    final u = (px - x) / rx, v = (py - y) / ry;
    final d2 = u * u + v * v;
    if (d2 >= 1) return 0;
    final k = 1 - d2;
    return k * k;
  }
}

/// O viajante respira.
///
/// Ele é uma pintura numa peça só: não há braço para mexer nem cabeça para
/// virar. O que dá para fazer com uma pintura, sem trair a pintura, é o que um
/// corpo parado faz de verdade — encher e esvaziar. O peito sobe pouco mais de
/// dois pixels, o livro que repousa na barriga sobe atrás dele, a cabeça quase
/// nada. A deformação é tão larga e tão rasa (menos de 2% em qualquer ponto)
/// que nenhuma linha do desenho chega a entortar.
///
/// O cachimbo fica de fora de propósito: é dele que as bolhas nascem, e a boca
/// do fornilho não pode sair do lugar.
abstract final class HeroBreath {
  /// Uma respiração de quem cochila.
  static const double period = 4.6;

  /// Que fração do ciclo é inspirar. Menos da metade: o ar entra mais depressa
  /// do que sai.
  static const double inhale = 0.42;

  static const bumps = [
    // o peito
    BreathBump(x: 335, y: 455, rx: 150, ry: 120, dx: 0.6, dy: -2.5, lag: 0),
    // a barriga, com o livro e as mãos
    BreathBump(x: 470, y: 540, rx: 150, ry: 110, dx: 0.4, dy: -1.7, lag: 0.28),
    // a cabeça
    BreathBump(x: 250, y: 288, rx: 108, ry: 104, dx: 0.1, dy: -0.8, lag: 0.12),
  ];

  /// 0 com o pulmão vazio, 1 com ele cheio.
  static double level(double seconds) {
    final t = _wrap(seconds / period);
    final meio = t < inhale
        ? 0.5 * t / inhale
        : 0.5 + 0.5 * (t - inhale) / (1 - inhale);
    return 0.5 - 0.5 * math.cos(2 * math.pi * meio);
  }

  /// Para onde vai o ponto ([x], [y]) da arte no instante [seconds]. O
  /// deslocamento é medido a partir do meio da respiração: a pintura como foi
  /// pintada é o corpo a meio fôlego.
  static (double, double) shift(double x, double y, double seconds) {
    var dx = 0.0, dy = 0.0;
    for (final b in bumps) {
      final w = b.weight(x, y);
      if (w == 0) continue;
      final a = w * (level(seconds - b.lag) - 0.5);
      dx += a * b.dx;
      dy += a * b.dy;
    }
    return (dx, dy);
  }
}
