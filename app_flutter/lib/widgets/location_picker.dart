import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../theme.dart';

class GeoResult {
  final double latitude;
  final double longitude;
  final String label;
  GeoResult(this.latitude, this.longitude, this.label);
}

/// Busca por nome no Nominatim (OpenStreetMap) — mesma política do app web.
Future<List<GeoResult>> searchPlaces(String query) async {
  final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search?format=json&limit=5&q=${Uri.encodeQueryComponent(query)}');
  final r = await http.get(uri, headers: {'User-Agent': 'SomeJourney/1.0'})
      .timeout(const Duration(seconds: 10));
  if (r.statusCode != 200) return [];
  final data = jsonDecode(utf8.decode(r.bodyBytes)) as List;
  return data
      .map((e) => GeoResult(
            double.parse(e['lat'] as String),
            double.parse(e['lon'] as String),
            e['display_name'] as String,
          ))
      .toList();
}

/// Picker de local: busca por nome + toque no mapa noturno (pino vinho).
class LocationPicker extends StatefulWidget {
  final double? latitude;
  final double? longitude;
  final void Function(double lat, double lng, String? label) onChange;

  const LocationPicker({super.key, this.latitude, this.longitude, required this.onChange});

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  final _query = TextEditingController();
  final _mapController = MapController();
  Timer? _debounce;
  List<GeoResult> _results = [];
  bool _searching = false;
  String _placeLabel = '';
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    if (widget.latitude != null && widget.longitude != null) {
      _picked = LatLng(widget.latitude!, widget.longitude!);
    }
    _query.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final q = _query.text.trim();
    if (q.length < 3) {
      setState(() => _results = []);
      return;
    }
    // Debounce de 600ms: respeita a política de uso do Nominatim.
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      setState(() => _searching = true);
      try {
        final res = await searchPlaces(q);
        if (mounted) setState(() => _results = res);
      } catch (_) {
        if (mounted) setState(() => _results = []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _select(double lat, double lng, String? label) {
    setState(() {
      _picked = LatLng(lat, lng);
      _placeLabel = label ?? '';
      _results = [];
      _query.clear();
    });
    _mapController.move(LatLng(lat, lng), 13);
    widget.onChange(lat, lng, label);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          alignment: Alignment.centerRight,
          children: [
            TextField(
              controller: _query,
              decoration:
                  const InputDecoration(hintText: 'Busque um lugar: cidade, praia, endereço…'),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.only(right: 14),
                child: SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: SJColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SJColors.line),
            ),
            child: Column(
              children: _results
                  .map((r) => InkWell(
                        onTap: () => _select(r.latitude, r.longitude, r.label),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: SJColors.line))),
                          child: Text(r.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: SJColors.ink, fontSize: 13, height: 1.4)),
                        ),
                      ))
                  .toList(),
            ),
          ),
        const SizedBox(height: 10),
        Container(
          height: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: SJColors.line),
            color: SJColors.sand,
          ),
          clipBehavior: Clip.antiAlias,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _picked ?? const LatLng(-14.235, -51.925),
              initialZoom: _picked == null ? 3 : 13,
              minZoom: 2,
              maxZoom: 19,
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds(const LatLng(-85, -180), const LatLng(85, 180)),
              ),
              backgroundColor: SJColors.sand,
              onTap: (_, pos) => _select(pos.latitude, pos.longitude, null),
            ),
            children: [
              TileLayer(
                // Base clara (Positron): casa com o papel da interface.
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                retinaMode: RetinaMode.isHighDensity(context),
                userAgentPackageName: 'app.somejourney',
              ),
              if (_picked != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _picked!,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: SJColors.wine,
                        shape: BoxShape.circle,
                        // Anel creme sobre a base clara (mesmo pin do atlas).
                        border: Border.all(color: SJColors.card, width: 2),
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
                ]),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_picked != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SJColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SJColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_placeLabel.isEmpty ? 'Local selecionado' : _placeLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: SJColors.ink, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  '${_picked!.latitude.toStringAsFixed(5)}, ${_picked!.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(color: SJColors.inkSoft, fontSize: 12),
                ),
              ],
            ),
          )
        else
          const Text('Toque no mapa ou busque um lugar.',
              style: TextStyle(
                  color: SJColors.inkSoft, fontSize: 13, fontStyle: FontStyle.italic)),
        const SizedBox(height: 8),
        const Text('A busca e o nome do lugar usam o OpenStreetMap.',
            style: TextStyle(color: SJColors.placeholder, fontSize: 11)),
      ],
    );
  }
}
