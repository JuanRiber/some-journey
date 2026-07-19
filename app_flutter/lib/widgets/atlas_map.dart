import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models.dart';
import '../theme.dart';

/// Mapa noturno do atlas: tiles CARTO dark, pins vinho (jornadas) e ciano
/// (pontos soltos), rastros em ciano. A câmera é contida a UM único mundo
/// (sem cópias laterais vazias — o equivalente do worldCopyJump do app web).
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
            color: SJColors.cyan.withValues(alpha: 0.85),
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
            urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
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
              border: Border.all(color: SJColors.ink, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
            ),
          ),
        ),
      );
}
