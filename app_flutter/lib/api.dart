/// Cliente da API do Some Journey (FastAPI).
///
/// Mesmo contrato do app Expo (mobile/src/lib/api.ts): Bearer token, erros
/// como {"detail": ...}, timeout de 20s. Base URL via --dart-define=API_URL
/// (padrão: backend local).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:shared_preferences/shared_preferences.dart';

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

class Api {
  Api._();
  static final Api instance = Api._();

  String? _token;

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
  }

  bool get hasToken => _token != null;

  Future<void> _saveToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
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

  Future<dynamic> _request(
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
        'GET' => await http.get(uri, headers: headers).timeout(_timeout),
        'POST' => await http
            .post(uri, headers: headers, body: body == null ? null : jsonEncode(body))
            .timeout(_timeout),
        'PATCH' => await http
            .patch(uri, headers: headers, body: body == null ? null : jsonEncode(body))
            .timeout(_timeout),
        'DELETE' => await http.delete(uri, headers: headers).timeout(_timeout),
        _ => throw ArgumentError(method),
      };
    } on TimeoutException {
      throw ApiError(0, 'O servidor demorou a responder. Tente de novo.');
    } catch (_) {
      throw ApiError(0, 'Sem conexão com o servidor.');
    }
    if (r.statusCode >= 400) throw ApiError(r.statusCode, _detail(r));
    if (r.statusCode == 204 || r.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
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

  // ---- Memórias ----
  Future<List<Memory>> listMemories() async {
    final data = await _request('GET', '/memories', authed: true);
    if (data is! List) return [];
    return data.map((e) => Memory.fromJson(e as Map<String, dynamic>)).toList();
  }

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

  // ---- Jornadas ----
  Future<List<Journey>> listJourneys() async {
    final data = await _request('GET', '/journeys', authed: true);
    if (data is! List) return [];
    return data.map((e) => Journey.fromJson(e as Map<String, dynamic>)).toList();
  }

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
