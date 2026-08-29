/// Cliente da API do Some Journey (FastAPI).
///
/// Mesmo contrato do app Expo (mobile/src/lib/api.ts): Bearer token, erros
/// como {"detail": ...}, timeout de 20s. Base URL via --dart-define=API_URL
/// (padrão: backend local).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:shared_preferences/shared_preferences.dart';

import 'features/profile/profile_models.dart';
import 'models.dart';

const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://127.0.0.1:8000');
const _timeout = Duration(seconds: 20);
const _tokenKey = 'sj_access_token';

class ApiError implements Exception {
  final int status;
  final String message;
  ApiError(this.status, this.message);
  bool get isUnauthorized => status == 401;
  bool get isNotFound => status == 404 || status == 422;
  @override
  String toString() => message;
}

/// Nome do header em que o backend devolve o cursor da próxima página.
const nextCursorHeader = 'X-Next-Cursor';

/// Resultado de uma listagem paginada por keyset.
///
/// [nextCursor] nulo significa que esta é a última página — é assim que o
/// backend sinaliza o fim, e não com uma contagem total.
class Page<T> {
  final List<T> items;
  final String? nextCursor;

  const Page(this.items, this.nextCursor);
  const Page._empty()
      : items = const [],
        nextCursor = null;

  bool get hasMore => nextCursor != null;
}

class Api {
  Api._();
  static final Api instance = Api._();

  String? _token;

  /// Cliente HTTP. Injetável para que o contrato com o backend — paginação por
  /// cursor, tradução de erro, timeout — possa ser testado sem rede nem
  /// servidor de pé. Em produção é o cliente padrão do pacote http.
  http.Client _client = http.Client();

  /// Troca o cliente HTTP (testes). Devolve o anterior, para restaurar depois.
  @visibleForTesting
  http.Client swapClient(http.Client client) {
    final old = _client;
    _client = client;
    return old;
  }

  /// Esquece a sessão em memória (testes), sem tocar no armazenamento.
  @visibleForTesting
  void debugSetToken(String? token) => _token = token;

  /// Lê a sessão salva. Falha de armazenamento NÃO derruba o app: sem token, o
  /// bootstrap manda para o login (ver _Bootstrap em main.dart).
  Future<void> loadToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenKey);
    } catch (_) {
      _token = null;
    }
  }

  bool get hasToken => _token != null;

  /// Guarda (ou apaga) a sessão. O token vale EM MEMÓRIA na hora — a persistência
  /// é best-effort: se o armazenamento estiver indisponível (aba privada, política
  /// de site na web), o login continua funcionando nesta sessão; ele só não
  /// sobrevive a um recarregamento. Antes, uma exceção aqui fazia um login
  /// bem-sucedido parecer que falhou.
  Future<void> _saveToken(String? token) async {
    _token = token;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (token == null) {
        await prefs.remove(_tokenKey);
      } else {
        await prefs.setString(_tokenKey, token);
      }
    } catch (_) {
      // Sessão só em memória — aceitável e melhor que quebrar o fluxo.
    }
  }

  Map<String, String> _headers({bool json = true, bool authed = false}) => {
        if (json) 'Content-Type': 'application/json',
        if (authed && _token != null) 'Authorization': 'Bearer $_token',
      };

  /// Extrai a mensagem do corpo {"detail": ...} (string ou lista do Pydantic).
  String _detail(http.Response r) {
    try {
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      final detail = body['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) return first['msg'] as String;
      }
    } catch (_) {}
    return 'Erro inesperado (${r.statusCode}).';
  }

  /// Envia a requisição e devolve a RESPOSTA inteira.
  ///
  /// Existe separado de [_request] porque as listagens precisam do header
  /// `X-Next-Cursor`, que se perde quando só o corpo é devolvido.
  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    bool authed = false,
  }) async {
    final uri = Uri.parse('$apiUrl$path');
    late http.Response r;
    try {
      final headers = _headers(json: body != null, authed: authed);
      r = switch (method) {
        'GET' => await _client.get(uri, headers: headers).timeout(_timeout),
        'POST' => await _client
            .post(uri, headers: headers, body: body == null ? null : jsonEncode(body))
            .timeout(_timeout),
        'PATCH' => await _client
            .patch(uri, headers: headers, body: body == null ? null : jsonEncode(body))
            .timeout(_timeout),
        'DELETE' => await _client.delete(uri, headers: headers).timeout(_timeout),
        _ => throw ArgumentError(method),
      };
    } on TimeoutException {
      throw ApiError(0, 'O servidor demorou a responder. Tente de novo.');
    } catch (_) {
      throw ApiError(0, 'Sem conexão com o servidor.');
    }
    if (r.statusCode >= 400) throw ApiError(r.statusCode, _detail(r));
    return r;
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    bool authed = false,
  }) async {
    final r = await _send(method, path, body: body, authed: authed);
    if (r.statusCode == 204 || r.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// Acrescenta `limit`/`cursor` à rota, já codificados.
  ///
  /// O cursor é opaco (base64url com `-`, `_` e possível `=`), então ele PRECISA
  /// passar por codificação de querystring — concatenar na mão corromperia o
  /// padding e o backend responderia 400.
  String _paged(String path, int? limit, String? cursor) {
    final q = <String, String>{
      if (limit != null) 'limit': '$limit',
      'cursor': ?cursor,
    };
    if (q.isEmpty) return path;
    return '$path?${Uri(queryParameters: q).query}';
  }

  /// Uma página de listagem: os itens e o cursor da PRÓXIMA página.
  ///
  /// O backend devolve um array JSON puro e sinaliza a continuação pelo header
  /// `X-Next-Cursor`; sem o header, acabou.
  Future<Page<T>> _page<T>(
    String path,
    T Function(Map<String, dynamic>) parse, {
    int? limit,
    String? cursor,
  }) async {
    final r = await _send('GET', _paged(path, limit, cursor), authed: true);
    final data = r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (data is! List) return const Page._empty();
    // O pacote http normaliza nomes de header para minúsculas.
    final next = r.headers[nextCursorHeader.toLowerCase()];
    return Page(
      data.map((e) => parse(e as Map<String, dynamic>)).toList(),
      (next != null && next.isNotEmpty) ? next : null,
    );
  }

  // ---- Auth ----
  Future<void> register(String name, String email, String password) =>
      _request('POST', '/auth/register', body: {'name': name, 'email': email, 'password': password});

  Future<void> login(String email, String password) async {
    final data = await _request('POST', '/auth/login', body: {'email': email, 'password': password});
    await _saveToken(data['access_token'] as String);
  }

  Future<void> logout() => _saveToken(null);

  Future<void> changePassword(String current, String next) => _request(
        'POST',
        '/auth/change-password',
        body: {'current_password': current, 'new_password': next},
        authed: true,
      );

  /// Pede o link de recuperação de senha. O backend responde SEMPRE 202 com a
  /// mesma mensagem genérica — exista a conta ou não (anti-enumeração). Portanto
  /// a UI nunca deve afirmar que "o e-mail existe": só que, se existir, o link foi
  /// enviado.
  Future<void> forgotPassword(String email) =>
      _request('POST', '/auth/forgot-password', body: {'email': email});

  /// Conclui a recuperação com o token recebido por e-mail (uso único, com
  /// validade). Token inválido/expirado/usado volta como ApiError 400.
  Future<void> resetPassword(String token, String newPassword) => _request(
        'POST',
        '/auth/reset-password',
        body: {'token': token, 'new_password': newPassword},
      );

  /// Perfil COMPLETO da tela (GET /me/profile): identidade, estatísticas,
  /// passaporte, última aventura e jornada atual — tudo agregado no backend.
  /// O cliente NÃO calcula nada nem baixa memórias para contar.
  Future<Profile> getProfile() async =>
      Profile.fromJson(await _request('GET', '/me/profile', authed: true));

  /// Edita a identidade pública (nome, @username, bio). PARCIAL: só o que for
  /// enviado muda. Devolve o Perfil já atualizado — sem segunda chamada.
  /// 422 = @username inválido/reservado (a mensagem já vem pronta em pt-BR);
  /// 409 = @username em uso por outra pessoa.
  Future<Profile> updateProfile({String? name, String? username, String? bio}) async =>
      Profile.fromJson(await _request('PATCH', '/me/profile', authed: true, body: {
        'name': ?name,
        'username': ?username,
        'bio': ?bio,
      }));

  /// Envia a foto de perfil e devolve o Perfil atualizado (com a URL assinada).
  Future<Profile> setAvatar(List<int> bytes, String filename, String mimeType) async =>
      Profile.fromJson(await _uploadJson('/me/avatar', bytes, filename, mimeType));

  /// Remove a foto de perfil (idempotente): volta a mostrar as iniciais.
  Future<Profile> removeAvatar() async =>
      Profile.fromJson(await _request('DELETE', '/me/avatar', authed: true));

  /// Perfil do usuário autenticado (GET /auth/me). O backend nunca devolve
  /// hash de senha — só os campos públicos da conta.
  Future<UserProfile> me() async =>
      UserProfile.fromJson(await _request('GET', '/auth/me', authed: true));

  // ---- Memórias ----
  /// Uma página de memórias, da mais recente para a mais antiga.
  ///
  /// Passe [cursor] com o `nextCursor` da página anterior para continuar. Sem
  /// paginar, a timeline mostrava só as 30 primeiras e escondia o resto sem
  /// avisar — num app de preservar memórias, o pior tipo de falha.
  Future<Page<Memory>> listMemories({int? limit, String? cursor}) =>
      _page('/memories', Memory.fromJson, limit: limit, cursor: cursor);

  Future<Memory> getMemory(String id) async =>
      Memory.fromJson(await _request('GET', '/memories/$id', authed: true));

  Future<Memory> createMemory(Map<String, dynamic> payload) async =>
      Memory.fromJson(await _request('POST', '/memories', body: payload, authed: true));

  Future<Memory> updateMemory(String id, Map<String, dynamic> patch) async =>
      Memory.fromJson(await _request('PATCH', '/memories/$id', body: patch, authed: true));

  Future<void> deleteMemory(String id) => _request('DELETE', '/memories/$id', authed: true);

  Future<void> addMemoryImage(String id, List<int> bytes, String filename, String mimeType) =>
      _upload('/memories/$id/images', bytes, filename, mimeType);

  Future<void> deleteMemoryImage(String memoryId, String imageId) =>
      _request('DELETE', '/memories/$memoryId/images/$imageId', authed: true);

  /// Upload multipart que DEVOLVE o corpo decodificado (o `_upload` abaixo
  /// descarta a resposta; aqui o servidor devolve o recurso atualizado).
  Future<dynamic> _uploadJson(
      String path, List<int> bytes, String filename, String mimeType) async {
    final r = await _sendMultipart(path, bytes, filename, mimeType);
    if (r.statusCode >= 400) throw ApiError(r.statusCode, _detail(r));
    if (r.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<http.Response> _sendMultipart(
      String path, List<int> bytes, String filename, String mimeType) async {
    final req = http.MultipartRequest('POST', Uri.parse('$apiUrl$path'));
    req.headers.addAll(_headers(json: false, authed: true));
    final parts = mimeType.split('/');
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: parts.length == 2 ? MediaType(parts[0], parts[1]) : null,
    ));
    try {
      return await http.Response.fromStream(await req.send().timeout(_timeout));
    } on TimeoutException {
      throw ApiError(0, 'O upload demorou demais. Tente de novo.');
    } catch (_) {
      throw ApiError(0, 'Sem conexão com o servidor.');
    }
  }

  Future<void> _upload(String path, List<int> bytes, String filename, String mimeType) async {
    final req = http.MultipartRequest('POST', Uri.parse('$apiUrl$path'));
    req.headers.addAll(_headers(json: false, authed: true));
    final parts = mimeType.split('/');
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: parts.length == 2 ? MediaType(parts[0], parts[1]) : null,
    ));
    late http.Response r;
    try {
      r = await http.Response.fromStream(await req.send().timeout(_timeout));
    } on TimeoutException {
      throw ApiError(0, 'O upload demorou demais. Tente de novo.');
    } catch (_) {
      throw ApiError(0, 'Sem conexão com o servidor.');
    }
    if (r.statusCode >= 400) throw ApiError(r.statusCode, _detail(r));
  }

  // ---- Percurso real (GPS) ----

  /// Abre um trecho de gravação. O backend recusa com 409 se já houver um
  /// trecho aberto nesta jornada — dois gravadores simultâneos embaralhariam
  /// a ordem dos pontos.
  Future<JourneyTrack> startTrack(String journeyId, {String source = 'gps_live'}) async =>
      JourneyTrack.fromJson(await _request(
        'POST',
        '/journeys/$journeyId/tracks/start',
        body: {'source': source},
        authed: true,
      ));

  /// Envia um LOTE de pontos. O backend aceita até 1000 por requisição.
  Future<void> addTrackPoints(
    String journeyId,
    String trackId,
    List<Map<String, dynamic>> points,
  ) =>
      _request(
        'POST',
        '/journeys/$journeyId/tracks/$trackId/points',
        body: {'points': points},
        authed: true,
      );

  Future<JourneyTrack> finishTrack(String journeyId, String trackId) async =>
      JourneyTrack.fromJson(await _request(
        'POST',
        '/journeys/$journeyId/tracks/$trackId/finish',
        authed: true,
      ));

  Future<List<JourneyTrack>> listTracks(String journeyId) async {
    final data = await _request('GET', '/journeys/$journeyId/tracks', authed: true);
    if (data is! List) return [];
    return data
        .map((e) => JourneyTrack.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteTrack(String journeyId, String trackId) =>
      _request('DELETE', '/journeys/$journeyId/tracks/$trackId', authed: true);

  /// Mapa da jornada: percurso real + memórias + rastro simbólico.
  Future<JourneyMap> journeyMap(String journeyId) async =>
      JourneyMap.fromJson(
          await _request('GET', '/journeys/$journeyId/map', authed: true));

  // ---- Jornadas ----
  /// Uma página de jornadas, da mais recente para a mais antiga.
  Future<Page<Journey>> listJourneys({int? limit, String? cursor}) =>
      _page('/journeys', Journey.fromJson, limit: limit, cursor: cursor);

  Future<JourneyDetail> getJourney(String id) async =>
      JourneyDetail.fromJson(await _request('GET', '/journeys/$id', authed: true));

  Future<Journey> createJourney(Map<String, dynamic> payload) async =>
      Journey.fromJson(await _request('POST', '/journeys', body: payload, authed: true));

  Future<Journey> updateJourney(String id, Map<String, dynamic> patch) async =>
      Journey.fromJson(await _request('PATCH', '/journeys/$id', body: patch, authed: true));

  Future<void> deleteJourney(String id) => _request('DELETE', '/journeys/$id', authed: true);

  Future<Journey> _lifecycle(String id, String action) async =>
      Journey.fromJson(await _request('POST', '/journeys/$id/$action', authed: true));

  Future<Journey> startJourney(String id) => _lifecycle(id, 'start');
  Future<Journey> pauseJourney(String id) => _lifecycle(id, 'pause');
  Future<Journey> resumeJourney(String id) => _lifecycle(id, 'resume');
  Future<Journey> finishJourney(String id) => _lifecycle(id, 'finish');

  Future<JourneyDetail> addJourneyPoint(String id, String memoryId) async => JourneyDetail.fromJson(
      await _request('POST', '/journeys/$id/points', body: {'memory_id': memoryId}, authed: true));

  Future<JourneyDetail> createMemoryInJourney(String id, Map<String, dynamic> payload) async =>
      JourneyDetail.fromJson(
          await _request('POST', '/journeys/$id/memories', body: payload, authed: true));

  Future<void> unlinkJourneyPoint(String id, String memoryId) =>
      _request('DELETE', '/journeys/$id/points/$memoryId', authed: true);

  Future<JourneyDetail> reorderJourneyPoints(String id, List<String> memoryIds) async =>
      JourneyDetail.fromJson(await _request('PATCH', '/journeys/$id/points/reorder',
          body: {'memory_ids': memoryIds}, authed: true));

  // ---- Mapa ----
  Future<MapResponse> getMap() async =>
      MapResponse.fromJson(await _request('GET', '/map', authed: true));
}
