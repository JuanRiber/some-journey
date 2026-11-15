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

  test('a pilha nunca vem vazia', () {
    for (final sessao in [true, false]) {
      for (final pedida in [null, '', '/', '/profile', '/memory']) {
        expect(_pilha(pedida, sessao: sessao), isNotEmpty);
      }
    }
  });
}
