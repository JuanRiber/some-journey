// Os cabeçalhos de segurança do app web (web/_headers, lido pelo Cloudflare
// Pages).
//
// Na web a sessão mora no localStorage: qualquer script que rode na página a
// lê. A CSP é o que impede um script que não é nosso de rodar — e ela é uma
// lista fechada do que o app carrega e de onde. Lista fechada tem um jeito
// próprio de quebrar: alguém acrescenta um serviço ao app, tudo funciona em
// localhost (onde o arquivo não é aplicado) e falha em produção, em silêncio,
// só para quem usa aquela tela.
//
// Estes testes prendem as duas pontas: o que a política NÃO pode afrouxar, e
// que todo host escrito no código do app está nela.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// As diretivas da CSP, por nome: `connect-src` → as fontes permitidas.
Map<String, List<String>> _csp(String headers) {
  final linha = headers
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.startsWith('Content-Security-Policy:'));
  final valor = linha.substring('Content-Security-Policy:'.length);
  return {
    for (final diretiva in valor.split(';').map((d) => d.trim()))
      if (diretiva.isNotEmpty)
        diretiva.split(RegExp(r'\s+')).first:
            diretiva.split(RegExp(r'\s+')).skip(1).toList(),
  };
}

/// Um host casa com uma fonte da CSP? (`https://*.supabase.co` cobre
/// `https://abc.supabase.co`; fonte com caminho cobre o host.)
bool _permite(List<String> fontes, String host) => fontes.any((fonte) {
      final uri = Uri.tryParse(fonte.replaceFirst('*.', 'curinga.'));
      if (uri == null || uri.host.isEmpty) return false;
      if (fonte.contains('*.')) {
        return host.endsWith(uri.host.replaceFirst('curinga', ''));
      }
      return uri.host == host;
    });

/// Os hosts externos que o código do app nomeia: literais `https://host` e
/// `Uri.https('host', ...)`. Comentários ficam de fora — link de documentação
/// não é chamada.
Set<String> _hostsDoCodigo() {
  final literal = RegExp(r'''https://([a-zA-Z0-9.-]+\.[a-z]{2,})''');
  final uriHttps = RegExp(r'''Uri\.https\(\s*['"]([^'"]+)['"]''');
  final hosts = <String>{};
  for (final arquivo in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    for (final linha in arquivo.readAsLinesSync()) {
      if (linha.trimLeft().startsWith('//')) continue;
      hosts
        ..addAll(literal.allMatches(linha).map((m) => m.group(1)!))
        ..addAll(uriHttps.allMatches(linha).map((m) => m.group(1)!));
    }
  }
  return hosts;
}

void main() {
  final headers = File('web/_headers').readAsStringSync();
  final csp = _csp(headers);

  group('o que a política não pode afrouxar', () {
    test('script só nosso: sem unsafe-inline e sem unsafe-eval', () {
      final scripts = csp['script-src']!;

      expect(scripts, isNot(contains("'unsafe-inline'")),
          reason: 'é o que impede um script injetado de ler a sessão');
      expect(scripts, isNot(contains("'unsafe-eval'")));
      expect(scripts, isNot(contains('*')));
      expect(scripts, contains("'wasm-unsafe-eval'"),
          reason: 'sem ele o CanvasKit não compila e o app não desenha nada');
    });

    test('nada vem de qualquer lugar por padrão', () {
      expect(csp['default-src'], ["'self'"]);
      expect(csp['object-src'], ["'none'"]);
      expect(csp['base-uri'], ["'self'"]);
    });

    test('o app não abre dentro da página de ninguém', () {
      expect(csp['frame-ancestors'], ["'none'"]);
      expect(headers, contains('X-Frame-Options: DENY'));
    });

    test('os outros cabeçalhos estão lá', () {
      expect(headers, contains('Strict-Transport-Security: max-age='));
      expect(headers, contains('X-Content-Type-Options: nosniff'));
      expect(headers, contains('Referrer-Policy:'));
      expect(headers, contains('geolocation=(self)'),
          reason: 'o percurso por GPS precisa da localização');
    });

    test('vale para todas as páginas', () {
      expect(headers.split('\n').where((l) => !l.startsWith('#')), contains('/*'));
    });
  });

  group('o que o app chama está na política', () {
    test('todo host escrito no código pode ser chamado', () {
      final conexoes = csp['connect-src']!;
      final hosts = _hostsDoCodigo();

      expect(hosts, isNotEmpty, reason: 'a coleta quebrou: sem isto o teste '
          'passaria sem conferir nada');
      for (final host in hosts) {
        expect(_permite(conexoes, host), isTrue,
            reason: '$host é chamado pelo app e não está em connect-src: '
                'funciona em localhost e falha em produção. Acrescente-o em '
                'web/_headers.');
      }
    });

    test('as telhas do mapa também entram como imagem', () {
      expect(_permite(csp['img-src']!, 'tile.openstreetmap.org'), isTrue);
    });

    test('fotos e capas de música têm de onde vir', () {
      expect(_permite(csp['img-src']!, 'abc.supabase.co'), isTrue);
      expect(_permite(csp['img-src']!, 'is1-ssl.mzstatic.com'), isTrue);
    });

    test('um host que não está na lista não passa', () {
      expect(_permite(csp['connect-src']!, 'example.com'), isFalse);
      expect(_permite(csp['connect-src']!, 'supabase.co.example.com'), isFalse);
    });
  });

  group('a origem da API', () {
    test('entra por um marcador, que o deploy troca', () {
      expect(csp['connect-src'], contains('__API_ORIGIN__'),
          reason: 'a API de cada build vem da variável API_URL, não deste arquivo');
    });

    test('o workflow de deploy faz a troca e confere que ela aconteceu', () {
      final workflow =
          File('../.github/workflows/deploy-web.yml').readAsStringSync();

      expect(workflow, contains('build/web/_headers'));
      expect(workflow, contains('s#__API_ORIGIN__#'));
      expect(workflow, contains("grep -q '__API_ORIGIN__'"),
          reason: 'publicar com o marcador bloquearia toda chamada à API');
    });
  });
}
