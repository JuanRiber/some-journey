// As telas tardias leem o ESQUEMA ativo, não uma paleta fixa.
//
// Detalhe de memória, edição de memória e detalhe de jornada pintavam-se com
// constantes `const` de um tema legado. Isso não dava erro nenhum: no modo
// claro a cor era exatamente a mesma, e a suíte inteira ficava verde. O defeito
// só apareceria ao ligar o modo escuro — as telas continuariam creme dentro de
// um app noturno, e nenhum teste diria por quê.
//
// Por isso a afirmação aqui é a ÚNICA que distingue os dois mundos: montar a
// tela sob o esquema ESCURO e exigir que o que ela pinta venha de `sjDark`.
// Com cor constante estes testes falham; com `SJTheme.of(context)` passam.
//
// `memory_new.dart` e `location_picker.dart` ficam de fora de propósito: montar
// qualquer uma das duas traz junto a camada de telhas do mapa, que em teste
// responde 400 e enche a saída da suíte de erros de rede. A cobertura delas
// aqui custaria mais em ruído do que entregaria em garantia.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/design/sj_theme.dart';
import 'package:some_journey/design/tokens.dart';
import 'package:some_journey/screens/journey_detail.dart';
import 'package:some_journey/screens/journeys.dart';
import 'package:some_journey/screens/memory_detail.dart';
import 'package:some_journey/screens/memory_edit.dart';

Map<String, dynamic> _memoria() => {
      'id': 'm1',
      'title': 'Fim de tarde',
      'text': 'o mar estava frio',
      'latitude': -3.7,
      'longitude': -38.5,
      'occurred_at': '2026-08-14T00:00:00Z',
      'created_at': '2026-08-14T10:00:00Z',
      'images': <dynamic>[],
      'music': <dynamic>[],
    };

/// Jornada CONCLUÍDA e sem pontos: sem pontos a tela não monta o mapa, e é o
/// estado "concluída" que exercita a cor que não tinha contrapartida óbvia.
Map<String, dynamic> _jornada() => {
      'id': 'j1',
      'title': 'Litoral Leste',
      'description': null,
      'mood': null,
      'is_private': true,
      'cover_image_url': null,
      'status': 'finished',
      'started_at': null,
      'ended_at': null,
      'created_at': '2026-01-01T00:00:00Z',
      'points_count': 0,
      'points': <dynamic>[],
      'route': null,
    };

/// Responde cada rota com o JSON que a tela espera. O roteamento é por sufixo
/// do caminho porque a `baseUrl` da Api não interessa aqui.
http.Response _ok(http.Request r) {
  final caminho = r.url.path;
  final corpo = caminho.endsWith('/map')
      ? {'journey': _jornada(), 'tracks': <String, dynamic>{}, 'distance_m': 0}
      : caminho.endsWith('/tracks')
          ? <dynamic>[]
          : caminho.contains('/journeys/')
              ? _jornada()
              : _memoria();
  return http.Response(jsonEncode(corpo), 200,
      headers: {'content-type': 'application/json'});
}

/// Monta [tela] sob o atlas noturno. O `SJTheme` fica ACIMA do `MaterialApp` de
/// propósito: é assim que o app vai prover o esquema quando o modo escuro for
/// ligado, e é o caminho que estas telas precisam saber percorrer.
Future<void> _montarNoEscuro(WidgetTester tester, Widget tela) async {
  await tester.pumpWidget(SJTheme(
    scheme: sjDark,
    child: MaterialApp(home: tela),
  ));
  await tester.pumpAndSettle();
}

/// A cor que o `Text` encontrado está realmente usando.
Color _corDoTexto(WidgetTester tester, String texto) =>
    tester.widget<Text>(find.text(texto)).style!.color!;

void main() {
  late http.Client anterior;

  setUp(() => Api.instance.debugSetToken('token'));
  tearDown(() => Api.instance.swapClient(anterior));

  void responder(http.Response Function(http.Request) handler) {
    anterior = Api.instance.swapClient(MockClient((r) async => handler(r)));
  }

  testWidgets('o detalhe da memória desenha a volta na superfície do esquema',
      (tester) async {
    responder(_ok);
    await _montarNoEscuro(tester, const MemoryDetailScreen(memoryId: 'm1'));

    final circulo = tester.widget<Container>(
      find.ancestor(of: find.text('←'), matching: find.byType(Container)).first,
    );
    final decoracao = circulo.decoration! as BoxDecoration;

    expect(decoracao.color, sjDark.surface,
        reason: 'preso no creme da paleta legada');
    expect((decoracao.border! as Border).top.color, sjDark.line);
  });

  testWidgets('o detalhe da memória escreve título e corpo na tinta do esquema',
      (tester) async {
    responder(_ok);
    await _montarNoEscuro(tester, const MemoryDetailScreen(memoryId: 'm1'));

    expect(_corDoTexto(tester, 'Fim de tarde'), sjDark.ink);
    expect(_corDoTexto(tester, 'o mar estava frio'), sjDark.ink);
  });

  testWidgets('a edição de memória acompanha o esquema', (tester) async {
    // 404 de propósito: no estado de erro a tela não monta o seletor de local
    // (e, com ele, a camada de telhas), mas ainda desenha cabeçalho e aviso —
    // que é exatamente o que precisa vir do esquema.
    responder((_) => http.Response('{"detail":"não achei"}', 404,
        headers: {'content-type': 'application/json'}));
    await _montarNoEscuro(tester, const MemoryEditScreen(memoryId: 'm1'));

    expect(_corDoTexto(tester, '← Voltar'), sjDark.ink);
    expect(_corDoTexto(tester, 'Editar memória'), sjDark.ink);
    expect(_corDoTexto(tester, 'Ajuste o que precisar.'), sjDark.inkSoft);
    expect(_corDoTexto(tester, 'Memória não encontrada.'), sjDark.danger);
  });

  testWidgets('a jornada concluída usa o musgo do esquema, não um ciano fixo',
      (tester) async {
    responder(_ok);
    await _montarNoEscuro(tester, const JourneyDetailScreen(journeyId: 'j1'));

    expect(_corDoTexto(tester, '← Voltar'), sjDark.ink);
    expect(_corDoTexto(tester, 'Litoral Leste'), sjDark.ink);
    // O estado do capítulo é o MESMO vocabulário da estante: concluída = musgo.
    expect(_corDoTexto(tester, 'Jornada concluída.'),
        journeyStatusColor('finished', sjDark));
  });
}
