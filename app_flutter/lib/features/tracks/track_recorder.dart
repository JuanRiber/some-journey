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
///
/// O que ainda não subiu fica escrito no aparelho ([TrackOutbox]): se o app
/// morrer no meio, os pontos esperam ali e sobem quando a pessoa voltar à
/// jornada e encerrar a gravação que ficou aberta.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api.dart';
import 'location_source.dart';
import 'track_domain.dart';
import 'track_outbox.dart';

enum RecorderStatus { idle, preparing, recording, finishing, error }

/// Estado observável da gravação. A tela escuta e desenha; não decide nada.
class TrackRecorder extends ChangeNotifier {
  TrackRecorder({
    required this.journeyId,
    LocationSource? source,
    SamplingPolicy policy = SamplingPolicy.walking,
    int flushEvery = 10,
    Api? api,
    TrackOutbox? outbox,
  })  : _source = source ?? const GeolocatorLocationSource(),
        _api = api ?? Api.instance,
        _outbox = outbox ?? const PrefsTrackOutbox(),
        _core = TrackRecorderCore(policy: policy, flushEvery: flushEvery) {
    unawaited(_lerGuardado());
  }

  final String journeyId;
  final LocationSource _source;
  final Api _api;
  final TrackOutbox _outbox;
  final TrackRecorderCore _core;

  /// O lote que saiu do buffer e ainda não teve resposta. Enquanto ele está no
  /// ar não é de ninguém: já não está no buffer, e o servidor ainda não disse
  /// que recebeu. É justamente o que se perderia se o app morresse agora — por
  /// isso entra no que é guardado.
  List<TrackSample> _emVoo = const [];

  /// Fila das gravações em disco: uma de cada vez, na ordem. Duas em paralelo
  /// poderiam terminar invertidas e deixar guardada a lista mais velha.
  Future<void> _gravando = Future<void>.value();

  /// Pontos que uma gravação anterior deixou por enviar neste aparelho.
  int _guardados = 0;
  bool _descartado = false;

  StreamSubscription<TrackSample>? _sub;
  String? _trackId;
  Future<void>? _inFlight;

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
  int get pendingCount => _core.pending.length + _emVoo.length;

  /// Quantos pontos uma gravação INTERROMPIDA deixou guardados neste aparelho
  /// — o app foi fechado antes de enviá-los. Zero enquanto se grava: aí o que
  /// está guardado é o próprio [pendingCount].
  int get savedPointCount => isRecording || isBusy ? 0 : _guardados;

  Future<void> _lerGuardado() async {
    final guardado = await _outbox.load(journeyId);
    if (_descartado || guardado == null) return;
    // Uma gravação que começou enquanto o disco respondia já é dona do que
    // está guardado; o número de antes não vale mais.
    if (_trackId != null) return;
    _guardados = guardado.points.length;
    notifyListeners();
  }

  /// Escreve no aparelho o que falta subir: o lote no ar e o buffer.
  ///
  /// A lista é lida na hora de gravar, não na de pedir: dez pontos que entram
  /// enquanto o disco está ocupado viram uma gravação, não dez.
  void _guardar() {
    final id = _trackId;
    if (id == null) return;
    _gravando = _gravando.then(
      (_) => _outbox.save(journeyId, id, [..._emVoo, ..._core.pending]),
    );
  }

  /// Por que a última leitura não entrou. Deixa a tela dizer "procurando sinal"
  /// em vez de parecer travada.
  SampleVerdict? get lastVerdict => _lastVerdict;

  /// Abre um trecho e começa a ouvir o GPS.
  Future<void> start() async {
    if (_status == RecorderStatus.recording || isBusy) return;
    _set(RecorderStatus.preparing, error: '');
    _orphan = false;
    try {
      await _source.ensurePermission();
      final track = await _api.startTrack(journeyId);
      _trackId = track.id;
      _core.reset();
      _emVoo = const [];
      // O servidor abriu um trecho NOVO: o que estivesse guardado era de um
      // trecho que já fechou, e ponto de trecho fechado não tem para onde ir.
      _guardados = 0;
      _guardar();
      _sub = _source.watch(_core.policy).listen(
            _onSample,
            onError: (_) => _fail('O sinal de GPS falhou. Tente de novo.'),
          );
      _set(RecorderStatus.recording);
    } on LocationUnavailable catch (e) {
      _fail(e.message);
    } on ApiError catch (e) {
      // 409: já existe um trecho aberto nesta jornada — normalmente de uma
      // sessão que foi interrompida. Marca para a tela oferecer o encerramento
      // em vez de deixar a pessoa presa.
      _orphan = e.status == 409;
      _fail(e.status == 409
          ? 'Ficou uma gravação aberta nesta jornada, de antes. Encerre-a para começar outra.'
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
    await _sub?.cancel();
    _sub = null;
    try {
      await _flushAll();
    } catch (_) {
      // segue para finalizar mesmo assim
    }
    final id = _trackId;
    try {
      if (id != null) await _api.finishTrack(journeyId, id);
      // O id só é esquecido quando o servidor CONFIRMA o fechamento. Zerá-lo
      // antes, como estava, perdia a única referência para tentar de novo: o
      // trecho ficava aberto para sempre e a próxima gravação batia em 409 sem
      // saída nenhuma.
      _trackId = null;
      // Trecho fechado não recebe mais ponto: o que não subiu até aqui não
      // sobe mais, e guardá-lo seria prometer um envio que não existe.
      _core.drain();
      _gravando = _gravando.then((_) => _outbox.clear(journeyId));
      _set(RecorderStatus.idle);
    } on ApiError catch (e) {
      // O trecho continua aberto e os pontos continuam guardados: encerrar de
      // novo tenta os dois outra vez.
      _fail(e.message);
    }
  }

  /// Encerra um trecho que ficou aberto de uma sessão anterior.
  ///
  /// Existe porque sair da tela no meio da gravação (ou perder a rede ao
  /// encerrar) deixa o trecho `is_active` no servidor, e a próxima gravação
  /// responde 409. Sem isto, a jornada ficava sem NENHUMA forma de gravar de
  /// novo pelo app — um beco sem saída.
  ///
  /// É também por aqui que sobe o que ficou guardado no aparelho: antes de
  /// fechar o trecho, os pontos que a sessão interrompida não chegou a enviar
  /// vão para ele. Sem rede, nada é fechado nem apagado — a pessoa tenta de
  /// novo e não perde o trecho.
  Future<void> closeOrphanTrack() async {
    _set(RecorderStatus.finishing, error: '');
    try {
      final guardado = await _outbox.load(journeyId);
      final abertos = await _api.listTracks(journeyId);
      for (final t in abertos.where((t) => t.isActive)) {
        if (guardado != null && guardado.trackId == t.id) {
          await _enviarGuardado(t.id, guardado.points);
        }
        await _api.finishTrack(journeyId, t.id);
      }
      // O que sobrou guardado depois disto é de um trecho que já estava
      // fechado: não tem mais para onde ir.
      await _outbox.clear(journeyId);
      _guardados = 0;
      _trackId = null;
      _orphan = false;
      _set(RecorderStatus.idle);
    } on ApiError catch (e) {
      _fail(e.message);
    }
  }

  /// Sobe os pontos guardados, em lotes que o servidor aceita.
  ///
  /// Queda (sem rede, servidor fora) sobe como erro: quem chamou para, e os
  /// pontos ficam guardados para a próxima tentativa. Recusa (4xx: o trecho
  /// fechou, a jornada foi concluída) não vai mudar tentando de novo — os
  /// pontos são deixados para trás, senão a jornada ficaria presa para sempre
  /// num envio que o servidor nunca vai aceitar.
  Future<void> _enviarGuardado(String trackId, List<TrackSample> pontos) async {
    const lote = 500; // o servidor aceita até 1000 por requisição
    for (var i = 0; i < pontos.length; i += lote) {
      final fatia = pontos.skip(i).take(lote);
      try {
        await _api.addTrackPoints(
            journeyId, trackId, fatia.map((p) => p.toJson()).toList());
      } on ApiError catch (e) {
        if (e.isOutage) rethrow;
        return;
      }
    }
  }

  /// Há um trecho aberto que impede uma nova gravação?
  bool get hasOrphanTrack => _status == RecorderStatus.error && _orphan;
  bool _orphan = false;

  void _onSample(TrackSample s) {
    final out = _core.offer(s);
    _lastVerdict = out.verdict;
    // Guarda ANTES de pensar em enviar: o ponto aceito já está no aparelho
    // quando o lote sai, e continua lá se o envio nunca voltar.
    if (out.accepted) _guardar();
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
    _emVoo = batch;
    try {
      await _api.addTrackPoints(
          journeyId, id, batch.map((p) => p.toJson()).toList());
    } catch (_) {
      // Devolve para tentar de novo. Também quando o trecho está fechando: se
      // o fechamento falhar junto (sem rede), encerrar de novo reenvia; se
      // der certo, quem limpa o que sobrou é o `stop`.
      _core.restore(batch);
    }
    _emVoo = const [];
    // Deu certo: o lote sai do aparelho. Falhou: ele volta ao buffer e segue
    // guardado. Nos dois casos o que está em disco passa a ser o que falta.
    _guardar();
    // A resposta pode chegar depois de a tela ter saído: aí não há mais quem
    // avisar, e quem acerta o que ficou guardado é o `_encerrarAoSair`.
    if (!_descartado) notifyListeners();
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
    _descartado = true;
    _sub?.cancel();
    // Sair da tela no meio da gravação NÃO pode deixar o trecho aberto: a
    // próxima gravação bateria em 409. `dispose` é síncrono, então o
    // encerramento vai como melhor-esforço — e, se falhar, `closeOrphanTrack`
    // continua sendo a saída pela tela.
    final id = _trackId;
    if (id != null) {
      _trackId = null;
      unawaited(_encerrarAoSair(id));
    }
    super.dispose();
  }

  /// O encerramento de quem saiu da tela gravando: sobe o que faltava e fecha.
  ///
  /// Os pontos já estão guardados no aparelho. Se a rede não deixar enviá-los,
  /// o trecho fica ABERTO de propósito e eles ficam onde estão: na volta à
  /// jornada, "Encerrar a gravação anterior" envia e fecha. Fechar o trecho
  /// sem eles, como era, jogava fora o fim do percurso para sempre.
  Future<void> _encerrarAoSair(String id) async {
    try {
      // Um lote no ar termina primeiro: enviá-lo de novo daqui, sem saber se
      // ele chegou, duplicaria os pontos no trecho.
      await _inFlight;
    } catch (_) {}
    try {
      await _gravando;
      final faltando = _core.drain();
      // O que fica guardado passa a ser exatamente o que falta — sem o lote
      // que acabou de ser confirmado.
      await _outbox.save(journeyId, id, faltando);
      if (faltando.isNotEmpty) await _enviarGuardado(id, faltando);
      await _api.finishTrack(journeyId, id);
      await _outbox.clear(journeyId);
    } catch (_) {
      // Melhor esforço: o que não subiu continua guardado.
    }
  }
}
