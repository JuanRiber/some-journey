import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../design/sj_theme.dart';
import '../../design/tokens.dart';
import 'light_domain.dart';
import 'scene_domain.dart';

/// # O herói: o vagão, a janela e a viagem.
///
/// **Por que existe:** a ilustração do vagão era uma foto de uma viagem; isto
/// é a viagem. A paisagem passa por trás do vidro, o trem entra no túnel, a
/// luz do vagão responde, o viajante respira e o cachimbo solta bolhas de
/// sabão.
///
/// **É tudo a mesma pintura.** Duas imagens, as duas tiradas da ilustração de
/// marca: o interior do vagão, com o vidro recortado no alfa, e o atlas da
/// paisagem — serra, vale, prado e nuvens em tiras, para cada plano passar à
/// sua velocidade. O que é desenhado aqui é só o que não existe na pintura:
/// postes, o corte e o túnel, o sol, a lua, e as bolhas.
///
/// **Como é montado:** de trás para a frente, num único `CustomPaint` e num
/// único relógio —
///
/// 1. o céu (degradê nas cores medidas na pintura, com o grão da tinta por
///    cima) e as nuvens;
/// 2. a serra, o vale e os dois planos de prado, cada tira banhada pela luz do
///    momento;
/// 3. o que corre rente ao trem: postes, o corte na rocha, o túnel;
/// 4. o vidro (reflexo e a sombra da moldura);
/// 5. o interior, banhado pela trilha de luz e desenhado numa malha que sobe e
///    desce com a respiração;
/// 6. o abajur — o interior de novo, sem o banho, numa poça em volta dele: é o
///    que continua aceso quando o resto apaga — e a luz que entra pela janela;
/// 7. as bolhas.
///
/// Onde está cada tira, cada bolha e o peito do viajante vêm de
/// `scene_domain.dart`; quanta luz entra, de `light_domain.dart`. Aqui só se
/// desenha.
class HeroScene extends StatefulWidget {
  const HeroScene({super.key, this.phase, this.semanticLabel});

  /// Fase fixa da viagem (0..1). Com ela a cena não anda sozinha — é como a
  /// galeria a percorre à mão. Nula, a cena corre no próprio relógio.
  final double? phase;

  /// Como a cena se apresenta a um leitor de tela. Nula, ela é decorativa.
  final String? semanticLabel;

  /// O interior do vagão e o atlas da paisagem.
  static const String asset = 'assets/images/first-class-interior.webp';
  static const String landscape = 'assets/images/first-class-landscape.webp';

  /// Desligado, a cena fica num quadro só. Existe para os testes: um relógio
  /// que nunca para faz todo `pumpAndSettle` do app esperar para sempre, e a
  /// tela de login está embaixo de metade deles.
  @visibleForTesting
  static bool autoplay = true;

  /// O quadro de quem pediu menos movimento ao sistema: o campo aberto, que é
  /// a composição da ilustração original.
  static const double stillPhase = 0.955;

  @override
  State<HeroScene> createState() => _HeroSceneState();
}

/// Uma das duas imagens da cena, do pedido à chegada.
class _Arte {
  _Arte(this.asset, this.aoChegar);

  final String asset;
  final VoidCallback aoChegar;

  ImageStream? _fluxo;
  ImageInfo? _info;

  ui.Image? get imagem => _info?.image;

  late final _ouvinte = ImageStreamListener(
    (info, _) {
      _info?.dispose();
      _info = info;
      aoChegar();
    },
    // Sem a arte não há cena: fica o fundo da tela, que é o que havia antes de
    // a imagem carregar. Nada a dizer ao usuário numa tela de login.
    onError: (_, _) {},
  );

  void resolver(BuildContext context) {
    final fluxo =
        AssetImage(asset).resolve(createLocalImageConfiguration(context));
    if (fluxo.key == _fluxo?.key) return;
    _fluxo?.removeListener(_ouvinte);
    _fluxo = fluxo..addListener(_ouvinte);
  }

  void dispose() {
    _fluxo?.removeListener(_ouvinte);
    _info?.dispose();
  }
}

class _HeroSceneState extends State<HeroScene>
    with SingleTickerProviderStateMixin {
  /// Onde a viagem começa: no campo aberto, que é a ilustração como todo mundo
  /// a conhece. O túnel fica a meio minuto dali.
  static const double _partida = HeroScene.stillPhase * HeroTravel.loopSeconds;

  final _relogio = ValueNotifier<double>(_partida);
  late final Ticker _ticker = createTicker(
    (decorrido) =>
        _relogio.value = _partida + decorrido.inMicroseconds / 1e6,
  );

  late final _interior = _Arte(HeroScene.asset, _chegou);
  late final _paisagem = _Arte(HeroScene.landscape, _chegou);

  /// O interior como textura: é o que a malha da respiração estica.
  ui.ImageShader? _pele;
  ui.Image? _peleDe;

  void _chegou() {
    if (!mounted) return;
    setState(() {
      final arte = _interior.imagem;
      if (arte == _peleDe) return;
      _pele?.dispose();
      _peleDe = arte;
      _pele = arte == null
          ? null
          : ui.ImageShader(
              arte,
              TileMode.clamp,
              TileMode.clamp,
              // A malha é medida em pixels da ARTE; se a imagem vier noutro
              // tamanho, é esta matriz que a traz para a mesma régua.
              Matrix4.diagonal3Values(
                HeroArtboard.width / arte.width,
                HeroArtboard.height / arte.height,
                1,
              ).storage,
              filterQuality: FilterQuality.medium,
            );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _interior.resolver(context);
    _paisagem.resolver(context);
    _acertarRelogio();
  }

  @override
  void didUpdateWidget(HeroScene antigo) {
    super.didUpdateWidget(antigo);
    _acertarRelogio();
  }

  /// A cena anda sozinha só se ninguém a está conduzindo e ninguém pediu
  /// menos movimento.
  void _acertarRelogio() {
    final anda = widget.phase == null &&
        HeroScene.autoplay &&
        !MediaQuery.disableAnimationsOf(context);
    if (anda && !_ticker.isActive) {
      _ticker.start();
    } else if (!anda) {
      if (_ticker.isActive) _ticker.stop();
      _relogio.value =
          (widget.phase ?? HeroScene.stillPhase) * HeroTravel.loopSeconds;
    }
  }

  @override
  void dispose() {
    _interior.dispose();
    _paisagem.dispose();
    _pele?.dispose();
    _ticker.dispose();
    _relogio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final noite = SJTheme.of(context).brightness == Brightness.dark;
    final pronta = _pele != null && _paisagem.imagem != null;
    final cena = RepaintBoundary(
      child: AnimatedOpacity(
        // A cena entra de uma vez, já inteira — paisagem sem vagão em volta
        // seria um quadro errado, por mais curto que fosse.
        opacity: pronta ? 1 : 0,
        duration: SJMotion.slow,
        curve: SJMotion.standard,
        child: CustomPaint(
          size: Size.infinite,
          painter: _ScenePainter(
            relogio: _relogio,
            pele: _pele,
            paisagem: _paisagem.imagem,
            noite: noite,
          ),
        ),
      ),
    );
    final rotulo = widget.semanticLabel;
    if (rotulo == null) return ExcludeSemantics(child: cena);
    return Semantics(image: true, label: rotulo, child: cena);
  }
}

// ---------------------------------------------------------------------------
// A malha do interior
// ---------------------------------------------------------------------------

/// O interior é desenhado numa grade de triângulos, e não num retângulo só,
/// para o peito do viajante poder subir sem o resto do vagão ir junto. A grade
/// é fina o bastante para a deformação ser lisa e grossa o bastante para
/// refazer todos os vértices a cada quadro não custar nada.
const double _passo = 24;
final int _colunas = (HeroArtboard.width / _passo).ceil() + 1;
final int _linhas = (HeroArtboard.height / _passo).ceil() + 1;

/// Os vértices em repouso — que são também as coordenadas de textura.
final Float32List _repouso = () {
  final r = Float32List(_colunas * _linhas * 2);
  for (var j = 0; j < _linhas; j++) {
    for (var i = 0; i < _colunas; i++) {
      final k = (j * _colunas + i) * 2;
      r[k] = math.min(i * _passo, HeroArtboard.width);
      r[k + 1] = math.min(j * _passo, HeroArtboard.height);
    }
  }
  return r;
}();

final Uint16List _triangulos = () {
  final t = Uint16List((_colunas - 1) * (_linhas - 1) * 6);
  var k = 0;
  for (var j = 0; j < _linhas - 1; j++) {
    for (var i = 0; i < _colunas - 1; i++) {
      final a = j * _colunas + i, b = a + 1, c = a + _colunas, d = c + 1;
      t[k++] = a;
      t[k++] = b;
      t[k++] = c;
      t[k++] = b;
      t[k++] = d;
      t[k++] = c;
    }
  }
  return t;
}();

/// Os vértices que alguma região da respiração alcança. Os outros nunca saem
/// do lugar, e não vale refazer a conta para eles a cada quadro.
final List<int> _vivos = [
  for (var v = 0; v < _repouso.length ~/ 2; v++)
    if (HeroBreath.bumps
        .any((b) => b.weight(_repouso[v * 2], _repouso[v * 2 + 1]) > 0))
      v,
];

final Float32List _posicoes = Float32List.fromList(_repouso);

ui.Vertices _malha(double segundos) {
  for (final v in _vivos) {
    final x = _repouso[v * 2], y = _repouso[v * 2 + 1];
    final (dx, dy) = HeroBreath.shift(x, y, segundos);
    _posicoes[v * 2] = x + dx;
    _posicoes[v * 2 + 1] = y + dy;
  }
  return ui.Vertices.raw(
    ui.VertexMode.triangles,
    _posicoes,
    textureCoordinates: _repouso,
    indices: _triangulos,
  );
}

// ---------------------------------------------------------------------------
// O desenho
// ---------------------------------------------------------------------------

const _g = HeroArtboard.glassLeft;
const _gw = HeroArtboard.glassWidth;
const _gh = HeroArtboard.glassHeight;
const _direita = HeroArtboard.glassRight;
const _fundo = HeroArtboard.glassBottom;
const _horizonte = HeroArtboard.horizon;
const _vidro = Rect.fromLTRB(_g, 0, _direita, _fundo);

// Pincéis de forma fixa. São criados uma vez, em torno da origem e com raio
// 1; quem desenha leva a tela até o lugar e a escala até o tamanho. A cena
// repinta sessenta vezes por segundo: criar um degradê por bolha por quadro
// era lixo de memória sem ganho nenhum de desenho.
const _unidade = Rect.fromLTRB(-1, -1, 1, 1);

/// Um clarão branco que se apaga para fora — a cor vem de quem o usa.
final ui.Shader _halo = const RadialGradient(
  colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
).createShader(_unidade);

/// O mesmo, com miolo: forte no centro, um resto até a borda.
final ui.Shader _haloComMiolo = const RadialGradient(
  colors: [Color(0xFFFFFFFF), Color(0x55FFFFFF), Color(0x00FFFFFF)],
  stops: [0, 0.36, 1],
).createShader(_unidade);

final ui.Shader _bolhaCorpo = const RadialGradient(
  center: Alignment(-0.25, -0.3),
  colors: [Color(0x08FFFFFF), Color(0x14FFFFFF), Color(0x4DEBF7FF)],
  stops: [0, 0.72, 1],
).createShader(_unidade);

const _iris = [
  Color(0xD1FFB3D1), Color(0xD1B9E6FF), Color(0xD1FFF2B0),
  Color(0xD1C9B8FF), Color(0xD1B6F5D8), Color(0xD1FFB3D1),
];

final ui.Shader _bolhaIris =
    const SweepGradient(colors: _iris).createShader(_unidade);

final ui.Shader _bolhaIrisDeDentro = SweepGradient(
  colors: [for (final c in _iris.reversed) c.withValues(alpha: 0.30)],
).createShader(_unidade);

/// A sombra que a moldura faz no que está logo atrás dela, por cima e pelo
/// lado, e o escuro que dá volume à rocha do corte.
final ui.Shader _sombraDeCima = const LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0x38100A06), Color(0x00100A06)],
  stops: [0, 0.14],
).createShader(_vidro);

final ui.Shader _sombraDoLado = const LinearGradient(
  colors: [Color(0x30100A06), Color(0x00100A06)],
  stops: [0, 0.06],
).createShader(_vidro);

final ui.Shader _escuroDaRocha = const LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0x00000000), Color(0x73000000)],
).createShader(_vidro);

const _pocaDoAbajur = Offset(HeroArtboard.lampX + 40, HeroArtboard.lampY + 70);
final ui.Shader _mascaraDoAbajur = const RadialGradient(
  colors: [Color(0xFFFFFFFF), Color(0xB0FFFFFF), Color(0x00FFFFFF)],
  stops: [0, 0.34, 1],
).createShader(Rect.fromCircle(center: _pocaDoAbajur, radius: 380));

Color _rgb(LightTint t, [double a = 1]) => Color.from(
      alpha: a,
      red: (t.r / 255).clamp(0.0, 1.0),
      green: (t.g / 255).clamp(0.0, 1.0),
      blue: (t.b / 255).clamp(0.0, 1.0),
    );

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.relogio,
    required this.pele,
    required this.paisagem,
    required this.noite,
  }) : super(repaint: relogio);

  final ValueListenable<double> relogio;
  final ui.ImageShader? pele;
  final ui.Image? paisagem;
  final bool noite;

  // Estado do quadro corrente — preenchido no começo de `paint`.
  late double _fase;
  late SkySample _ceu;
  late LightSample _luz;

  /// Quanto da luz de fora sobra lá fora (cai no corte e no túnel).
  late double _ganho;

  /// A mesma coisa, de 0 a 1: zero no breu do túnel, um em campo aberto.
  late double _fora;

  /// A cor de uma coisa DESENHADA lá fora (poste, pedra da boca do túnel) sob
  /// a luz do momento. As tiras pintadas recebem a mesma luz por [_banho].
  Color _cor(Color base) {
    final k = _ganho / 255;
    return Color.from(
      alpha: base.a,
      red: base.r * _ceu.land.r * k,
      green: base.g * _ceu.land.g * k,
      blue: base.b * _ceu.land.b * k,
    );
  }

  /// O banho de luz de uma tira pintada: a cor da pintura multiplicada pela
  /// luz do momento e, conforme a distância, dissolvida na barra do céu.
  ///
  /// A linha do alfa é a identidade, como na matriz do interior: é ela que
  /// mantém o céu aparecendo por cima da serra.
  ColorFilter _banho(LightTint luz, [double nevoa = 0]) {
    final k = _ganho * (1 - nevoa) / 255;
    final n = _ganho * nevoa;
    return ColorFilter.matrix(<double>[
      luz.r * k, 0, 0, 0, _ceu.horizon.r * n, //
      0, luz.g * k, 0, 0, _ceu.horizon.g * n, //
      0, 0, luz.b * k, 0, _ceu.horizon.b * n, //
      0, 0, 0, 1, 0,
    ]);
  }

  double _x(StripLayer camada, double v) => _g + camada.screenOf(_fase, v) * _gw;

  /// Um clarão da cor [cor], centrado em [centro], com os raios dados.
  void _clarao(
    Canvas canvas,
    Offset centro,
    double raioX,
    double raioY,
    Color cor, {
    bool comMiolo = false,
    BlendMode modo = BlendMode.srcOver,
  }) {
    canvas.save();
    canvas.translate(centro.dx, centro.dy);
    canvas.scale(raioX, raioY);
    canvas.drawRect(
        _unidade,
        Paint()
          ..shader = comMiolo ? _haloComMiolo : _halo
          ..colorFilter = ColorFilter.mode(cor, BlendMode.modulate)
          ..blendMode = modo);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final atlas = paisagem, interior = pele;
    if (atlas == null || interior == null) return;

    final segundos = relogio.value;
    _fase = HeroTravel.phaseAt(segundos);
    final c = HeroTravel.center(_fase);
    _luz = (noite ? LightTrack.scenic.toNight() : LightTrack.scenic).at(c);
    _ceu = HeroSky.at(c, night: noite);
    _ganho = HeroTravel.outsideGain(_luz);
    _fora = ((_ganho - 0.30) / 0.70).clamp(0.0, 1.0);

    // A arte cobre a caixa inteira, como o `BoxFit.cover` da foto que havia.
    final k = math.max(size.width / HeroArtboard.width, size.height / HeroArtboard.height);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate((size.width - HeroArtboard.width * k) / 2,
        (size.height - HeroArtboard.height * k) / 2);
    canvas.scale(k);

    canvas.save();
    canvas.clipRect(_vidro);
    _pintarCeu(canvas, atlas);
    _tira(canvas, atlas, HeroAtlas.far, HeroTravel.far, HeroAtlas.farTop,
        _banho(_ceu.land, 0.07));
    _tira(canvas, atlas, HeroAtlas.valley, HeroTravel.valley,
        HeroAtlas.valleyTop, _banho(_ceu.land, 0.02));
    _pintarVila(canvas);
    _tira(canvas, atlas, HeroAtlas.meadowBack, HeroTravel.meadowBack,
        HeroAtlas.meadowBackTop, _banho(_ceu.land));
    _tira(canvas, atlas, HeroAtlas.meadow, HeroTravel.meadow,
        HeroAtlas.meadowTop, _banho(_ceu.land));
    _pintarTrilho(canvas, atlas);
    _pintarVidro(canvas);
    canvas.restore();

    final malha = _malha(segundos);
    canvas.drawVertices(
      malha,
      BlendMode.srcOver,
      Paint()
        ..shader = interior
        ..colorFilter = ColorFilter.matrix(_luz.colorMatrix),
    );
    _pintarAbajur(canvas, malha, interior);
    malha.dispose();
    _pintarLuzDaJanela(canvas);
    _pintarBolhas(canvas, segundos);
    canvas.restore();
  }

  /// Uma tira do atlas, rolada até onde a camada está.
  ///
  /// A tira é cíclica: quando a janela passa do fim dela, o resto vem do
  /// começo. Sem suavização de borda nos pedaços — duas bordas suavizadas lado
  /// a lado deixam passar um fio do que está atrás, exatamente na emenda.
  void _tira(Canvas canvas, ui.Image atlas, AtlasRect peca, StripLayer camada,
      double topo, ColorFilter banho) {
    final tinta = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.low
      ..colorFilter = banho;
    var px = camada.pixelAt(_fase);
    var feito = 0.0;
    while (feito < _gw) {
      final largura = math.min(peca.width - px, _gw - feito);
      canvas.drawImageRect(
        atlas,
        Rect.fromLTWH(peca.x + px, peca.y, largura, peca.height),
        Rect.fromLTWH(_g + feito, topo, largura, peca.height),
        tinta,
      );
      feito += largura;
      px = 0;
    }
  }

  // --- 1. Céu ---------------------------------------------------------------

  void _pintarCeu(Canvas canvas, ui.Image atlas) {
    // O grão vai multiplicado por cima e escurece o céu um pouco; as cores já
    // sobem na mesma proporção.
    final k = _ganho / HeroAtlas.canvasMean;
    LightTint acender(LightTint t) => LightTint(t.r * k, t.g * k, t.b * k);
    canvas.drawRect(
      _vidro,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_rgb(acender(_ceu.top)), _rgb(acender(_ceu.horizon))],
        ).createShader(const Rect.fromLTRB(_g, 0, _direita, _horizonte)),
    );
    // O grão da tinta: sem ele o céu é um degradê liso ao lado de uma pintura.
    final grao = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.low
      ..blendMode = BlendMode.modulate;
    const peca = HeroAtlas.canvas;
    final origem = Rect.fromLTWH(peca.x, peca.y, peca.width, peca.height);
    for (var y = 0.0; y < _horizonte + 80; y += peca.height) {
      for (var x = _g; x < _direita; x += peca.width) {
        canvas.drawImageRect(atlas, origem,
            Rect.fromLTWH(x, y, peca.width, peca.height), grao);
      }
    }

    if (_ceu.stars > 0) {
      final tinta = Paint();
      for (var i = 0; i < 80; i++) {
        final x = _g + _gw * _fixo(i, 1);
        final y = (_horizonte - 40) * math.pow(_fixo(i, 2), 1.4);
        tinta.color = Color.from(
            alpha: _ceu.stars * _ganho * (0.35 + 0.6 * _fixo(i, 3)),
            red: 1, green: 0.97, blue: 0.88);
        canvas.drawCircle(Offset(x, y), 0.7 + 1.1 * _fixo(i, 4), tinta);
      }
      // A lua, parada: o que está longe não anda.
      const lua = Offset(_g + _gw * 0.30, 96);
      _clarao(canvas, lua, 80, 80,
          Color.from(alpha: 0.22 * _ganho, red: 0.8, green: 0.86, blue: 1));
      canvas.drawCircle(
          lua,
          19,
          Paint()
            ..color = Color.from(alpha: _ganho, red: 0.96, green: 0.94, blue: 0.86));
    }

    if (_ceu.sun > 0.01) {
      // Pousado no horizonte na saída do túnel; sobe e sai pelo alto da janela
      // conforme o dia abre.
      final s = _ceu.sun;
      final sol = Offset(_g + _gw * 0.30, _horizonte - 62 - (1 - s) * 460);
      final brilho = s * _ganho;
      _clarao(canvas, sol, 300, 300,
          Color.from(alpha: 0.62 * brilho, red: 1, green: 0.84, blue: 0.54),
          comMiolo: true);
      // O disco só existe baixo: subindo, dissolve no clarão — um disco pálido
      // no alto de um céu de dia seria uma lua fora de hora.
      canvas.drawCircle(
          sol,
          27,
          Paint()
            ..color = Color.from(
                alpha: math.min(1.0, brilho * 1.25) * _smooth((s - 0.55) / 0.3),
                red: 1, green: 0.96, blue: 0.82));
    }

    _tira(canvas, atlas, HeroAtlas.clouds, HeroTravel.clouds,
        HeroAtlas.cloudsTop, _banho(_ceu.clouds));
  }

  // --- 2. A vila ------------------------------------------------------------

  /// As janelas da vila do vale. De dia não há nada ali além de campo; quando
  /// a luz cai, acendem — e é isso que diz que mora gente naquele vale.
  void _pintarVila(Canvas canvas) {
    final acesa = _smooth(math.max(_ceu.sun, _ceu.stars) * 1.5 - 0.3) * _fora;
    if (acesa < 0.02) return;
    const tira = HeroTravel.valley;
    final x0 = tira.pixelAt(_fase);
    final miolo = Paint();
    for (final ancora in HeroAtlas.villages) {
      var dx = (ancora - x0) % tira.tile;
      if (dx > tira.tile - 60) dx -= tira.tile; // já saindo pela esquerda
      if (dx > _gw + 60) continue;
      for (final luz in HeroScenery.village) {
        final centro =
            Offset(_g + dx + luz.v, HeroAtlas.villageRow + luz.depth);
        final r = 1.25 * luz.size;
        _clarao(canvas, centro, r * 5, r * 5,
            Color.from(alpha: 0.50 * acesa, red: 1, green: 0.80, blue: 0.46));
        miolo.color =
            Color.from(alpha: acesa, red: 1, green: 0.90, blue: 0.62);
        canvas.drawCircle(centro, r, miolo);
      }
    }
  }

  // --- 3. Rente ao trem -----------------------------------------------------

  void _pintarTrilho(Canvas canvas, ui.Image atlas) {
    const camada = HeroTravel.track;

    // Postes e fios.
    const cruzeta = 138.0;
    const n = HeroScenery.poleCount;
    final madeira = Paint()..color = _cor(const Color(0xFF33261E));
    // O lado do poste que pega o sol: um filete, como o traço de luz que a
    // pintura põe em tudo que é madeira.
    final veio = Paint()..color = _cor(const Color(0xFF7A5F47));
    final fio = Paint()
      ..color = _cor(const Color(0xFF2B2420)).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final passo = _gw * camada.span / HeroTravel.aperture / n;
    for (final p in HeroScenery.poles) {
      final x = _x(camada, p.v);
      if (x < _g - passo - 20 || x > _direita + 20) continue;
      canvas.drawRect(Rect.fromLTRB(x - 5, cruzeta - 26, x + 5, _fundo), madeira);
      canvas.drawRect(Rect.fromLTRB(x - 5, cruzeta - 26, x - 2.4, _fundo), veio);
      canvas.drawRect(Rect.fromLTRB(x - 34, cruzeta - 4, x + 34, cruzeta + 4), madeira);
      canvas.drawRect(Rect.fromLTRB(x - 34, cruzeta - 4, x + 34, cruzeta - 2.2), veio);
      for (final dx in [-28.0, 28.0]) {
        canvas.drawRect(
            Rect.fromLTRB(x + dx - 2.5, cruzeta - 11, x + dx + 2.5, cruzeta - 4),
            madeira);
      }
      // O fio até o próximo poste, se houver um (não há dentro do corte).
      if (Terrain.cutting((p.seed + 1.5) / n) > 0) continue;
      for (final dx in [-28.0, 28.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(x + dx, cruzeta - 6)
            ..quadraticBezierTo(x + dx + passo / 2, cruzeta + 44, x + dx + passo, cruzeta - 6),
          fio,
        );
      }
    }

    // O corte na rocha, que sobe até a boca do túnel.
    final a = _x(camada, HeroTravel.tunnelFrom);
    final b = _x(camada, HeroTravel.tunnelTo);
    final ca = _x(camada, HeroTravel.cuttingFrom);
    final cb = _x(camada, HeroTravel.cuttingTo);
    if (cb < _g || ca > _direita) return;

    // Os pontos do contorno ficam presos à CAMADA, não à tela: se fossem
    // amostras de tela, a aresta da rocha ferveria a cada quadro.
    const porCiclo = 3000;
    final v0 = camada.at(_fase, 0);
    final pontos = [
      for (var i = (v0 * porCiclo).floor() - 1;
          i <= ((v0 + camada.visible) * porCiclo).ceil() + 1;
          i++)
        (i / porCiclo, _g + (i / porCiclo - v0) / camada.visible * _gw),
    ];
    final corte = Path()..moveTo(pontos.first.$2, _fundo);
    for (final (v, x) in pontos) {
      corte.lineTo(x, _fundo - math.min(Terrain.cutting(v), 1.1) * _gh);
    }
    corte
      ..lineTo(pontos.last.$2, _fundo)
      ..close();

    // A pedra é a da serra da pintura, em ladrilho, correndo com a camada.
    canvas.save();
    canvas.clipPath(corte);
    const pedra = HeroAtlas.rock;
    final escala = _gh / pedra.height;
    final largura = pedra.width * escala;
    final banho = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.low
      // Mais escura que a serra: é rocha a dois palmos do vidro, na sombra.
      ..colorFilter = _banho(
          LightTint(_ceu.land.r * 0.78, _ceu.land.g * 0.74, _ceu.land.b * 0.72));
    final origem = Rect.fromLTWH(pedra.x, pedra.y, pedra.width, pedra.height);
    for (var x = _g - camada.pixelAt(_fase) % largura; x < _direita; x += largura) {
      canvas.drawImageRect(
          atlas, origem, Rect.fromLTWH(x, 0, largura, _gh), banho);
    }
    canvas.drawRect(_vidro, Paint()..shader = _escuroDaRocha);
    canvas.restore();

    // A relva na borda de cima do corte.
    final relva = Path();
    var aberto = false;
    for (final (v, x) in pontos) {
      final alto = Terrain.cutting(v);
      if (alto <= 0 || alto > 1.1) {
        aberto = false;
        continue;
      }
      final y = _fundo - alto * _gh;
      aberto ? relva.lineTo(x, y) : relva.moveTo(x, y);
      aberto = true;
    }
    canvas.drawPath(
        relva,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeJoin = StrokeJoin.round
          ..color = _cor(const Color(0xFF4F7044)));

    // O túnel: breu, com a cantaria da boca de cada lado.
    if (b < _g || a > _direita) return;
    canvas.drawRect(Rect.fromLTRB(a, 0, b, _fundo), Paint()..color = const Color(0xFF09080B));
    final cantaria = Paint()..color = _cor(const Color(0xFFC9BEAC));
    final junta = Paint()
      ..color = _cor(const Color(0xFF3A3431))
      ..strokeWidth = 1.5;
    for (final (x0, x1) in [(a - 34, a), (b, b + 34)]) {
      canvas.drawRect(Rect.fromLTRB(x0, 0, x1, _fundo), cantaria);
      for (var y = 22.0; y < _fundo; y += 44) {
        canvas.drawLine(Offset(x0, y), Offset(x1, y), junta);
      }
    }
    // Lá dentro: um cabo na parede e as lâmpadas, que passam.
    canvas.drawLine(Offset(a, 176), Offset(b, 176),
        Paint()..color = const Color(0xFF1C1A1E)..strokeWidth = 3);
    for (final l in HeroScenery.lamps) {
      final x = _x(camada, l.v);
      if (x < _g - 160 || x > _direita + 160) continue;
      final centro = Offset(x, 150);
      _clarao(canvas, centro, 160, 80, const Color(0x70FFC070), comMiolo: true);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: centro, width: 26, height: 9),
              const Radius.circular(5)),
          Paint()..color = const Color(0xFFFFE2A8));
    }
  }

  // --- 4. Vidro -------------------------------------------------------------

  void _pintarVidro(Canvas canvas) {
    // A moldura faz sombra no que está logo atrás dela.
    canvas.drawRect(_vidro, Paint()..shader = _sombraDeCima);
    canvas.drawRect(_vidro, Paint()..shader = _sombraDoLado);
    // Dois reflexos em diagonal — é o que diz que há um vidro ali. De dia; no
    // escuro quase somem, ou viram dois fachos de luz no breu.
    final reflexo = Paint()
      ..color = Color.from(
          alpha: 0.010 + 0.034 * _ganho * (noite ? 0.5 : 1),
          red: 1, green: 1, blue: 1);
    for (final (x, l) in [(_g + 250.0, 90.0), (_g + 390.0, 34.0)]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + l, 0)
          ..lineTo(x + l - 230, _fundo)
          ..lineTo(x - 230, _fundo)
          ..close(),
        reflexo,
      );
    }
    // No escuro a janela vira espelho: o abajur aparece nela.
    final espelho = _luz.lamp * (1 - _ganho);
    if (espelho > 0.02) {
      _clarao(canvas, const Offset(_g + 150, 150), 240, 240,
          Color.from(alpha: 0.16 * espelho, red: 1, green: 0.80, blue: 0.52));
    }
  }

  // --- 6. Abajur e a luz da janela ------------------------------------------

  void _pintarAbajur(Canvas canvas, ui.Vertices malha, ui.ImageShader interior) {
    final aceso = _smooth((_luz.lamp - 0.15) / 0.7);
    if (aceso < 0.01) return;
    const caixa = Rect.fromLTWH(0, 0, HeroArtboard.width, HeroArtboard.height);
    final poca =
        Rect.fromCircle(center: _pocaDoAbajur, radius: 380).intersect(caixa);
    canvas.saveLayer(
        poca, Paint()..color = Color.from(alpha: aceso, red: 1, green: 1, blue: 1));
    canvas.clipRect(poca);
    canvas.drawVertices(
      malha,
      BlendMode.srcOver,
      Paint()
        ..shader = interior
        // A luz do abajur é quente; a cópia sai levemente âmbar.
        ..colorFilter = const ColorFilter.matrix(<double>[
          1.04, 0, 0, 0, 0, //
          0, 0.95, 0, 0, 0, //
          0, 0, 0.78, 0, 0, //
          0, 0, 0, 1, 0,
        ]),
    );
    canvas.drawRect(
        poca,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = _mascaraDoAbajur);
    canvas.restore();
    _clarao(
        canvas,
        const Offset(HeroArtboard.lampX, HeroArtboard.lampY),
        170,
        170,
        Color.from(alpha: 0.30 * aceso, red: 1, green: 0.84, blue: 0.58),
        modo: BlendMode.plus);
  }

  /// A luz que a janela joga para dentro.
  ///
  /// A trilha já banha o vagão inteiro; isto é o que vem DA janela: um clarão
  /// da cor do céu lá fora, mais forte perto do vidro. De dia é creme, no
  /// entardecer é âmbar, no túnel apaga — e em troca passa, de tempos em
  /// tempos, o clarão de cada lâmpada da parede.
  void _pintarLuzDaJanela(Canvas canvas) {
    canvas.save();
    canvas.clipRect(const Rect.fromLTRB(0, 0, _g + 6, HeroArtboard.height));
    final forca = _fora * (noite ? 0.35 : 1);
    if (forca > 0.02) {
      _clarao(canvas, const Offset(_g + 70, 310), 600, 600,
          _rgb(_ceu.horizon, 0.11 * forca),
          comMiolo: true, modo: BlendMode.plus);
    }
    final breu = HeroTravel.darkness(_fase);
    if (breu > 0.01) {
      for (final l in HeroScenery.lamps) {
        final x = _x(HeroTravel.track, l.v);
        if (x < _g - 120 || x > _direita + 200) continue;
        // O clarão cai à frente da lâmpada, junto do vidro, e é curto: luz
        // somada demais num vagão escuro deixa de ser clarão e vira neblina.
        _clarao(canvas, Offset(x - 330, 300), 230, 230,
            Color.from(alpha: 0.075 * breu, red: 1, green: 0.78, blue: 0.48),
            modo: BlendMode.plus);
      }
    }
    canvas.restore();
  }

  // --- 7. Bolhas ------------------------------------------------------------

  void _pintarBolhas(Canvas canvas, double segundos) {
    // Sabão não tem luz própria: no túnel a bolha só mostra o que o abajur
    // alcança.
    final claridade =
        (0.38 + 0.62 * math.min(1.0, _luz.exposure) + 0.2 * _luz.lamp)
            .clamp(0.0, 1.0);
    for (final b in HeroBubbles.at(segundos)) {
      final o = b.opacity * claridade;
      if (o < 0.01 || b.radius < 0.6) continue;
      final r = b.radius;
      // Desenhada em torno da origem com raio 1: a tela vai até a bolha, cresce
      // até o tamanho dela e achata com a tremida de quando solta. É o que
      // deixa os pincéis serem os mesmos para todas, em todos os quadros.
      canvas.save();
      canvas.translate(b.x, b.y);
      canvas.scale(r * (1 + b.squash), r * (1 - b.squash));
      final alfa = Color.from(alpha: o, red: 1, green: 1, blue: 1);

      canvas.drawCircle(
          Offset.zero,
          1,
          Paint()
            ..shader = _bolhaCorpo
            ..color = alfa);

      // A película: um arco-íris fino na borda, que gira devagar com a bolha.
      final traco = math.max(1.0, r * 0.09) / r;
      canvas.save();
      canvas.rotate(_fixo(b.index, 9) * 6.283 + b.age * 0.22);
      canvas.drawCircle(
          Offset.zero,
          1 - traco / 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = traco
            ..shader = _bolhaIris
            ..color = alfa);
      canvas.restore();
      canvas.save();
      canvas.rotate(_fixo(b.index, 10) * 6.283 - b.age * 0.15);
      canvas.drawCircle(
          Offset.zero,
          1 - traco * 2.1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = traco * 0.7
            ..shader = _bolhaIrisDeDentro
            ..color = alfa);
      canvas.restore();

      // Os brilhos: a janela refletida em cima, o rebatido embaixo, e o ponto
      // de luz do abajur.
      final brilho = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.0, r * 0.14) / r
        ..color = Color.from(alpha: 0.88 * o, red: 1, green: 1, blue: 0.96);
      canvas.drawArc(_unidade.deflate(0.27), math.pi * 1.12, 0.66, false, brilho);
      brilho
        ..strokeWidth = math.max(0.8, r * 0.08) / r
        ..color = Color.from(alpha: 0.42 * o, red: 1, green: 1, blue: 0.96);
      canvas.drawArc(_unidade.deflate(0.24), math.pi * 0.16, 0.42, false, brilho);
      canvas.drawCircle(
          const Offset(-0.42, -0.46),
          math.max(0.7, r * 0.07) / r,
          Paint()..color = Color.from(alpha: 0.9 * o, red: 1, green: 0.98, blue: 0.92));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.pele != pele ||
      old.paisagem != paisagem ||
      old.noite != noite ||
      old.relogio != relogio;
}

double _smooth(double t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  return t * t * (3 - 2 * t);
}

/// Variação fixa para o desenho (o brilho de uma estrela, o giro de uma bolha).
double _fixo(int n, int sal) {
  final x = math.sin(n * 12.9898 + sal * 78.233) * 43758.5453;
  return x - x.floorToDouble();
}
