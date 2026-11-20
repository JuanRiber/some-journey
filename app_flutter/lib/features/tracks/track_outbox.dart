/// Os pontos de GPS que ainda não chegaram ao servidor, guardados NO APARELHO.
///
/// O gravador sobe o percurso em lotes, e entre um lote e outro os pontos
/// existiam só na memória do app. Se o app morresse ali — o sistema matou o
/// processo, a aba foi fechada, a bateria acabou — o trecho andado desde o
/// último envio sumia sem deixar rastro: o traço simplesmente terminava antes.
/// Com rede ruim era pior, porque os lotes que falhavam iam se acumulando na
/// mesma memória.
///
/// Aqui cada ponto aceito é escrito em disco assim que entra, junto com o
/// trecho a que pertence, e sai quando o servidor confirma. O que sobrar de
/// uma gravação interrompida é enviado na próxima vez que a pessoa abrir a
/// jornada (ver `TrackRecorder.closeOrphanTrack`).
///
/// São coordenadas de onde a pessoa esteve: ficam só até subirem, e sair da
/// conta apaga tudo ([PrefsTrackOutbox.clearAll]).
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'track_domain.dart';

/// O que ficou por enviar de um trecho.
class PendingTrack {
  const PendingTrack({required this.trackId, required this.points});

  /// O trecho, no servidor, a que os pontos pertencem. Sem ele os pontos não
  /// têm para onde ir: um trecho novo seria outro percurso.
  final String trackId;
  final List<TrackSample> points;
}

/// O contrato de quem guarda. Existe para o gravador ser testado sem disco.
abstract class TrackOutbox {
  /// O que ficou por enviar nesta jornada, ou null. NUNCA lança.
  Future<PendingTrack?> load(String journeyId);

  /// Substitui o que está guardado para a jornada. Lista vazia apaga.
  /// NUNCA lança: gravar o percurso não pode parar porque o disco recusou.
  Future<void> save(String journeyId, String trackId, List<TrackSample> points);

  Future<void> clear(String journeyId);
}

/// `shared_preferences`: arquivo do app no celular, `localStorage` na web.
class PrefsTrackOutbox implements TrackOutbox {
  const PrefsTrackOutbox();

  static const _prefixo = 'sj_track_outbox_';

  @override
  Future<PendingTrack?> load(String journeyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bruto = prefs.getString('$_prefixo$journeyId');
      if (bruto == null) return null;
      final dados = jsonDecode(bruto) as Map<String, dynamic>;
      final pontos = [
        for (final p in dados['points'] as List)
          TrackSample.fromJson(p as Map<String, dynamic>),
      ];
      if (pontos.isEmpty) return null;
      return PendingTrack(trackId: dados['track_id'] as String, points: pontos);
    } catch (_) {
      // Ilegível (versão antiga, gravação cortada no meio): vale como vazio.
      return null;
    }
  }

  @override
  Future<void> save(
      String journeyId, String trackId, List<TrackSample> points) async {
    if (points.isEmpty) return clear(journeyId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefixo$journeyId',
        jsonEncode({
          'track_id': trackId,
          'points': [for (final p in points) p.toJson()],
        }),
      );
    } catch (_) {
      // Sem disco, o percurso continua valendo em memória.
    }
  }

  @override
  Future<void> clear(String journeyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefixo$journeyId');
    } catch (_) {}
  }

  /// Apaga o que ficou por enviar de TODAS as jornadas. É o que sair da conta
  /// chama: o próximo a usar o aparelho não herda por onde a pessoa andou.
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final chave in prefs.getKeys().toList()) {
        if (chave.startsWith(_prefixo)) await prefs.remove(chave);
      }
    } catch (_) {}
  }
}
