// A tela "O que guardamos sobre você".
//
// É uma tela de texto, e o risco de uma tela de texto é ela ficar para trás do
// código: o app passa a chamar um serviço novo e a página continua dizendo que
// são seis. Aqui o que é afirmado é conferido contra a política de segurança do
// site (`web/_headers`), que nomeia cada endereço que o app PODE chamar — se um
// endereço entrar lá sem que o dono dele seja nomeado aqui, o teste para.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/screens/your_data.dart';

/// De quem é cada endereço que a política libera.
const _donoDoEndereco = {
  'openstreetmap.org': 'OpenStreetMap',
  'supabase.co': 'Supabase',
  'itunes.apple.com': 'iTunes',
  'mzstatic.com': 'iTunes', // as capas das faixas, servidas pela Apple
  'gstatic.com': 'Google',
  'accounts.google.com': 'Google',
};

/// Os hosts de terceiros que a CSP libera (tudo menos o próprio site e a API).
Set<String> _hostsLiberados() {
  final csp = File('web/_headers')
      .readAsLinesSync()
      .map((l) => l.trim())
      .firstWhere((l) => l.startsWith('Content-Security-Policy:'));
  return RegExp(r'https://([a-zA-Z0-9.*-]+)')
      .allMatches(csp)
      .map((m) => m.group(1)!.replaceFirst('*.', ''))
      .toSet();
}

void main() {
  Future<void> abrir(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 6000); // a página inteira
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: const YourDataScreen(),
      routes: {
        '/delete-account': (_) => const Scaffold(body: Text('EXCLUIR')),
      },
    ));
  }

  testWidgets('diz o essencial: quem vê, o que sai das fotos, como apagar',
      (tester) async {
    await abrir(tester);

    expect(find.textContaining('Só você vê'), findsOneWidget);
    expect(find.textContaining('sem o que o celular anota'), findsOneWidget);
    expect(find.textContaining('não acompanha você em segundo plano'), findsOneWidget);
    expect(find.textContaining('depois de 30 dias'), findsOneWidget);
    expect(find.textContaining('Excluir a conta apaga tudo na hora'), findsOneWidget);
  });

  testWidgets('cada serviço da lista aparece na tela, com o papel dele',
      (tester) async {
    await abrir(tester);

    for (final servico in YourDataScreen.servicos) {
      expect(find.textContaining('${servico.nome} ${servico.papel}'), findsOneWidget,
          reason: '${servico.nome} está na lista e não está na tela');
    }
  });

  test('todo endereço que o app pode chamar tem o dono nomeado na tela', () {
    final nomeados = YourDataScreen.servicos.map((s) => s.nome).toSet();
    final hosts = _hostsLiberados();

    expect(hosts, isNotEmpty, reason: 'a leitura da política quebrou');
    for (final host in hosts) {
      final dono = _donoDoEndereco.entries
          .where((e) => host == e.key || host.endsWith('.${e.key}'))
          .map((e) => e.value)
          .firstOrNull;
      expect(dono, isNotNull,
          reason: '$host entrou em web/_headers e ninguém disse de quem é. '
              'Acrescente-o em _donoDoEndereco e nomeie o serviço em '
              'YourDataScreen.servicos.');
      expect(nomeados, contains(dono),
          reason: 'o app pode chamar $host ($dono), e a tela não diz isso');
    }
  });

  test('os prazos ditos na tela são os do servidor', () {
    final config = File('../backend/app/core/config.py').readAsStringSync();

    // "depois de 30 dias" e "vale uma hora": se o padrão mudar, o texto muda.
    expect(config, contains('PURGE_DELETED_AFTER_DAYS: int = Field(default=30'));
    expect(config, contains('IMAGE_SIGNED_URL_TTL: int = Field(default=3600'));
  });

  testWidgets('leva à exclusão de conta', (tester) async {
    await abrir(tester);

    await tester.tap(find.text('Excluir minha conta'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('EXCLUIR'), findsOneWidget);
  });
}
