import 'package:flutter/material.dart';
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

    final center = all.isEmpty
        ? const LatLng(-14.235, -51.925) // Brasil (visão ampla)
        : LatLng(
            all.map((p) => p.latitude).reduce((a, b) => a + b) / all.length,
            all.map((p) => p.longitude).reduce((a, b) => a + b) / all.length,
          );

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
        options: MapOptions(
          initialCenter: center,
          initialZoom: all.isEmpty ? 3 : 4,
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
          SJBasemap.layer(context, esquema),
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
