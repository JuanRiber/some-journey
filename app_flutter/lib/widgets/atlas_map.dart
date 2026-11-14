import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../design/basemap.dart';
import '../features/atlas/atlas_domain.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../models.dart';

/// Mapa do atlas em PAPEL: as telhas do OpenStreetMap passam pelo filtro de
/// [SJBasemap] e chegam na cor do tema — sépia sobre creme no claro, tinta
/// pálida sobre meia-noite no escuro. O fundo é discreto de propósito: os pins
/// e os rastros (a memória) é que são a informação. Pins vinho
/// (jornadas) e azul-lago (pontos soltos), rastros em vinho. A câmera é contida
/// a UM único mundo (sem cópias laterais vazias — o worldCopyJump do app web).
class AtlasMap extends StatefulWidget {
  final MapResponse? data;
  final void Function(String memoryId)? onSelect;
  final double height;

  /// Percurso REAL de GPS, uma lista de coordenadas `[lng, lat]` por trecho.
  ///
  /// Desenhado por cima e com traço distinto do rastro simbólico de propósito:
  /// são coisas diferentes. O simbólico liga memórias na ordem; este é o caminho
  /// que a pessoa percorreu de fato.
  final List<List<List<double>>>? trackLines;

  const AtlasMap({
    super.key,
    required this.data,
    this.onSelect,
    this.height = 380,
    this.trackLines,
  });

  @override
  State<AtlasMap> createState() => _AtlasMapState();
}

class _AtlasMapState extends State<AtlasMap>
    with SingleTickerProviderStateMixin {
  /// O rastro é TRAÇADO ao aparecer, em vez de surgir pronto.
  ///
  /// É a animação "linha que conecta" do design system — a única do mapa, e ela
  /// explica uma transição: o caminho que liga os lugares está sendo escrito.
  /// Roda UMA vez, quando o rastro chega; repetir a cada rebuild viraria o
  /// enfeite que o mesmo documento proíbe.
  late final AnimationController _traco = AnimationController(
    vsync: this,
    // 420ms é a duração mais longa da escala do design system. Um traço rápido
    // e seguro cabe melhor em "nunca enfeite" do que um gesto teatral.
    duration: const Duration(milliseconds: 420),
  );

  bool _jaTracou = false;

  /// A câmera ENQUADRA os pontos: abre mostrando todos eles, com respiro, e
  /// reenquadra quando o conjunto muda (os dados chegaram, a lente de fase
  /// trocou, uma parada entrou na jornada).
  ///
  /// Uma câmera fixada só ao nascer não basta: o atlas nasce antes da resposta
  /// da API — o mapa ficava no zoom de continente com tudo empilhado num pin.
  final MapController _camera = MapController();
  bool _cameraPronta = false;

  /// O retângulo enquadrado por último e o que os dados pedem agora.
  GeoBounds? _enquadrado;
  GeoBounds? _desejado;

  static const _respiro = EdgeInsets.all(36);

  CameraFit _fit(GeoBounds b) => CameraFit.bounds(
        bounds: LatLngBounds(LatLng(b.minLat, b.minLng), LatLng(b.maxLat, b.maxLng)),
        padding: _respiro,
        maxZoom: AtlasDomain.frameMaxZoom,
      );

  /// Geração da camada de telhas: trocar a `key` recria a camada.
  int _geracaoTelhas = 0;

  void _reenquadrar() {
    if (!_cameraPronta || !mounted) return;
    if (!AtlasDomain.shouldRefit(_enquadrado, _desejado)) return;
    _enquadrado = _desejado;
    _camera.fitCamera(_fit(_desejado!));
    // A camada de telhas poda o que sobrou usando a câmera do ÚLTIMO build
    // dela, e o enquadramento acontece fora de um quadro. As telhas do zoom
    // novo voltam do cache em milissegundos — antes de a camada se reconstruir
    // — e a poda, ainda com a câmera antiga, apagava justamente elas: os pins
    // no lugar e o fundo vazio (ou o zoom de continente esticado) até alguém
    // arrastar o mapa. Depois do quadro, uma camada NOVA nasce lendo a
    // câmera já enquadrada e pede e poda com ela. (O `reset` do TileLayer
    // seria o caminho natural, mas no flutter_map 7.0.2 a assinatura dele é
    // um `late final` que ninguém lê — os eventos não chegam a lugar nenhum.)
    SchedulerBinding.instance.endOfFrame.then((_) {
      if (mounted) setState(() => _geracaoTelhas++);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Quem pede menos movimento no sistema recebe o rastro pronto, sem gesto.
    if (MediaQuery.disableAnimationsOf(context)) {
      _traco.value = 1;
      _jaTracou = true;
    }
  }

  @override
  void dispose() {
    _camera.dispose();
    _traco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // O mapa passa a seguir o tema: no atlas noturno, um retângulo creme
    // brilhante no meio da tela escura pareceria um erro de renderização.
    final esquema = SJTheme.of(context);
    // O traço começa quando existe rastro para traçar — e só na primeira vez.
    final temRastro = (widget.trackLines?.any((l) => l.length >= 2) ?? false) ||
        (widget.data?.journeys
                .any((j) => (j.route?.coordinates.length ?? 0) >= 2) ??
            false);
    if (temRastro && !_jaTracou) {
      _jaTracou = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _traco.forward());
    }

    final markers = <Marker>[];
    final all = <LatLng>[];

    /// As polilinhas do quadro atual: os rastros crescem com [t].
    ///
    /// Recalcular por quadro é barato — são dezenas de pontos — e é o que
    /// permite a ponta avançar interpolada, em vez de pular de vértice em
    /// vértice.
    List<Polyline> tracar(double t) {
      final linhas = <Polyline>[];
      for (final j in widget.data?.journeys ?? const []) {
        final route = j.route;
        if (route != null && route.coordinates.length >= 2) {
          final parcial = AtlasDomain.partialLine(route.coordinates, t);
          if (parcial.length >= 2) {
            linhas.add(Polyline(
              points: parcial.map((c) => LatLng(c[1], c[0])).toList(),
              // Rastro simbólico da jornada: vinho (a cor da ação/jornada).
              color: esquema.primary.withValues(alpha: 0.75),
              strokeWidth: 3,
            ));
          }
        }
      }
      for (final line in widget.trackLines ?? const <List<List<double>>>[]) {
        final parcial = AtlasDomain.partialLine(line, t);
        if (parcial.length < 2) continue;
        linhas.add(Polyline(
          points: parcial.map((c) => LatLng(c[1], c[0])).toList(),
          // Ciano (o acento de "lugar/percurso"), mais grosso que o simbólico:
          // o caminho real é o protagonista quando existe.
          color: esquema.secondary.withValues(alpha: 0.9),
          strokeWidth: 4.5,
        ));
      }
      return linhas;
    }

    if (widget.data != null) {
      for (final j in widget.data!.journeys) {
        for (final p in j.points) {
          final pos = LatLng(p.latitude, p.longitude);
          all.add(pos);
          markers.add(_pin(pos, esquema.primary, esquema, p.memoryId));
        }
      }
      for (final p in widget.data!.loosePoints) {
        final pos = LatLng(p.latitude, p.longitude);
        all.add(pos);
        markers.add(_pin(pos, esquema.secondary, esquema, p.memoryId));
      }
    }

    // Os pontos do percurso entram no enquadramento da câmera mesmo antes de
    // serem traçados: o mapa não deve se mexer enquanto a linha cresce.
    for (final line in widget.trackLines ?? const <List<List<double>>>[]) {
      all.addAll(line.map((c) => LatLng(c[1], c[0])));
    }

    _desejado = AtlasDomain.boundsOfCoords(all.map((p) => (p.latitude, p.longitude)));
    // Cada mudança de retângulo reenquadra ao fim do quadro; antes de a câmera
    // ficar pronta, quem enquadra é o `onMapReady`.
    if (AtlasDomain.shouldRefit(_enquadrado, _desejado)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reenquadrar());
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        border: Border.all(color: esquema.frame, width: 3),
        borderRadius: BorderRadius.circular(3),
        color: esquema.bgDeep,
      ),
      clipBehavior: Clip.antiAlias,
      // O selo de atribuição fica SOBRE o mapa, não dentro dele: `children` do
      // FlutterMap é uma lista de CAMADAS, e um widget comum ali confunde o
      // pipeline de camadas.
      child: Stack(children: [
        FlutterMap(
        mapController: _camera,
        options: MapOptions(
          // Sem pontos: o Brasil em visão ampla.
          initialCenter: const LatLng(-14.235, -51.925),
          initialZoom: 3,
          // O enquadramento inicial também passa por `_reenquadrar`, e não por
          // `initialCameraFit`: é lá que mora o recarregamento das telhas
          // depois do quadro. Uma volta do event loop depois do onMapReady,
          // para vir depois do evento de tamanho que o flutter_map 7 adia
          // para o fim do primeiro quadro.
          onMapReady: () {
            _cameraPronta = true;
            Future(_reenquadrar);
          },
          minZoom: 2,
          maxZoom: 19,
          // Mundo ÚNICO: a câmera não sai dos limites [-180, 180] — nada de
          // "vários Brasils" com pins em só um.
          cameraConstraint: CameraConstraint.contain(
            bounds: LatLngBounds(const LatLng(-85, -180), const LatLng(85, 180)),
          ),
          backgroundColor: esquema.bgDeep,
        ),
        children: [
          KeyedSubtree(
            key: ValueKey(_geracaoTelhas),
            child: SJBasemap.layer(context, esquema),
          ),
          AnimatedBuilder(
            animation: _traco,
            builder: (_, _) => PolylineLayer(polylines: tracar(_traco.value)),
          ),
          MarkerLayer(markers: markers),
        ],
        ),
        SJBasemap.selo(esquema),
      ]),
    );
  }

  Marker _pin(LatLng pos, Color color, SJScheme s, String memoryId) => Marker(
        point: pos,
        width: 20,
        height: 20,
        child: GestureDetector(
          onTap: widget.onSelect == null ? null : () => widget.onSelect!(memoryId),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              // Anel creme: destaca o pin sobre a base clara sem endurecer o
              // desenho; a sombra é muito suave (nada de preto duro no papel).
              border: Border.all(color: s.surface, width: 2),
              boxShadow: [
                BoxShadow(
                  color: s.shadow.withValues(alpha: 0.22),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      );
}
