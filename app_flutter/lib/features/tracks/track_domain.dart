/// # Percurso real — CAMADA DE DOMÍNIO (Dart puro, zero Flutter, zero GPS).
///
/// Mesma decisão do atlas: a inteligência mora aqui e o resto fica bobo. O
/// serviço que fala com o GPS e com a API (`track_recorder.dart`) só entrega
/// leituras e obedece ao veredito. Ganho concreto: dá para testar caminhada,
/// parada no semáforo, sinal ruim e relógio pulando — sem sair do lugar.
///
/// ## O problema que este módulo resolve
///
/// GPS cru não é o caminho que a pessoa fez. Parada num café, a leitura oscila
/// de 5 a 15 metros e desenha um rabisco; num túnel ou entre prédios altos, ela
/// salta quarteirões. Gravar tudo produziria um traço sujo, uma distância
/// inflada ("você caminhou 800 m" sentado) e um payload enorme. Filtrar é o que
/// transforma leitura de sensor em percurso.
library;

import '../atlas/atlas_domain.dart' show AtlasDomain;

/// Uma leitura de posição vinda do dispositivo, antes de qualquer julgamento.
class TrackSample {
  const TrackSample({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
  });

  final double latitude;
  final double longitude;

  /// Instante da CAPTURA no aparelho, não do envio. É o que ordena o percurso.
  final DateTime recordedAt;

  /// Raio de erro estimado, em metros. Nulo = o aparelho não informou.
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'altitude': altitude,
        'speed': speed,
        'heading': heading,
        'recorded_at': recordedAt.toUtc().toIso8601String(),
      };
}

/// O que o domínio decidiu sobre uma leitura — e por quê.
///
/// Recusar em silêncio esconderia do usuário por que o traço parou de crescer.
/// Com o motivo na mão, a tela pode dizer "procurando sinal" em vez de fingir
/// que está tudo bem.
enum SampleVerdict {
  /// Entrou no percurso.
  accepted,

  /// Erro estimado grande demais: a leitura não distingue rua de quarteirão.
  inaccurate,

  /// Perto demais da anterior para ser movimento — é oscilação de quem parou.
  stationary,

  /// Chegou antes do intervalo mínimo; a anterior ainda representa a posição.
  tooSoon,

  /// Carimbo de tempo igual ou anterior ao último aceito (relógio pulou,
  /// leitura chegou fora de ordem). Aceitar corromperia a ordem do traço.
  outOfOrder,
}

/// Quando uma leitura vira ponto do percurso.
///
/// Os limites são conservadores de propósito: é melhor um traço com menos
/// pontos e fiel do que um traço denso e mentiroso.
class SamplingPolicy {
  const SamplingPolicy({
    this.maxAccuracyMeters = 50,
    this.minDistanceMeters = 12,
    this.minInterval = const Duration(seconds: 3),
  });

  /// Acima disto a leitura é descartada. 50 m é a fronteira prática entre
  /// "sei em que rua estou" e "sei em que bairro estou".
  final double maxAccuracyMeters;

  /// Piso de deslocamento para a leitura contar como movimento.
  final double minDistanceMeters;

  /// Piso de tempo entre pontos aceitos.
  final Duration minInterval;

  /// Política para gravar a pé: passo curto, tolerância menor a erro.
  static const walking = SamplingPolicy(
    maxAccuracyMeters: 30,
    minDistanceMeters: 8,
    minInterval: Duration(seconds: 2),
  );

  /// Política para deslocamento em veículo: pontos mais espaçados.
  static const driving = SamplingPolicy(
    maxAccuracyMeters: 80,
    minDistanceMeters: 40,
    minInterval: Duration(seconds: 5),
  );
}

/// Resultado de oferecer uma leitura ao domínio.
class SampleOutcome {
  const SampleOutcome(this.verdict, {this.shouldFlush = false});

  final SampleVerdict verdict;

  /// O buffer atingiu o lote: quem chama deve enviar agora.
  final bool shouldFlush;

  bool get accepted => verdict == SampleVerdict.accepted;
}

/// O gravador, em estado puro: recebe leituras, decide, acumula.
///
/// Não conhece GPS, HTTP nem telas. Quem o usa pergunta o que fazer e faz.
class TrackRecorderCore {
  TrackRecorderCore({
    this.policy = const SamplingPolicy(),
    this.flushEvery = 10,
  }) : assert(flushEvery > 0);

  final SamplingPolicy policy;

  /// A cada quantos pontos aceitos vale a pena subir um lote. Segurar tudo em
  /// memória perderia o percurso se o app morresse; subir a cada ponto gastaria
  /// bateria e rede à toa.
  final int flushEvery;

  final List<TrackSample> _buffer = [];
  TrackSample? _last;
  double _distanceMeters = 0;
  int _acceptedCount = 0;

  /// Pontos aguardando envio.
  List<TrackSample> get pending => List.unmodifiable(_buffer);
  bool get hasPending => _buffer.isNotEmpty;

  /// Quantos pontos entraram no percurso desde o início.
  int get acceptedCount => _acceptedCount;

  /// Distância acumulada dos pontos ACEITOS, em metros. Como a filtragem já
  /// removeu a oscilação de quem está parado, este número não infla sozinho.
  double get distanceMeters => _distanceMeters;

  /// A última posição que entrou no percurso.
  TrackSample? get lastAccepted => _last;

  /// Julga uma leitura e, se ela passar, acumula.
  SampleOutcome offer(TrackSample s) {
    final last = _last;

    if (last != null && !s.recordedAt.isAfter(last.recordedAt)) {
      return const SampleOutcome(SampleVerdict.outOfOrder);
    }

    final accuracy = s.accuracy;
    if (accuracy != null && accuracy > policy.maxAccuracyMeters) {
      return const SampleOutcome(SampleVerdict.inaccurate);
    }

    if (last != null) {
      if (s.recordedAt.difference(last.recordedAt) < policy.minInterval) {
        return const SampleOutcome(SampleVerdict.tooSoon);
      }

      final moved = AtlasDomain.haversineMeters(
        last.latitude,
        last.longitude,
        s.latitude,
        s.longitude,
      );

      // O piso é o MAIOR entre a distância mínima e o próprio erro da leitura:
      // um ponto com 30 m de incerteza que "andou" 20 m provavelmente não andou.
      // É o que impede a parada no semáforo de virar rabisco no mapa.
      final floor = accuracy == null
          ? policy.minDistanceMeters
          : (accuracy > policy.minDistanceMeters
              ? accuracy
              : policy.minDistanceMeters);
      if (moved < floor) {
        return const SampleOutcome(SampleVerdict.stationary);
      }

      _distanceMeters += moved;
    }

    _buffer.add(s);
    _last = s;
    _acceptedCount++;
    return SampleOutcome(
      SampleVerdict.accepted,
      shouldFlush: _buffer.length >= flushEvery,
    );
  }

  /// Retira os pontos pendentes para envio. Quem chama fica responsável por
  /// eles: em falha, devolva com [restore].
  List<TrackSample> drain() {
    final out = List<TrackSample>.from(_buffer);
    _buffer.clear();
    return out;
  }

  /// Devolve ao início da fila pontos cujo envio falhou, preservando a ordem.
  ///
  /// Sem isto, uma queda de rede de dez segundos apagaria o trecho do percurso
  /// que aconteceu nela — e ninguém perceberia, porque o traço continuaria
  /// crescendo depois.
  void restore(List<TrackSample> points) {
    if (points.isEmpty) return;
    _buffer.insertAll(0, points);
  }

  /// Zera para um novo trecho, mantendo a política.
  void reset() {
    _buffer.clear();
    _last = null;
    _distanceMeters = 0;
    _acceptedCount = 0;
  }
}
