/// Cliente da API do Some Journey (FastAPI).
///
/// Mesmo contrato do app Expo (mobile/src/lib/api.ts): Bearer token, erros
/// como {"detail": ...}, e um teto de espera maior para upload que para leitura.
/// Base URL via --dart-define=API_URL (padrão: backend local).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'features/auth/token_store.dart';
import 'features/collection/collection_domain.dart';
import 'features/phases/phase_domain.dart';
import 'features/profile/profile_models.dart';
import 'features/tracks/track_outbox.dart';
import 'models.dart';

const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://127.0.0.1:8000');

/// Quanto esperar por uma resposta antes de desistir.
///
/// Era 20s — herdado do cliente Expo, que já chutava "~20s por causa do cold
/// start". O chute ficou curto: a API roda no plano FREE do Render, que desliga
/// a instância quando ela fica ociosa, e o próprio painel do Render avisa que a
/// primeira requisição depois disso "pode atrasar as requisições em 50 segundos
/// ou mais". Ou seja, 20s não era um teto apertado — era a garantia de que a
/// primeira tela depois de qualquer pausa SEMPRE falharia, mesmo com o servidor
/// inteiro e a ponto de responder.
///
/// O que medimos aqui: com o servidor quente, 0,39s. Com ele desligado, 90s sem
/// um único byte de volta. Então o teto precisa ficar entre dois erros opostos:
/// abaixo dos 50s avisados, falhar é certo; muito acima, a pessoa fica olhando
/// um spinner por uma falha que já estava decidida — porque quando o servidor
/// está mesmo fora, nada chega, e esperar mais só adia a má notícia.
///
/// 75s é meia vez acima do piso que o Render avisa (margem para o "ou mais", já
/// que 50s é o começo da faixa, não o fim) e ainda abaixo dos 90s em que vimos
/// silêncio completo. Na prática a espera longa acontece UMA vez por período de
/// ociosidade: depois que a instância sobe, a mesma chamada volta a custar
/// décimos de segundo.
const apiTimeout = Duration(seconds: 75);

/// Teto do upload, separado de propósito.
///
/// O relógio do upload não cobre só a espera pelo servidor: cobre também os
/// bytes subindo. Uma foto num uplink móvel ruim leva dezenas de segundos por
/// si só, e isso se SOMA ao cold start — o upload pode ser justamente a primeira
/// requisição depois da pausa. Usar [apiTimeout] aqui cancelaria envios que
/// estavam progredindo bem. O cliente Expo já tratava os dois casos como
/// grandezas diferentes (`API_TIMEOUT_MS * 3`); manter a proporção.
const apiUploadTimeout = Duration(minutes: 3);

/// Natureza da falha, para a tela saber que notícia dar.
///
/// Um 500 e um 422 chegavam aqui como a mesma coisa — um status e um texto — e
/// a tela mostrava o texto. Só que "o servidor caiu" e "faltou o título" pedem
/// reações opostas: a primeira passa sozinha e vale tentar de novo, a segunda
/// só sai do lugar se a pessoa corrigir algo. Sem essa distinção o app oferecia
/// "Tentar de novo" para erros que nunca vão passar.
enum ApiFailure {
  /// Não chegou a sair: sem rede, DNS que não resolve, conexão recusada.
  offline,

  /// Saiu, e ninguém respondeu dentro do tempo.
  timeout,

  /// O servidor está de pé mas não está atendendo — 502, 503, 504. É o formato
  /// de um deploy no ar, de uma manutenção, ou do contêiner que morreu atrás da
  /// borda: a borda responde, o serviço não.
  unavailable,

  /// O servidor recebeu, tentou e quebrou (500 e os demais 5xx).
  serverError,

  /// A requisição é que não serve (4xx): sessão expirada, campo inválido,
  /// recurso que não existe.
  request,
}

class ApiError implements Exception {
  final int status;
  final String message;

  /// Deduzida do status quando não informada, para que os pontos que já
  /// levantavam `ApiError` continuem corretos sem mudar de assinatura.
  final ApiFailure kind;

  /// Quanto o servidor pediu para esperar (header `Retry-After`), quando pede.
  /// É o único sinal de manutenção programada que o HTTP oferece de fato.
  final Duration? retryAfter;

  ApiError(this.status, this.message, {ApiFailure? kind, this.retryAfter})
      : kind = kind ?? kindOf(status);

  static ApiFailure kindOf(int status) {
    if (status == 0) return ApiFailure.offline;
    if (status == 502 || status == 503 || status == 504) return ApiFailure.unavailable;
    if (status >= 500) return ApiFailure.serverError;
    return ApiFailure.request;
  }

  bool get isUnauthorized => status == 401;
  bool get isNotFound => status == 404 || status == 422;

  /// A culpa não é do que a pessoa pediu — é do servidor ou do caminho até ele.
  /// Ou seja: tentar de novo é uma ação que faz sentido oferecer.
  bool get isOutage => kind != ApiFailure.request;

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

  /// O que troca o access token vencido por um novo (POST /auth/refresh). Vale
  /// UMA troca: cada renovação devolve o sucessor. Nulo em sessão antiga,
  /// aberta antes de existir renovação — essa vale até o access token vencer.
  String? _refreshToken;

  /// Muda quando a SESSÃO muda (entrar, sair, restaurar) e fica igual quando
  /// ela só é renovada. Ver [sessionTag].
  Object? _sessao;

  /// Avisa que este app MUDOU algo no servidor — uma escrita que deu certo.
  ///
  /// As abas guardam o estado (não recarregam ao trocar), então quem mostra
  /// dados precisa saber quando eles ficaram velhos: a memória criada pelo
  /// botão central tem de aparecer na timeline e no atlas que estão por baixo.
  /// O número em si não importa; importa que ele muda. As rotas de `/auth/`
  /// ficam de fora — entrar ou trocar de senha não muda o acervo.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  void _mudou(String path) {
    if (!path.startsWith('/auth/')) changes.value++;
  }

  /// Identifica a sessão atual sem expor o token: dois valores iguais são a
  /// mesma sessão. É o que deixa um cache de tela saber se ainda é da pessoa
  /// que está logada (ver features/sync/session_cache.dart).
  ///
  /// NÃO é o token: ele troca a cada hora, na renovação, e a sessão continua
  /// sendo a mesma — um cache que se esvaziasse a cada renovação reabriria as
  /// telas em esqueleto sem ninguém ter saído.
  Object? get sessionTag => _token == null ? null : _sessao;

  /// Onde a sessão fica guardada: o cofre do sistema no celular, o
  /// `localStorage` na web (ver features/auth/token_store.dart).
  TokenStore _store = TokenStore.platform();

  /// Troca o cofre da sessão (testes). Devolve o anterior, para restaurar.
  @visibleForTesting
  TokenStore swapTokenStore(TokenStore store) {
    final old = _store;
    _store = store;
    return old;
  }

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

  /// Define a sessão em memória (testes), sem tocar no armazenamento.
  @visibleForTesting
  void debugSetToken(String? token, {String? refreshToken}) {
    _token = token;
    _refreshToken = token == null ? null : refreshToken;
    _sessao = token;
  }

  /// Lê a sessão salva. Falha de armazenamento NÃO derruba o app: sem token, o
  /// bootstrap manda para o login (ver _Bootstrap em main.dart).
  Future<void> loadToken() async {
    final guardada = await _store.read();
    _token = guardada?.accessToken;
    _refreshToken = guardada?.refreshToken;
    _sessao = guardada == null ? null : Object();
  }

  bool get hasToken => _token != null;

  /// Guarda (ou apaga) a sessão. Ela vale EM MEMÓRIA na hora — a persistência
  /// é best-effort: se o armazenamento estiver indisponível (aba privada,
  /// política de site na web, cofre recusando), o login continua funcionando
  /// nesta sessão; ele só não sobrevive a um recarregamento. Antes, uma exceção
  /// aqui fazia um login bem-sucedido parecer que falhou.
  ///
  /// [nova] é falso só na renovação: os tokens mudam, a sessão é a mesma.
  Future<void> _saveSession(String? access,
      {String? refresh, bool nova = true}) async {
    _token = access;
    _refreshToken = access == null ? null : refresh;
    if (nova) _sessao = access == null ? null : Object();
    await _store.write(access == null
        ? null
        : StoredSession(accessToken: access, refreshToken: refresh));
  }

  /// Guarda o par que o servidor acabou de emitir (login, Google, renovação).
  Future<void> _adotar(dynamic data, {bool nova = true}) => _saveSession(
        data['access_token'] as String,
        refresh: data['refresh_token'] as String?,
        nova: nova,
      );

  Map<String, String> _headers({bool json = true, bool authed = false}) => {
        if (json) 'Content-Type': 'application/json',
        if (authed && _token != null) 'Authorization': 'Bearer $_token',
      };

  /// Traduz uma resposta de erro no `ApiError` que a tela vai mostrar.
  ///
  /// O corpo do servidor só é aproveitado em 4xx, onde a API escreve frases
  /// pensadas para quem está usando o app ("Essa jornada já tem um trecho
  /// aberto"). Em 5xx o que chega é "Internal Server Error" — ou a página HTML
  /// que o proxy devolve quando o contêiner não sobe. É texto de
  /// infraestrutura, em inglês, que não diz nada a quem está do outro lado e
  /// ainda conta o que quebrou. Nesses casos a frase é nossa.
  /// 503 numa rota de imagem NÃO é servidor fora do ar.
  ///
  /// O backend separa os dois casos de propósito — 502 quando a comunicação
  /// com o storage falha, 503 quando ele nem está configurado — e a tela
  /// estava contando a mesma história para os dois. Dizer "fora do ar" manda
  /// a pessoa esperar por algo que não muda sozinho, e ainda acusa de queda um
  /// servidor que está de pé respondendo todo o resto.
  static bool _semStorage(http.Response r) {
    final caminho = r.request?.url.path ?? '';
    return caminho.endsWith('/images') ||
        caminho.endsWith('/avatar') ||
        caminho.endsWith('/cover');
  }

  ApiError _errorFor(http.Response r) {
    final kind = ApiError.kindOf(r.statusCode);
    final espera = _retryAfter(r);
    return switch (kind) {
      ApiFailure.unavailable => ApiError(
          r.statusCode,
          _semStorage(r)
              ? 'As fotos estão indisponíveis aqui: o armazenamento de imagens '
                  'não está configurado. O resto da memória salva normalmente.'
              : 'O servidor está fora do ar no momento. Tente de novo ${_quando(espera)}.',
          kind: kind,
          retryAfter: espera,
        ),
      ApiFailure.serverError => ApiError(
          r.statusCode,
          'Algo quebrou do nosso lado ao atender seu pedido. Tente de novo em instantes.',
          kind: kind,
        ),
      _ => ApiError(r.statusCode, _detail(r), kind: kind),
    };
  }

  /// Lê o `Retry-After` em SEGUNDOS.
  ///
  /// O header também admite uma data HTTP, que é ignorada de propósito: parsear
  /// data depende de `dart:io`, que não existe no alvo web, e um valor mal lido
  /// viraria uma promessa errada na tela. Sem número, a frase fica genérica.
  Duration? _retryAfter(http.Response r) {
    final bruto = r.headers['retry-after'];
    if (bruto == null) return null;
    final segundos = int.tryParse(bruto.trim());
    if (segundos == null || segundos <= 0) return null;
    return Duration(seconds: segundos);
  }

  /// A espera em palavras. Sem número do servidor, "em instantes" — que promete
  /// pouco de propósito, porque nós não sabemos.
  String _quando(Duration? espera) {
    if (espera == null) return 'em instantes';
    if (espera.inMinutes < 1) return 'em alguns segundos';
    if (espera.inMinutes < 60) {
      final m = espera.inMinutes;
      return 'em $m ${m == 1 ? 'minuto' : 'minutos'}';
    }
    final h = espera.inHours;
    return 'em $h ${h == 1 ? 'hora' : 'horas'}';
  }

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

  /// Uma ida ao servidor, sem julgar o status. Só o transporte vira exceção.
  Future<http.Response> _despachar(
    String method,
    String path, {
    Object? body,
    bool authed = false,
  }) async {
    final uri = Uri.parse('$apiUrl$path');
    try {
      final headers = _headers(json: body != null, authed: authed);
      return switch (method) {
        'GET' => await _client.get(uri, headers: headers).timeout(apiTimeout),
        'POST' => await _client
            .post(uri, headers: headers, body: body == null ? null : jsonEncode(body))
            .timeout(apiTimeout),
        'PATCH' => await _client
            .patch(uri, headers: headers, body: body == null ? null : jsonEncode(body))
            .timeout(apiTimeout),
        'DELETE' => await _client.delete(uri, headers: headers).timeout(apiTimeout),
        _ => throw ArgumentError(method),
      };
    } on TimeoutException {
      throw ApiError(0, 'O servidor demorou a responder. Tente de novo.',
          kind: ApiFailure.timeout);
    } on ArgumentError {
      rethrow;
    } catch (_) {
      throw ApiError(0, 'Sem conexão com o servidor.');
    }
  }

  /// Envia a requisição e devolve a RESPOSTA inteira.
  ///
  /// Existe separado de [_request] porque as listagens precisam do header
  /// `X-Next-Cursor`, que se perde quando só o corpo é devolvido.
  ///
  /// Sessão vencida não chega a quem chamou: o 401 de sessão vira uma
  /// renovação e a MESMA requisição sai de novo, com o token novo (ver
  /// [_renovar]). Só quando a renovação diz que a sessão acabou é que o 401
  /// sobe — e aí cada tela faz o que sempre fez com ele: manda para o login.
  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    bool authed = false,
  }) async {
    final usado = _token;
    var r = await _despachar(method, path, body: body, authed: authed);
    if (authed && _sessaoVencida(r, path) && await _renovar(usado)) {
      r = await _despachar(method, path, body: body, authed: authed);
    }
    if (r.statusCode >= 400) throw _errorFor(r);
    if (method != 'GET') _mudou(path);
    return r;
  }

  /// Este 401 é de SESSÃO (token vencido ou revogado), e não de outra coisa?
  ///
  /// A API responde 401 também para "a senha atual está incorreta", na troca
  /// de senha. Renovar a sessão ali seria gastar um refresh token para repetir
  /// a mesma senha errada — e contar duas tentativas no limite do servidor. O
  /// 401 de sessão é o único que vem com `WWW-Authenticate`; onde o header não
  /// é visível (um servidor que ainda não o expõe ao navegador), o caminho
  /// decide: fora de `/auth/`, todo 401 é de sessão.
  bool _sessaoVencida(http.Response r, String path) =>
      r.statusCode == 401 &&
      (r.headers.containsKey('www-authenticate') || !path.startsWith('/auth/'));

  Future<bool>? _renovando;

  /// Renova a sessão. Devolve se há um token novo para tentar de novo.
  ///
  /// [recusado] é o access token que acabou de tomar 401. Várias requisições
  /// vencem juntas — uma tela abre e dispara três — e todas chegam aqui: a
  /// primeira renova, as outras esperam a MESMA renovação. O refresh token
  /// vale uma troca só; três trocas em paralelo com o mesmo token seriam duas
  /// recusas.
  ///
  /// Lança `ApiError` quando não deu para saber (sem rede, servidor fora, 429):
  /// a sessão pode estar inteira, e tratar isso como "sessão acabou" mandaria
  /// para o login alguém que só passou por um túnel.
  Future<bool> _renovar(String? recusado) => _renovando ??=
      _renovarUmaVez(recusado).whenComplete(() => _renovando = null);

  Future<bool> _renovarUmaVez(String? recusado) async {
    // Já foi renovada enquanto esta requisição estava no ar.
    if (_token != null && _token != recusado) return true;

    // Outra aba do navegador pode ter renovado: o par novo está guardado, e o
    // que esta aba tem em memória já foi trocado. Usar o refresh token velho
    // pareceria reuso ao servidor, que derrubaria a sessão das duas.
    final guardada = await _store.read();
    if (_token != null && guardada != null && guardada.accessToken != recusado) {
      _token = guardada.accessToken;
      _refreshToken = guardada.refreshToken;
      return true;
    }

    final refresh = _refreshToken;
    if (refresh == null) return false;

    final r = await _despachar('POST', '/auth/refresh',
        body: {'refresh_token': refresh});
    if (r.statusCode == 200) {
      await _adotar(jsonDecode(utf8.decode(r.bodyBytes)), nova: false);
      return true;
    }
    if (r.statusCode == 429 || r.statusCode >= 500) throw _errorFor(r);
    // 401 (vencido, revogado, reusado) e qualquer outro 4xx: a sessão acabou.
    // Esquecê-la aqui é o que impede o app de reabrir no atlas, na próxima
    // vez, só para cada tela tomar 401 de novo.
    await _saveSession(null);
    return false;
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
  String _paged(String path, int? limit, String? cursor,
          {String? phaseId, MemoryFilter? filter}) =>
      _query(path, {
        if (limit != null) 'limit': '$limit',
        'cursor': ?cursor,
        'life_phase_id': ?phaseId,
        ...?filter?.toQuery(),
      });

  /// Acrescenta a querystring à rota, codificada — ou devolve a rota pura.
  String _query(String path, Map<String, String> q) {
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
    String? phaseId,
    MemoryFilter? filter,
  }) async {
    final r = await _send(
        'GET', _paged(path, limit, cursor, phaseId: phaseId, filter: filter),
        authed: true);
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
    await _adotar(data);
  }

  /// Entra com o Google: manda o `id_token` e recebe a NOSSA sessão.
  ///
  /// O app não decide quem a pessoa é — quem verifica a assinatura do token,
  /// confere o `aud` e vincula (ou cria) a conta é o backend. Aqui só o
  /// transporte.
  ///
  /// 503 = o servidor não tem GOOGLE_CLIENT_ID configurado; 401 = token
  /// recusado. Os dois chegam como `ApiError` com a mensagem pronta.
  Future<void> loginWithGoogle(String idToken) async {
    final data = await _request('POST', '/auth/google', body: {'id_token': idToken});
    await _adotar(data);
  }

  /// Sai: esquece a sessão AQUI na hora e avisa o servidor em seguida.
  ///
  /// A ordem é a regra. Sair não pode depender de rede — quem toca em "Sair"
  /// num metrô tem de sair — então o aparelho esquece primeiro e o aviso
  /// (POST /auth/logout, que revoga o refresh token) vai sem ninguém esperar
  /// por ele. Se não chegar, o refresh token morre sozinho na validade.
  ///
  /// Os pontos de GPS que estivessem esperando envio neste aparelho saem
  /// junto: são de quem está saindo, e não do próximo a entrar.
  Future<void> logout() async {
    final refresh = _refreshToken;
    await _saveSession(null);
    await PrefsTrackOutbox.clearAll();
    if (refresh != null) unawaited(_encerrarNoServidor(refresh));
  }

  Future<void> _encerrarNoServidor(String refresh) async {
    try {
      await _despachar('POST', '/auth/logout', body: {'refresh_token': refresh});
    } catch (_) {
      // Melhor esforço: a sessão local já acabou.
    }
  }

  Future<void> changePassword(String current, String next) => _request(
        'POST',
        '/auth/change-password',
        body: {'current_password': current, 'new_password': next},
        authed: true,
      );

  /// Exclui a conta de quem está logado, e tudo o que é dela. SEM VOLTA.
  ///
  /// O servidor confere duas coisas que não são a sessão: o [email] digitado
  /// e, se a conta tem senha, a [password] atual — um token copiado não apaga
  /// a vida de ninguém. 400 = o e-mail não é o da conta; 401 = senha errada
  /// (sem `WWW-Authenticate`, então não dispara renovação de sessão).
  ///
  /// Deu certo, a sessão daqui não existe mais em lugar nenhum: é esquecida
  /// no aparelho, com os pontos de GPS que estivessem esperando envio. Não há
  /// logout a avisar — os tokens foram apagados junto com a conta.
  Future<void> deleteAccount({required String email, String? password}) async {
    await _request(
      'POST',
      '/auth/delete-account',
      body: {'email': email, 'password': ?password},
      authed: true,
    );
    await _saveSession(null);
    await PrefsTrackOutbox.clearAll();
  }

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

  /// As cidades e os países da coleção (GET /me/places), agrupados no banco:
  /// a lista por trás dos números "cidades" e "países" do Perfil.
  Future<Places> getPlaces() async =>
      Places.fromJson(await _request('GET', '/me/places', authed: true));

  /// Os dias em que a pessoa registrou algo (GET /me/days), do mais recente
  /// ao mais antigo — a lista por trás de "dias no app".
  Future<List<DayEntry>> getDays() async {
    final data = await _request('GET', '/me/days', authed: true);
    if (data is! List) return const [];
    return [for (final d in data) DayEntry.fromJson(d as Map<String, dynamic>)];
  }

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
      Profile.fromJson(await _upload('/me/avatar', bytes, filename, mimeType));

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
  ///
  /// [phaseId] é a lente: só as memórias da fase (marcadas nela ou dentro de
  /// uma jornada marcada nela — a regra mora no backend). O cursor de uma
  /// página filtrada só vale com o MESMO filtro.
  ///
  /// [filter] é o recorte que um número do Perfil abre: a cidade, o país, só
  /// as que têm foto, as registradas num dia. Vale a mesma regra do cursor.
  Future<Page<Memory>> listMemories(
          {int? limit, String? cursor, String? phaseId, MemoryFilter? filter}) =>
      _page('/memories', Memory.fromJson,
          limit: limit, cursor: cursor, phaseId: phaseId, filter: filter);

  Future<Memory> getMemory(String id) async =>
      Memory.fromJson(await _request('GET', '/memories/$id', authed: true));

  Future<Memory> createMemory(Map<String, dynamic> payload) async =>
      Memory.fromJson(await _request('POST', '/memories', body: payload, authed: true));

  Future<Memory> updateMemory(String id, Map<String, dynamic> patch) async =>
      Memory.fromJson(await _request('PATCH', '/memories/$id', body: patch, authed: true));

  Future<void> deleteMemory(String id) => _request('DELETE', '/memories/$id', authed: true);

  /// Anexa uma foto à memória. A rota devolve a memória inteira, mas o corpo é
  /// descartado de propósito: quem chama está num laço de várias fotos
  /// (memory_edit, memory_new) e relê a memória uma vez no fim.
  Future<void> addMemoryImage(String id, List<int> bytes, String filename, String mimeType) =>
      _upload('/memories/$id/images', bytes, filename, mimeType);

  Future<void> deleteMemoryImage(String memoryId, String imageId) =>
      _request('DELETE', '/memories/$memoryId/images/$imageId', authed: true);

  /// O ÚNICO envio multipart do cliente: avatar, capa da jornada e foto da
  /// memória passam todos por aqui.
  ///
  /// Eram dois caminhos quase iguais, e a cópia não era inofensiva: só um deles
  /// enviava pelo cliente injetável, então a foto da memória — o upload mais
  /// usado do app — era o único que nenhum teste conseguia observar. Duas
  /// cópias de uma correção é uma correção que vai ser aplicada só numa delas.
  ///
  /// Devolve o corpo já decodificado (null quando a resposta vem vazia): quem
  /// precisa do recurso atualizado lê o retorno, e quem não precisa ignora —
  /// como [addMemoryImage] faz, e como [_request] já fazia para `deleteMemory`.
  Future<dynamic> _upload(
      String path, List<int> bytes, String filename, String mimeType) async {
    final usado = _token;
    var r = await _enviarArquivo(path, bytes, filename, mimeType);
    // Mesma regra de [_send]: sessão vencida vira renovação e o MESMO envio
    // sai de novo. A requisição multipart é de uso único, por isso é remontada.
    if (_sessaoVencida(r, path) && await _renovar(usado)) {
      r = await _enviarArquivo(path, bytes, filename, mimeType);
    }
    if (r.statusCode >= 400) throw _errorFor(r);
    _mudou(path);
    if (r.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<http.Response> _enviarArquivo(
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
      // Pelo cliente injetável, e NÃO por `req.send()`: aquele fabrica um
      // cliente próprio lá dentro, que `swapClient` não alcança — é o que
      // deixava todo envio de imagem fora do alcance de um teste.
      //
      // O teto é o do upload, não o de leitura: aqui o relógio também cobre os
      // bytes subindo, e [apiTimeout] cancelaria envio que ia bem.
      final enviada = await _client.send(req).timeout(apiUploadTimeout);
      return await http.Response.fromStream(enviada);
    } on TimeoutException {
      // Texto próprio: "o upload demorou" é outra notícia que "o servidor
      // demorou a responder" — quem está esperando sabe que mandou uma foto.
      throw ApiError(0, 'O upload demorou demais. Tente de novo.',
          kind: ApiFailure.timeout);
    } catch (_) {
      throw ApiError(0, 'Sem conexão com o servidor.');
    }
  }

  // ---- Música da memória ----

  /// Anexa a canção que estava tocando.
  ///
  /// O corpo é o snapshot que veio do catálogo — a API não consulta provedor
  /// nenhum. 409 quando a faixa já está na memória ou o teto de 5 foi atingido.
  Future<Memory> addMemoryMusic(String memoryId, Map<String, dynamic> track) async =>
      Memory.fromJson(await _request('POST', '/memories/$memoryId/music',
          body: track, authed: true));

  Future<Memory> removeMemoryMusic(String memoryId, String musicId) async =>
      Memory.fromJson(await _request(
          'DELETE', '/memories/$memoryId/music/$musicId', authed: true));

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
  /// Uma página de jornadas, da mais recente para a mais antiga. Com
  /// [phaseId], só as da fase — marcadas nela ou com alguma memória dela.
  Future<Page<Journey>> listJourneys({int? limit, String? cursor, String? phaseId}) =>
      _page('/journeys', Journey.fromJson,
          limit: limit, cursor: cursor, phaseId: phaseId);

  Future<JourneyDetail> getJourney(String id) async =>
      JourneyDetail.fromJson(await _request('GET', '/journeys/$id', authed: true));

  Future<Journey> createJourney(Map<String, dynamic> payload) async =>
      Journey.fromJson(await _request('POST', '/journeys', body: payload, authed: true));

  Future<Journey> updateJourney(String id, Map<String, dynamic> patch) async =>
      Journey.fromJson(await _request('PATCH', '/journeys/$id', body: patch, authed: true));

  /// Define a capa da jornada e devolve a jornada já atualizada, com a URL
  /// assinada pronta para a lista — sem segunda leitura.
  ///
  /// O [mimeType] vai no multipart por educação, mas NÃO é o que decide: o
  /// backend fareja os magic bytes do conteúdo (`sniff_image_type`) e recusa
  /// com 400 o que não for JPEG, PNG ou WebP, por mais que o cabeçalho prometa.
  /// Acima de 5 MB (`MAX_IMAGE_BYTES`) a resposta é 413 — por isso quem escolhe
  /// a foto reduz antes de enviar.
  Future<Journey> setJourneyCover(
    String id,
    List<int> bytes,
    String filename,
    String mimeType,
  ) async =>
      Journey.fromJson(
          await _upload('/journeys/$id/cover', bytes, filename, mimeType));

  /// Tira a capa ESCOLHIDA (idempotente). A jornada não fica necessariamente
  /// sem capa: o backend volta ao automático — a primeira foto do rastro —, e é
  /// por isso que a resposta pode trazer `cover_image_url` preenchida mesmo
  /// depois de remover.
  Future<Journey> removeJourneyCover(String id) async =>
      Journey.fromJson(await _request('DELETE', '/journeys/$id/cover', authed: true));

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
  /// O atlas inteiro ou, com [phaseId], a lente de uma fase: pins soltos
  /// marcados nela e as jornadas que pertencem a ela, inteiras.
  Future<MapResponse> getMap({String? phaseId}) async => MapResponse.fromJson(
      await _request('GET', _query('/map', {'life_phase_id': ?phaseId}),
          authed: true));

  // ---- Fases da vida ----
  /// As fases da pessoa, na ordem em que a vida aconteceu (as sem início vão
  /// para o fim — a ordem é do backend). Quem nunca criou nenhuma recebe [].
  Future<List<LifePhase>> listPhases() async {
    final data = await _request('GET', '/life-phases', authed: true);
    if (data is! List) return [];
    return data.map((e) => LifePhase.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 422 = nome vazio, cor fora da paleta ou fim antes do início; a mensagem
  /// já vem em pt-BR, escrita para quem vai ler.
  Future<LifePhase> createPhase(Map<String, dynamic> body) async => LifePhase.fromJson(
      await _request('POST', '/life-phases', body: body, authed: true));

  /// PARCIAL, e aqui `null` LIMPA (ao contrário do PATCH de jornada): é o que
  /// deixa uma fase que ganhou fim por engano voltar a ser a fase em curso.
  /// Monte o corpo com `phasePatch`, que só manda o que mudou.
  Future<LifePhase> updatePhase(String id, Map<String, dynamic> patch) async =>
      LifePhase.fromJson(
          await _request('PATCH', '/life-phases/$id', body: patch, authed: true));

  /// Apaga a fase e SOLTA o que apontava para ela: memórias e jornadas ficam,
  /// só perdem a etiqueta.
  Future<void> deletePhase(String id) =>
      _request('DELETE', '/life-phases/$id', authed: true);
}
