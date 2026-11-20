// A sessão que se renova sozinha.
//
// O access token vale uma hora. Antes, passada a hora, a primeira tela que
// pedisse dados tomava 401 e mandava a pessoa para o login — no meio do que
// ela estivesse fazendo. Agora o cliente da API troca o refresh token por um
// par novo e repete a MESMA requisição; quem chamou nem fica sabendo.
//
// O servidor falso responde como o de verdade no que importa: `Authorization`
// com o token vigente é 200, com qualquer outro é o 401 de sessão (o que vem
// com `WWW-Authenticate`), e `/auth/refresh` só aceita o refresh token vigente
// — que vale uma troca.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/features/auth/token_store.dart';

/// O cofre, em memória — e contando quantas vezes foi gravado.
class CofreFalso implements TokenStore {
  StoredSession? guardada;
  int gravacoes = 0;

  @override
  Future<StoredSession?> read() async => guardada;

  @override
  Future<bool> write(StoredSession? session) async {
    guardada = session;
    gravacoes++;
    return true;
  }
}

http.Response _json(Object corpo, [int status = 200, Map<String, String>? h]) =>
    http.Response(jsonEncode(corpo), status,
        headers: {'content-type': 'application/json; charset=utf-8', ...?h});

http.Response _sessaoVencida() => _json(
      {'detail': 'Sua sessão expirou ou não é válida. Entre de novo.'},
      401,
      {'www-authenticate': 'Bearer'},
    );

const _perfil = {
  'identity': {
    'id': 'u1',
    'name': 'Ana Lima',
    'email': 'ana@example.com',
    'joined_at': '2026-03-14T12:00:00Z',
  },
  'stats': {'memories': 3, 'journeys': 1},
  'passport': <dynamic>[],
};

void main() {
  late http.Client anterior;
  late TokenStore cofreAnterior;
  late CofreFalso cofre;

  /// O que o servidor aceita agora.
  late String accessVigente;
  late String refreshVigente;
  late int geracao;

  /// "MÉTODO caminho" de tudo o que chegou, na ordem.
  late List<String> chamadas;

  /// Como `/auth/refresh` responde, quando o teste quer outra coisa.
  http.Response? Function()? renovacaoForcada;

  setUp(() {
    accessVigente = 'access-1';
    refreshVigente = 'refresh-1';
    geracao = 1;
    chamadas = [];
    renovacaoForcada = null;
    cofre = CofreFalso();
    cofreAnterior = Api.instance.swapTokenStore(cofre);
    anterior = Api.instance.swapClient(MockClient((r) async {
      final caminho = r.url.path;
      chamadas.add('${r.method} $caminho');

      if (caminho == '/auth/login') {
        return _json({
          'access_token': accessVigente,
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': refreshVigente,
        });
      }
      if (caminho == '/auth/refresh') {
        final forcada = renovacaoForcada?.call();
        if (forcada != null) return forcada;
        final enviado = (jsonDecode(r.body) as Map)['refresh_token'];
        if (enviado != refreshVigente) {
          return _json({'detail': 'Sua sessão expirou. Entre de novo.'}, 401);
        }
        geracao++;
        accessVigente = 'access-$geracao';
        refreshVigente = 'refresh-$geracao';
        return _json({
          'access_token': accessVigente,
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': refreshVigente,
        });
      }
      if (caminho == '/auth/logout') return http.Response('', 204);
      if (caminho == '/auth/change-password') {
        // O 401 que NÃO é de sessão: sem WWW-Authenticate.
        return _json({'detail': 'A senha atual está incorreta.'}, 401);
      }

      if (r.headers['Authorization'] != 'Bearer $accessVigente') {
        return _sessaoVencida();
      }
      if (caminho == '/me/profile') return _json(_perfil);
      return _json(<dynamic>[]);
    }));
    Api.instance.debugSetToken(null);
  });

  tearDown(() {
    Api.instance.swapClient(anterior);
    Api.instance.swapTokenStore(cofreAnterior);
    Api.instance.debugSetToken(null);
  });

  /// O servidor esqueceu o access token (passou a hora); o refresh ainda vale.
  void vencerAccess() => accessVigente = 'ninguem-tem-este';

  group('entrar', () {
    test('guarda o par inteiro no cofre', () async {
      await Api.instance.login('ana@example.com', 'senha-da-ana');

      expect(Api.instance.hasToken, isTrue);
      expect(cofre.guardada?.accessToken, 'access-1');
      expect(cofre.guardada?.refreshToken, 'refresh-1');
    });

    test('a sessão restaurada do cofre renova como a que acabou de entrar',
        () async {
      cofre.guardada =
          const StoredSession(accessToken: 'velho', refreshToken: 'refresh-1');

      await Api.instance.loadToken();
      final perfil = await Api.instance.getProfile();

      expect(perfil.identity.name, 'Ana Lima');
      expect(chamadas,
          ['GET /me/profile', 'POST /auth/refresh', 'GET /me/profile']);
    });
  });

  group('renovar', () {
    setUp(() async {
      await Api.instance.login('ana@example.com', 'senha-da-ana');
      chamadas.clear();
    });

    test('sessão vencida não chega à tela: renova e repete o pedido', () async {
      vencerAccess();

      final perfil = await Api.instance.getProfile();

      expect(perfil.identity.name, 'Ana Lima');
      expect(chamadas,
          ['GET /me/profile', 'POST /auth/refresh', 'GET /me/profile']);
      expect(cofre.guardada?.accessToken, 'access-2');
      expect(cofre.guardada?.refreshToken, 'refresh-2',
          reason: 'o refresh token vale uma troca: o sucessor tem de ser guardado');
    });

    test('renovar não é trocar de sessão: os caches de tela continuam valendo',
        () async {
      final antes = Api.instance.sessionTag;
      vencerAccess();

      await Api.instance.getProfile();

      expect(Api.instance.sessionTag, same(antes));
    });

    test('três pedidos vencem juntos e a renovação acontece UMA vez', () async {
      vencerAccess();

      await Future.wait([
        Api.instance.getProfile(),
        Api.instance.listMemories(),
        Api.instance.listJourneys(),
      ]);

      expect(chamadas.where((c) => c == 'POST /auth/refresh'), hasLength(1),
          reason: 'três trocas com o mesmo refresh token seriam duas recusas');
      expect(geracao, 2);
    });

    test('o pedido que volta depois da renovação não renova de novo', () async {
      vencerAccess();
      await Api.instance.getProfile();
      chamadas.clear();

      await Api.instance.getProfile();

      expect(chamadas, ['GET /me/profile']);
    });

    test('escrita também se repete, e avisa a mudança uma vez só', () async {
      vencerAccess();
      final antes = Api.instance.changes.value;

      await Api.instance.deleteMemory('m1');

      expect(chamadas,
          ['DELETE /memories/m1', 'POST /auth/refresh', 'DELETE /memories/m1']);
      expect(Api.instance.changes.value, antes + 1);
    });

    test('upload também se repete', () async {
      vencerAccess();

      await Api.instance
          .addMemoryImage('m1', const [0xFF, 0xD8, 0xFF], 'f.jpg', 'image/jpeg');

      expect(chamadas, [
        'POST /memories/m1/images',
        'POST /auth/refresh',
        'POST /memories/m1/images',
      ]);
    });
  });

  group('quando a sessão acabou de verdade', () {
    setUp(() async {
      await Api.instance.login('ana@example.com', 'senha-da-ana');
      chamadas.clear();
    });

    test('refresh recusado: o 401 sobe e a sessão é esquecida', () async {
      vencerAccess();
      refreshVigente = 'revogado-no-servidor';

      await expectLater(
        Api.instance.getProfile(),
        throwsA(isA<ApiError>().having((e) => e.isUnauthorized, '401', isTrue)),
      );

      expect(Api.instance.hasToken, isFalse);
      expect(cofre.guardada, isNull,
          reason: 'senão o app reabre no atlas só para tomar 401 de novo');
      expect(chamadas, ['GET /me/profile', 'POST /auth/refresh'],
          reason: 'sem token novo, o pedido não é repetido');
    });

    test('sessão antiga, sem refresh token, cai como sempre caiu', () async {
      Api.instance.debugSetToken('token-de-antes-da-renovacao');
      cofre.guardada =
          const StoredSession(accessToken: 'token-de-antes-da-renovacao');

      await expectLater(
        Api.instance.getProfile(),
        throwsA(isA<ApiError>().having((e) => e.isUnauthorized, '401', isTrue)),
      );

      expect(chamadas, ['GET /me/profile']);
    });
  });

  group('quando não deu para saber', () {
    setUp(() async {
      await Api.instance.login('ana@example.com', 'senha-da-ana');
      chamadas.clear();
      vencerAccess();
    });

    test('sem rede na renovação: avisa a queda e NÃO desloga', () async {
      renovacaoForcada = () => throw const _SemRede();

      await expectLater(
        Api.instance.getProfile(),
        throwsA(isA<ApiError>()
            .having((e) => e.kind, 'kind', ApiFailure.offline)
            .having((e) => e.isUnauthorized, '401', isFalse)),
      );

      expect(Api.instance.hasToken, isTrue);
      expect(cofre.guardada?.refreshToken, 'refresh-1');
    });

    test('servidor fora na renovação: idem', () async {
      renovacaoForcada = () => _json({'detail': 'x'}, 503);

      await expectLater(
        Api.instance.getProfile(),
        throwsA(isA<ApiError>()
            .having((e) => e.kind, 'kind', ApiFailure.unavailable)),
      );

      expect(Api.instance.hasToken, isTrue);
    });

    test('limite de tentativas na renovação não desloga ninguém', () async {
      renovacaoForcada = () => _json({'detail': 'Tentativas demais.'}, 429);

      await expectLater(
        Api.instance.getProfile(),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 429)),
      );

      expect(Api.instance.hasToken, isTrue);
    });

    test('a queda passou: a renovação seguinte funciona', () async {
      renovacaoForcada = () => _json({'detail': 'x'}, 503);
      await expectLater(Api.instance.getProfile(), throwsA(isA<ApiError>()));

      renovacaoForcada = null;
      final perfil = await Api.instance.getProfile();

      expect(perfil.identity.name, 'Ana Lima');
    });
  });

  group('o 401 que não é de sessão', () {
    test('senha atual errada não gasta um refresh token', () async {
      await Api.instance.login('ana@example.com', 'senha-da-ana');
      chamadas.clear();

      await expectLater(
        Api.instance.changePassword('errada', 'nova-senha-123'),
        throwsA(isA<ApiError>()
            .having((e) => e.message, 'mensagem', 'A senha atual está incorreta.')),
      );

      expect(chamadas, ['POST /auth/change-password']);
      expect(Api.instance.hasToken, isTrue);
    });
  });

  group('duas abas', () {
    test('a outra aba já renovou: adota o par guardado, sem trocar de novo',
        () async {
      await Api.instance.login('ana@example.com', 'senha-da-ana');
      // A outra aba trocou refresh-1 por refresh-2 e gravou. Esta ainda tem,
      // em memória, o par antigo.
      vencerAccess();
      accessVigente = 'access-2';
      refreshVigente = 'refresh-2';
      cofre.guardada = const StoredSession(
          accessToken: 'access-2', refreshToken: 'refresh-2');
      chamadas.clear();

      final perfil = await Api.instance.getProfile();

      expect(perfil.identity.name, 'Ana Lima');
      expect(chamadas, ['GET /me/profile', 'GET /me/profile'],
          reason: 'usar o refresh-1 de novo pareceria reuso ao servidor');
    });
  });

  group('sair', () {
    test('esquece aqui e avisa o servidor com o refresh token', () async {
      await Api.instance.login('ana@example.com', 'senha-da-ana');
      chamadas.clear();

      await Api.instance.logout();
      await Future<void>.delayed(Duration.zero);

      expect(Api.instance.hasToken, isFalse);
      expect(Api.instance.sessionTag, isNull);
      expect(cofre.guardada, isNull);
      expect(chamadas, ['POST /auth/logout']);
    });

    test('sem rede, sai do mesmo jeito', () async {
      await Api.instance.login('ana@example.com', 'senha-da-ana');
      Api.instance.swapClient(MockClient((_) async => throw const _SemRede()));

      await Api.instance.logout();
      await Future<void>.delayed(Duration.zero);

      expect(Api.instance.hasToken, isFalse);
      expect(cofre.guardada, isNull);
    });

    test('sessão sem refresh token não tem o que avisar', () async {
      Api.instance.debugSetToken('so-o-access');

      await Api.instance.logout();
      await Future<void>.delayed(Duration.zero);

      expect(chamadas, isEmpty);
    });
  });
}

class _SemRede implements Exception {
  const _SemRede();
}
