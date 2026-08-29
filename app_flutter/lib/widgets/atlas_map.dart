import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../design/basemap.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../models.dart';

/// Mapa do atlas em PAPEL: as telhas do OpenStreetMap passam pelo filtro de
/// [SJBasemap] e chegam na cor do tema — sépia sobre creme no claro, tinta
/// pálida sobre meia-noite no escuro. O fundo é discreto de propósito: os pins
/// e os rastros (a memória) é que são a informação. Pins vinho
/// (jornadas) e azul-lago (pontos soltos), rastros em vinho. A câmera é contida
/// a UM único mundo (sem cópias laterais vazias — o worldCopyJump do app web).
class AtlasMap extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // O mapa passa a seguir o tema: no atlas noturno, um retângulo creme
    // brilhante no meio da tela escura pareceria um erro de renderização.
    final esquema = SJTheme.of(context);
    final markers = <Marker>[];
    final polylines = <Polyline>[];
    final all = <LatLng>[];

    if (data != null) {
      for (final j in data!.journeys) {
        final route = j.route;
        if (route != null && route.coordinates.length >= 2) {
          polylines.add(Polyline(
            points: route.coordinates.map((c) => LatLng(c[1], c[0])).toList(),
            // Rastro simbólico da jornada: vinho (a cor da ação/jornada).
            color: esquema.primary.withValues(alpha: 0.75),
            strokeWidth: 3,
          ));
        }
        for (final p in j.points) {
          final pos = LatLng(p.latitude, p.longitude);
          all.add(pos);
          markers.add(_pin(pos, esquema.primary, esquema, p.memoryId));
        }
      }
      for (final p in data!.loosePoints) {
        final pos = LatLng(p.latitude, p.longitude);
        all.add(pos);
        markers.add(_pin(pos, esquema.secondary, esquema, p.memoryId));
      }
    }

    for (final line in trackLines ?? const <List<List<double>>>[]) {
      if (line.length < 2) continue;
      final pontos = line.map((c) => LatLng(c[1], c[0])).toList();
      all.addAll(pontos);
      polylines.add(Polyline(
        points: pontos,
        // Ciano (o acento de "lugar/percurso"), mais grosso que o simbólico:
        // o caminho real é o protagonista quando existe.
        color: esquema.secondary.withValues(alpha: 0.9),
        strokeWidth: 4.5,
      ));
    }

    final center = all.isEmpty
        ? const LatLng(-14.235, -51.925) // Brasil (visão ampla)
        : LatLng(
            all.map((p) => p.latitude).reduce((a, b) => a + b) / all.length,
            all.map((p) => p.longitude).reduce((a, b) => a + b) / all.length,
          );

    return Container(
      height: height,
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
          PolylineLayer(polylines: polylines),
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
          onTap: onSelect == null ? null : () => onSelect!(memoryId),
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
