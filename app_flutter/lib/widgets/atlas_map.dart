import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models.dart';
import '../theme.dart';

/// Mapa do atlas em PAPEL: tiles claros (CARTO Positron), que casam com o creme
/// da interface e deixam a cartografia parecer um mapa impresso — o fundo é
/// discreto para os pins e rastros (a memória) serem a informação. Pins vinho
/// (jornadas) e azul-lago (pontos soltos), rastros em vinho. A câmera é contida
/// a UM único mundo (sem cópias laterais vazias — o worldCopyJump do app web).
class AtlasMap extends StatelessWidget {
  final MapResponse? data;
  final void Function(String memoryId)? onSelect;
  final double height;

  const AtlasMap({super.key, required this.data, this.onSelect, this.height = 380});

  @override
  Widget build(BuildContext context) {
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
            color: SJColors.wine.withValues(alpha: 0.75),
            strokeWidth: 3,
          ));
        }
        for (final p in j.points) {
          final pos = LatLng(p.latitude, p.longitude);
          all.add(pos);
          markers.add(_pin(pos, SJColors.wine, p.memoryId));
        }
      }
      for (final p in data!.loosePoints) {
        final pos = LatLng(p.latitude, p.longitude);
        all.add(pos);
        markers.add(_pin(pos, SJColors.cyan, p.memoryId));
      }
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
        border: Border.all(color: SJColors.frame, width: 3),
        borderRadius: BorderRadius.circular(3),
        color: SJColors.sand,
      ),
      clipBehavior: Clip.antiAlias,
      child: FlutterMap(
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
          backgroundColor: SJColors.sand,
        ),
        children: [
          TileLayer(
            // Positron = base clara e silenciosa (papel). Trocar por dark_all
            // quando o modo escuro por tela chegar.
            urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
            subdomains: const ['a', 'b', 'c', 'd'],
            retinaMode: RetinaMode.isHighDensity(context),
            userAgentPackageName: 'app.somejourney',
          ),
          PolylineLayer(polylines: polylines),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }

  Marker _pin(LatLng pos, Color color, String memoryId) => Marker(
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
              border: Border.all(color: const Color(0xFFFBF8F1), width: 2),
              boxShadow: [
                BoxShadow(
                  color: SJColors.ink.withValues(alpha: 0.22),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      );
}
