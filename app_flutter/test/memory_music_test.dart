// A trilha da memória, do lado do app.
//
// Duas coisas valem teste aqui, e nenhuma é a aparência:
//
// 1. A busca ESPERA a digitação pausar. Sem isso, escrever "caetano" dispara
//    sete requisições a um catálogo público para uma única intenção.
// 2. Anexar e remover devolvem a memória atualizada para a tela dona — se esse
//    fio se rompe, a faixa é salva no servidor e some da tela até um F5.

import 'dart:convert';

import 'package:flutter/material.dart';
// O campo do design system é um CupertinoTextField por dentro; EditableText é o
// widget comum aos dois, e é nele que o enterText escreve.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/features/music/memory_music_section.dart';
import 'package:some_journey/features/music/music_provider.dart';
import 'package:some_journey/models.dart';

/// Catálogo falso: conta as buscas e devolve o que o teste mandar.
class _CatalogoFalso implements MusicProvider {
  _CatalogoFalso(this.resultados, {this.falhaNaPrimeira = false});

  final List<MusicTrack> resultados;

  /// Faz a PRIMEIRA busca falhar — para exercitar a recuperação do erro.
  final bool falhaNaPrimeira;

  int buscas = 0;
  final List<String> termos = [];

  @override
  String get id => 'falso';

  @override
  Future<List<MusicTrack>> search(String query, {int limit = 20}) async {
    if (query.trim().length < 2) return const [];
    buscas++;
    termos.add(query);
    if (falhaNaPrimeira && buscas == 1) {
      throw MusicSearchError('Não consegui buscar agora.');
    }
    return resultados;
  }
}

const _faixa = MusicTrack(
  provider: 'itunes',
  externalId: '1440857781',
  title: 'Sozinho',
  artist: 'Caetano Veloso',
  album: 'Prenda Minha',
  durationMs: 222000,
);

Map<String, dynamic> _memoriaJson({List<Map<String, dynamic>> music = const []}) => {
      'id': 'm1',
      'title': 'Praia de Iracema',
      'text': 'O fim de tarde daqui.',
      'latitude': -3.72,
      'longitude': -38.51,
      'occurred_at': '2026-08-28T21:30:00Z',
      'created_at': '2026-08-28T21:30:00Z',
      'images': <dynamic>[],
      'music': music,
    };

const _salva = {
  'id': 'sm1',
  'provider': 'itunes',
  'external_id': '1440857781',
  'title': 'Sozinho',
  'artist': 'Caetano Veloso',
  'album': 'Prenda Minha',
  'duration_ms': 222000,
};

void main() {
  late http.Client original;

  setUp(() => Api.instance.debugSetToken('token'));
  tearDown(() => Api.instance.swapClient(original));

  Future<void> montar(
    WidgetTester tester, {
    required List<SavedTrack> tracks,
    MusicProvider? provider,
    Memory? Function()? aoMudar,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MemoryMusicSection(
              memoryId: 'm1',
              tracks: tracks,
              provider: provider,
              onChanged: (_) => aoMudar?.call(),
            ),
          ),
        ),
      ));

  group('sem música', () {
    testWidgets('convida, em vez de dizer "nenhum resultado"', (tester) async {
      original = Api.instance.swapClient(MockClient((_) async =>
          http.Response(jsonEncode(_memoriaJson()), 200,
              headers: {'content-type': 'application/json'})));

      await montar(tester, tracks: const []);

      expect(find.textContaining('se alguma tocava, ela cabe aqui'),
          findsOneWidget);
      expect(find.text('Escolher a música'.toUpperCase()), findsOneWidget);
    });
  });

  group('com música', () {
    final salva = SavedTrack.fromJson(Map<String, dynamic>.from(_salva));

    testWidgets('mostra faixa, artista, álbum e duração', (tester) async {
      original = Api.instance.swapClient(MockClient((_) async =>
          http.Response('{}', 200, headers: {'content-type': 'application/json'})));

      await montar(tester, tracks: [salva]);

      expect(find.text('Sozinho'), findsOneWidget);
      expect(find.textContaining('Caetano Veloso'), findsOneWidget);
      expect(find.textContaining('Prenda Minha'), findsOneWidget);
      expect(find.textContaining('3:42'), findsOneWidget);
    });

    testWidgets('no teto, some o convite e explica o limite', (tester) async {
      original = Api.instance.swapClient(MockClient((_) async =>
          http.Response('{}', 200, headers: {'content-type': 'application/json'})));

      final cinco = [
        for (var i = 0; i < 5; i++)
          SavedTrack.fromJson({..._salva, 'id': 's$i', 'external_id': '$i'})
      ];
      await montar(tester, tracks: cinco);

      expect(find.textContaining('trilha, não playlist'), findsOneWidget);
      expect(find.text('Outra música'.toUpperCase()), findsNothing,
          reason: 'a UI não convida para um 409');
    });

    testWidgets('remover avisa a tela dona com a memória atualizada',
        (tester) async {
      var avisou = false;
      original = Api.instance.swapClient(MockClient((req) async {
        expect(req.method, 'DELETE');
        expect(req.url.path, '/memories/m1/music/sm1');
        return http.Response(jsonEncode(_memoriaJson()), 200,
            headers: {'content-type': 'application/json'});
      }));

      await montar(tester, tracks: [salva], aoMudar: () {
        avisou = true;
        return null;
      });
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(avisou, isTrue,
          reason: 'sem isso a faixa some do servidor e fica na tela');
    });
  });

  group('busca', () {
    testWidgets('espera a digitação pausar antes de consultar', (tester) async {
      final catalogo = _CatalogoFalso([_faixa]);
      original = Api.instance.swapClient(MockClient((_) async =>
          http.Response('{}', 200, headers: {'content-type': 'application/json'})));

      await montar(tester, tracks: const [], provider: catalogo);
      await tester.tap(find.text('Escolher a música'.toUpperCase()));
      await tester.pumpAndSettle();

      // Alguém escrevendo "caetano", letra por letra.
      for (final parcial in ['ca', 'cae', 'caet', 'caeta', 'caetan', 'caetano']) {
        await tester.enterText(find.byType(EditableText).last, parcial);
        await tester.pump(const Duration(milliseconds: 80));
      }
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(catalogo.buscas, 1,
          reason: 'seis teclas, uma intenção — uma consulta só');
      expect(catalogo.termos.single, 'caetano');
    });

    testWidgets('escolher a faixa a envia para a API', (tester) async {
      final catalogo = _CatalogoFalso([_faixa]);
      Map<String, dynamic>? enviado;
      original = Api.instance.swapClient(MockClient((req) async {
        if (req.method == 'POST') {
          enviado = jsonDecode(req.body) as Map<String, dynamic>;
        }
        return http.Response(
          jsonEncode(_memoriaJson(music: [Map<String, dynamic>.from(_salva)])),
          req.method == 'POST' ? 201 : 200,
          headers: {'content-type': 'application/json'},
        );
      }));

      await montar(tester, tracks: const [], provider: catalogo);
      await tester.tap(find.text('Escolher a música'.toUpperCase()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'sozinho');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sozinho'));
      await tester.pumpAndSettle();

      expect(enviado, isNotNull, reason: 'a escolha precisa chegar ao servidor');
      expect(enviado!['external_id'], '1440857781');
      expect(enviado!['title'], 'Sozinho');
      expect(enviado!['provider'], 'itunes',
          reason: 'a origem vai junto, para reabrir a faixa depois');
    });

    testWidgets('busca curta não consulta o catálogo', (tester) async {
      final catalogo = _CatalogoFalso([_faixa]);
      original = Api.instance.swapClient(MockClient((_) async =>
          http.Response('{}', 200, headers: {'content-type': 'application/json'})));

      await montar(tester, tracks: const [], provider: catalogo);
      await tester.tap(find.text('Escolher a música'.toUpperCase()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'c');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(catalogo.buscas, 0, reason: 'uma letra é ruído, não consulta');
    });
  });

  group('recuperação de erro na busca', () {
    testWidgets('uma busca que falha não trava as seguintes', (tester) async {
      // O defeito: o erro antigo continuava na tela e, como o corpo testa erro
      // ANTES de spinner, a segunda busca nunca mostrava carregamento.
      final catalogo = _CatalogoFalso([_faixa], falhaNaPrimeira: true);
      original = Api.instance.swapClient(MockClient((_) async =>
          http.Response('{}', 200, headers: {'content-type': 'application/json'})));

      await montar(tester, tracks: const [], provider: catalogo);
      await tester.tap(find.text('Escolher a música'.toUpperCase()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText).last, 'sozinho');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.textContaining('Não consegui buscar'), findsOneWidget);

      await tester.enterText(find.byType(EditableText).last, 'caetano');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.textContaining('Não consegui buscar'), findsNothing,
          reason: 'o erro velho não pode sobreviver à busca seguinte');
      expect(find.text('Sozinho'), findsOneWidget,
          reason: 'a segunda busca precisa chegar à tela');
    });
  });
}
