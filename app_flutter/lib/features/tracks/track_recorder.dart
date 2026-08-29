/// Gravação de percurso em PRIMEIRO PLANO — orquestração.
///
/// Junta três coisas que existem separadas de propósito: a fonte de posição
/// ([LocationSource]), a política de amostragem ([TrackRecorderCore]) e a API.
/// Nada de regra mora aqui; aqui mora a coreografia — pedir permissão, abrir o
/// trecho, ouvir, subir em lote, fechar.
///
/// NÃO grava em segundo plano. Isso exigiria permissão de background nas duas
/// plataformas e um serviço de longa duração; a gravação vale enquanto a tela
/// está aberta, e o usuário sempre inicia e encerra de forma explícita.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api.dart';
import 'location_source.dart';
import 'track_domain.dart';

enum RecorderStatus { idle, preparing, recording, finishing, error }

/// Estado observável da gravação. A tela escuta e desenha; não decide nada.
class TrackRecorder extends ChangeNotifier {
  TrackRecorder({
    required this.journeyId,
    LocationSource? source,
    SamplingPolicy policy = SamplingPolicy.walking,
    int flushEvery = 10,
    Api? api,
  })  : _source = source ?? const GeolocatorLocationSource(),
        _api = api ?? Api.instance,
        _core = TrackRecorderCore(policy: policy, flushEvery: flushEvery);

  final String journeyId;
  final LocationSource _source;
  final Api _api;
  final TrackRecorderCore _core;

  StreamSubscription<TrackSample>? _sub;
  String? _trackId;
  Future<void>? _inFlight;
  bool _closing = false;

  RecorderStatus _status = RecorderStatus.idle;
  String _error = '';
  SampleVerdict? _lastVerdict;

  RecorderStatus get status => _status;
  String get error => _error;
  bool get isRecording => _status == RecorderStatus.recording;
  bool get isBusy =>
      _status == RecorderStatus.preparing || _status == RecorderStatus.finishing;

  /// Pontos que entraram no percurso e distância acumulada — o que a tela mostra
  /// ao vivo.
  int get pointCount => _core.acceptedCount;
  double get distanceMeters => _core.distanceMeters;

  /// Pontos capturados mas ainda não confirmados pelo servidor.
  int get pendingCount => _core.pending.length;

  /// Por que a última leitura não entrou. Deixa a tela dizer "procurando sinal"
  /// em vez de parecer travada.
  SampleVerdict? get lastVerdict => _lastVerdict;

  /// Abre um trecho e começa a ouvir o GPS.
  Future<void> start() async {
    if (_status == RecorderStatus.recording || isBusy) return;
    _set(RecorderStatus.preparing, error: '');
    try {
      await _source.ensurePermission();
      final track = await _api.startTrack(journeyId);
      _trackId = track.id;
      _closing = false;
      _core.reset();
      _sub = _source.watch(_core.policy).listen(
            _onSample,
            onError: (_) => _fail('O sinal de GPS falhou. Tente de novo.'),
          );
      _set(RecorderStatus.recording);
    } on LocationUnavailable catch (e) {
      _fail(e.message);
    } on ApiError catch (e) {
      // 409: já existe um trecho aberto nesta jornada.
      _fail(e.status == 409
          ? 'Já há uma gravação aberta nesta jornada. Encerre antes de começar outra.'
          : e.message);
    } catch (_) {
      _fail('Não consegui iniciar a gravação.');
    }
  }

  /// Encerra o trecho: sobe o que sobrou e finaliza no servidor.
  ///
  /// Fecha o trecho MESMO se o último envio falhar — deixar um trecho aberto
  /// bloquearia a próxima gravação com 409, e o percurso já gravado vale mais
  /// que os últimos metros.
  Future<void> stop() async {
    if (_trackId == null || _status == RecorderStatus.finishing) return;
    _set(RecorderStatus.finishing);
    _closing = true;
    await _sub?.cancel();
    _sub = null;
    try {
      await _flushAll();
    } catch (_) {
      // segue para finalizar mesmo assim
    }
    final id = _trackId;
    _trackId = null;
    try {
      if (id != null) await _api.finishTrack(journeyId, id);
      _set(RecorderStatus.idle);
    } on ApiError catch (e) {
      _fail(e.message);
    }
  }

  void _onSample(TrackSample s) {
    final out = _core.offer(s);
    _lastVerdict = out.verdict;
    if (out.shouldFlush) unawaited(_flush());
    notifyListeners();
  }

  /// Serializa os envios: encadeia após o que estiver em voo. Dois lotes em
  /// paralelo poderiam chegar fora de ordem ao servidor.
  Future<void> _flush() {
    final prev = _inFlight ?? Future<void>.value();
    late final Future<void> next;
    next = prev.then((_) => _flushOnce()).whenComplete(() {
      if (identical(_inFlight, next)) _inFlight = null;
    });
    _inFlight = next;
    return next;
  }

  Future<void> _flushOnce() async {
    final id = _trackId;
    if (id == null || !_core.hasPending) return;
    final batch = _core.drain();
    try {
      await _api.addTrackPoints(
          journeyId, id, batch.map((p) => p.toJson()).toList());
    } catch (_) {
      // Devolve para tentar de novo — a menos que o trecho esteja fechando, e aí
      // reinserir só deixaria pontos órfãos que nunca subiriam.
      if (!_closing) _core.restore(batch);
    }
    notifyListeners();
  }

  /// Espera o envio em voo e repete até o buffer zerar (ou parar de progredir).
  Future<void> _flushAll() async {
    var antes = -1;
    while (_core.hasPending && _core.pending.length != antes) {
      antes = _core.pending.length;
      await _flush();
    }
  }

  void _set(RecorderStatus s, {String? error}) {
    _status = s;
    if (error != null) _error = error;
    notifyListeners();
  }

  void _fail(String message) {
    _error = message;
    _status = RecorderStatus.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
