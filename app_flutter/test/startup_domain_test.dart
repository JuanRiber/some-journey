// Com que telas o app abre — a regra pura por trás do bootstrap.
//
// O caso que motivou o arquivo é o recarregamento do navegador numa rota
// interna (ver reload_route_test.dart, que monta o app de verdade). Aqui fica
// a tabela inteira da decisão, que não precisa de tela para ser conferida.

import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/features/auth/startup_domain.dart';

const _montaveis = {
  '/login',
  '/forgot',
  '/tabs',
  '/profile',
  '/settings',
  '/phases',
};

List<String> _pilha(String? pedida, {required bool sessao}) => startupStack(
      requested: pedida,
      hasToken: sessao,
      buildable: _montaveis,
    );

void main() {
  group('sem sessão', () {
    test('qualquer pedido termina no login, e só nele', () {
      for (final pedida in [null, '/', '/tabs', '/profile', '/memory', '/forgot']) {
        expect(_pilha(pedida, sessao: false), ['/login'], reason: '$pedida');
      }
    });
  });

  group('com sessão', () {
    test('sem pedido, ou pedindo a raiz, abre o atlas', () {
      expect(_pilha(null, sessao: true), ['/tabs']);
      expect(_pilha('/', sessao: true), ['/tabs']);
      expect(_pilha('/tabs', sessao: true), ['/tabs']);
    });

    test('rota sem argumento volta por cima do atlas', () {
      expect(_pilha('/profile', sessao: true), ['/tabs', '/profile']);
      expect(_pilha('/phases', sessao: true), ['/tabs', '/phases']);
    });

    test('rota que leva id não se reconstrói do hash: atlas', () {
      for (final pedida in ['/memory', '/memory-edit', '/journey', '/journey-edit']) {
        expect(_pilha(pedida, sessao: true), ['/tabs'], reason: pedida);
      }
    });

    test('rota de quem ainda não entrou não se abre para quem já entrou', () {
      for (final pedida in rotasPublicas) {
        expect(_pilha(pedida, sessao: true), ['/tabs'], reason: pedida);
      }
    });

    test('nome desconhecido ou torto cai no atlas, nunca no login', () {
      expect(_pilha('/nao-existe', sessao: true), ['/tabs']);
      expect(_pilha('', sessao: true), ['/tabs']);
      expect(_pilha('::', sessao: true), ['/tabs']);
    });

    test('querystring pendurada no hash não muda a tela', () {
      expect(_pilha('/profile?x=1', sessao: true), ['/tabs', '/profile']);
    });
  });

  group('link de redefinição de senha', () {
    const link = '/reset-password?token=abc-DEF_123';

    test('o token sai da querystring do link', () {
      expect(resetTokenFrom(link), 'abc-DEF_123');
      // Espaço colado junto, por quem copiou o link à mão, não faz parte dele.
      expect(resetTokenFrom('/reset-password?token=%20abc%20'), 'abc');
    });

    test('sem token não é link de redefinição', () {
      for (final pedida in [
        null,
        '',
        '/',
        '/reset-password',
        '/reset-password?token=',
        '/reset-password?token=%20',
        '/reset-password?outra=1',
      ]) {
        expect(resetTokenFrom(pedida), isNull, reason: '$pedida');
      }
    });

    test('querystring torta nunca derruba a abertura do app', () {
      // Isto roda no bootstrap: uma exceção aqui é o app que não abre.
      for (final pedida in [
        '/reset-password?token=%zz',
        '/reset-password?token=%FF',
        '/reset-password?token=%E0%A4',
        '/reset-password?%',
      ]) {
        expect(() => resetTokenFrom(pedida), returnsNormally, reason: pedida);
      }
    });

    test('token pendurado em outra rota não vale', () {
      expect(resetTokenFrom('/profile?token=abc'), isNull);
      expect(resetTokenFrom('/forgot?token=abc'), isNull);
    });

    test('abre a nova senha por cima do login, com ou sem sessão', () {
      expect(_pilha(link, sessao: false), ['/login', rotaResetSenha]);
      // Com sessão também: o atlas por baixo, com um token vencido, tomaria
      // 401 e derrubaria a tela de nova senha junto.
      expect(_pilha(link, sessao: true), ['/login', rotaResetSenha]);
    });

    test('a rota sem token cai nas regras comuns', () {
      expect(_pilha('/reset-password', sessao: false), ['/login']);
      expect(_pilha('/reset-password', sessao: true), ['/tabs']);
    });
  });

  test('a pilha nunca vem vazia', () {
    for (final sessao in [true, false]) {
      for (final pedida in [null, '', '/', '/profile', '/memory']) {
        expect(_pilha(pedida, sessao: sessao), isNotEmpty);
      }
    }
  });
}
