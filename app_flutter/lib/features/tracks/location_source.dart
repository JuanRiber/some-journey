/// Fonte de posição — CONTRATO + adaptador.
///
/// Mesmo padrão do provedor de música e do de geocodificação do backend: o
/// gravador conversa com esta interface, nunca com o pacote de GPS. Trocar de
/// biblioteca é escrever outra classe; testar é passar uma falsa.
library;

import 'package:geolocator/geolocator.dart';

import 'track_domain.dart';

/// Por que a gravação não pôde começar. A tela precisa distinguir os casos:
/// "ligue o GPS" e "autorize no ajustes do sistema" pedem ações diferentes.
enum LocationDenial {
  /// O serviço de localização do aparelho está desligado.
  serviceDisabled,

  /// O usuário recusou agora — dá para pedir de novo.
  denied,

  /// Recusado permanentemente: só pelos ajustes do sistema.
  deniedForever,
}

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.reason);
  final LocationDenial reason;

  String get message => switch (reason) {
        LocationDenial.serviceDisabled =>
          'A localização do aparelho está desligada. Ligue para gravar o percurso.',
        LocationDenial.denied =>
          'Preciso da sua localização para desenhar por onde você passou.',
        LocationDenial.deniedForever =>
          'A permissão de localização está bloqueada. Libere nos ajustes do sistema.',
      };
}

abstract class LocationSource {
  /// Garante permissão de uso em primeiro plano. Lança [LocationUnavailable].
  Future<void> ensurePermission();

  /// Fluxo de leituras enquanto o app está em foco.
  Stream<TrackSample> watch(SamplingPolicy policy);
}

/// Adaptador do geolocator. Único ponto do app que conhece esse pacote.
class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  @override
  Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(LocationDenial.serviceDisabled);
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.deniedForever) {
      throw const LocationUnavailable(LocationDenial.deniedForever);
    }
    if (p == LocationPermission.denied) {
      throw const LocationUnavailable(LocationDenial.denied);
    }
  }

  @override
  Stream<TrackSample> watch(SamplingPolicy policy) {
    // O filtro fino é do domínio; aqui só evitamos acordar o rádio à toa. Por
    // isso o distanceFilter é METADE do piso do domínio: entregar de menos
    // esconderia movimento real que o domínio saberia aproveitar.
    final settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: (policy.minDistanceMeters / 2).round(),
    );
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (p) => TrackSample(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        altitude: p.altitude,
        speed: p.speed,
        heading: p.heading,
        recordedAt: p.timestamp.toUtc(),
      ),
    );
  }
}
