/// # A base cartográfica do atlas.
///
/// **O problema que isto resolve.** O mapa usava as telhas Positron do CartoDB,
/// que passaram a exigir chave: o atlas — o centro do produto — ficou coberto de
/// marcas d'água "API KEY REQUIRED". E mesmo funcionando, uma base comercial
/// cinza-azulada brigava com o papel quente da interface: o mapa parecia colado
/// de outro aplicativo.
///
/// **A saída.** Telhas do OpenStreetMap (livres, sem chave) passadas por um
/// filtro de cor que as traz para a paleta do produto. O mapa deixa de ser um
/// widget de terceiro e vira parte do caderno: sépia sobre papel no modo claro,
/// tinta pálida sobre azul de meia-noite no escuro.
///
/// **Por que um filtro e não outra base pronta.** Nenhuma base gratuita nasce na
/// cor deste produto, e assinar uma só para isso seria caro e ainda assim
/// aproximado. O filtro é uma matriz — custo desprezível na GPU — e nos dá a
/// cor EXATA dos tokens, nos dois modos, de graça.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'components/type_styles.dart';
import 'tokens.dart';

class SJBasemap {
  const SJBasemap._();

  /// Telhas do OpenStreetMap. Sem chave, sem marca d'água.
  static const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// A política de uso do OSM EXIGE um agente identificável. Sem isto as telhas
  /// podem ser bloqueadas — o mesmo cuidado que o backend toma com o Nominatim.
  static const userAgent = 'app.somejourney';

  /// Atribuição obrigatória pela licença do OpenStreetMap. Faltava no mapa
  /// antigo, com CartoDB — era uma dívida, não uma escolha.
  static const attribution = '© OpenStreetMap';

  /// Pesos de luminância percebida (Rec. 709). Usados para achatar a telha em
  /// uma escala de cinza antes de recolori-la — é o que faz verde de parque e
  /// azul de rio virarem tons do MESMO papel, em vez de manchas coloridas.
  static const _lumR = 0.2126;
  static const _lumG = 0.7152;
  static const _lumB = 0.0722;

  /// Recolore a telha mapeando a luminância numa rampa entre duas cores.
  ///
  /// [naEscuridao] é a cor que o preto da telha vira; [naLuz], a que o branco
  /// vira. A ORDEM é o que expressa a inversão: no modo claro vai sépia → creme
  /// (o traço escurece, o papel clareia); no escuro vai tinta pálida →
  /// meia-noite, e a mesma fórmula produz o negativo, sem segunda matriz.
  static ColorFilter _rampa(Color naEscuridao, Color naLuz) =>
      ColorFilter.matrix(matrizRampa(naEscuridao, naLuz));

  /// A matriz da rampa, exposta para teste.
  ///
  /// Escrever esta matriz à mão é fácil de inverter sem perceber — e uma rampa
  /// invertida produz um NEGATIVO do mapa, que na tela parece "o mapa sumiu"
  /// em vez de "a cor está errada". Por isso ela é testável.
  @visibleForTesting
  static List<double> matrizRampa(Color naEscuridao, Color naLuz) {
    final br = naEscuridao.r, bg = naEscuridao.g, bb = naEscuridao.b;
    final ar = naLuz.r, ag = naLuz.g, ab = naLuz.b;

    // saida = naEscuridao + luminancia * (naLuz - naEscuridao)
    final sr = ar - br, sg = ag - bg, sb = ab - bb;
    return <double>[
      sr * _lumR, sr * _lumG, sr * _lumB, 0, br * 255,
      sg * _lumR, sg * _lumG, sg * _lumB, 0, bg * 255,
      sb * _lumR, sb * _lumG, sb * _lumB, 0, bb * 255,
      0, 0, 0, 1, 0,
    ];
  }

  /// Aplica a matriz a uma cor — o que a GPU faria por pixel. Existe para os
  /// testes poderem afirmar "o branco da telha vira creme" em cores, e não em
  /// coeficientes.
  @visibleForTesting
  static Color aplicar(List<double> m, Color entrada) {
    double canal(int i) => (m[i * 5] * entrada.r * 255 +
            m[i * 5 + 1] * entrada.g * 255 +
            m[i * 5 + 2] * entrada.b * 255 +
            m[i * 5 + 4])
        .clamp(0, 255);
    return Color.fromARGB(
      255,
      canal(0).round(),
      canal(1).round(),
      canal(2).round(),
    );
  }

  /// As duas rampas, para os testes conferirem os extremos.
  @visibleForTesting
  static List<double> get matrizClara =>
      matrizRampa(const Color(0xFF6B5540), const Color(0xFFF7F2E7));

  @visibleForTesting
  static List<double> get matrizEscura =>
      matrizRampa(const Color(0xFFAEB9CE), const Color(0xFF0C1322));

  /// Papel quente: o traço vira sépia, o fundo vira creme.
  static final _claro = _rampa(
    const Color(0xFF6B5540), // preto da telha -> couro escuro
    const Color(0xFFF7F2E7), // branco da telha -> papel
  );

  /// Atlas noturno: o papel vira meia-noite e o traço, tinta pálida. As cores
  /// entram na ordem inversa — é isso que faz a telha virar negativo.
  static final _escuro = _rampa(
    const Color(0xFFAEB9CE), // preto da telha -> tinta clara
    const Color(0xFF0C1322), // branco da telha -> meia-noite
  );

  static ColorFilter filtro(SJScheme s) =>
      s.brightness == Brightness.dark ? _escuro : _claro;

  /// A camada de telhas pronta, já na cor do tema.
  static TileLayer layer(BuildContext context, SJScheme s) => TileLayer(
        urlTemplate: tileUrl,
        userAgentPackageName: userAgent,
        // O OSM não serve telhas @2x, e a URL não tem o marcador {r}. Com
        // retinaMode ligado, o flutter_map entra em modo SIMULADO: corta o
        // tileSize pela metade e desloca o zoom — configuração errada para
        // esta base. Desligado, ele pede as telhas 256px que existem de fato.
        retinaMode: false,
        // O filtro vai por telha (e não no mapa inteiro) para NÃO tingir os
        // pins, os rastros e o rótulo de atribuição desenhados por cima.
        tileBuilder: (context, tileWidget, tile) => ColorFiltered(
          colorFilter: filtro(s),
          child: tileWidget,
        ),
      );

  /// Selo de atribuição: discreto, no canto, no vocabulário do design system
  /// (mono, caixa alta, tinta suave sobre a superfície).
  static Widget selo(SJScheme s) => Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(SJSpace.x2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: s.surface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(SJRadius.sm),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SJSpace.x2,
                vertical: 2,
              ),
              child: Text(
                attribution,
                style: SJText.caption(color: s.inkSoft).copyWith(
                  fontFamily: SJType.mono,
                  fontFamilyFallback: SJType.monoFallback,
                  fontSize: 9,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      );
}
