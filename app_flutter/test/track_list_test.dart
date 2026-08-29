// Lista de trechos gravados: o que a pessoa lê e o que acontece ao remover.
//
// A remoção é destrutiva e irreversível — o backend apaga o trecho de verdade.
// Por isso a confirmação em dois passos é comportamento, não enfeite, e é o que
// estes testes travam: um toque errado não pode apagar um caminho.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/features/tracks/track_list.dart';
import 'package:some_journey/models.dart';

JourneyTrack _track({
  String id = 't1',
  int pontos = 12,
  double metros = 272,
  bool ativo = false,
  String inicio = '2026-08-28T18:57:00-03:00',
  String? fim = '2026-08-28T19:24:00-03:00',
}) =>
    JourneyTrack(
      id: id,
      journeyId: 'j1',
      source: 'gps_live',
      startedAt: inicio,
      endedAt: fim,
      isActive: ativo,
      pointCount: pontos,
      distanceMeters: metros,
    );

Future<void> _montar(
  WidgetTester tester,
  List<JourneyTrack> tracks, {
  Future<void> Function(JourneyTrack)? onDelete,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TrackList(
            tracks: tracks,
            onDelete: onDelete ?? (_) async {},
          ),
        ),
      ),
    ));

void main() {
  testWidgets('sem trechos, não ocupa espaço nenhum', (tester) async {
    await _montar(tester, const []);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.textContaining('trecho'), findsNothing);
  });

  testWidgets('mostra distância, pontos e duração do trecho', (tester) async {
    await _montar(tester, [_track()]);

    expect(find.text('trecho gravado'.toUpperCase()), findsOneWidget);
    // A linha do trecho junta os três dados; o resumo acima também cita a
    // distância, por isso o assert casa a linha inteira e não só "272 m".
    expect(find.textContaining('272 m · 12 pontos · 27 min'), findsOneWidget,
        reason: 'de 18:57 a 19:24 são 27 minutos');
    expect(find.textContaining('Um caminho de 272 m'), findsOneWidget);
    // A hora é a do relógio de parede de quem gravou. O esperado é CALCULADO
    // com o mesmo fuso do ambiente — cravar '18:57' faria o teste passar só em
    // quem roda em UTC-3 e quebrar em qualquer CI.
    final local = DateTime.parse('2026-08-28T18:57:00-03:00').toLocal();
    final hhmm = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    expect(find.textContaining('· $hhmm'), findsOneWidget,
        reason: 'a hora exibida é a local, não UTC');
  });

  testWidgets('vários trechos somam como um caminho só', (tester) async {
    await _montar(tester, [
      _track(id: 'a', metros: 1200),
      _track(id: 'b', metros: 800),
    ]);

    expect(find.text('2 trechos gravados'.toUpperCase()), findsOneWidget);
    expect(find.textContaining('2,0 km'), findsOneWidget,
        reason: 'a leitura que importa é a soma dos trechos');
  });

  testWidgets('o trecho em gravação se identifica', (tester) async {
    await _montar(tester, [_track(ativo: true, fim: null)]);
    expect(find.text('gravando'.toUpperCase()), findsOneWidget);
  });

  group('remoção', () {
    testWidgets('um toque não apaga — pede confirmação primeiro',
        (tester) async {
      var chamou = false;
      await _montar(tester, [_track()], onDelete: (_) async => chamou = true);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(chamou, isFalse, reason: 'nada pode ser apagado num toque só');
      expect(find.textContaining('Remover este trecho?'), findsOneWidget);
      expect(find.textContaining('As memórias da jornada ficam'), findsOneWidget,
          reason: 'a confirmação precisa dizer o que NÃO se perde');
    });

    testWidgets('confirmar remove o trecho certo', (tester) async {
      JourneyTrack? removido;
      await _montar(
        tester,
        [_track(id: 'a'), _track(id: 'b')],
        onDelete: (t) async => removido = t,
      );

      // O segundo trecho da lista.
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pump();
      await tester.tap(find.text('Remover'.toUpperCase()));
      await tester.pump();

      expect(removido?.id, 'b');
    });

    testWidgets('manter desiste sem chamar nada', (tester) async {
      var chamou = false;
      await _montar(tester, [_track()], onDelete: (_) async => chamou = true);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.tap(find.text('Manter'));
      await tester.pump();

      expect(chamou, isFalse);
      expect(find.textContaining('Remover este trecho?'), findsNothing,
          reason: 'desistir fecha a confirmação');
    });

    testWidgets('confirma um de cada vez', (tester) async {
      await _montar(tester, [_track(id: 'a'), _track(id: 'b')]);

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pump();

      expect(find.textContaining('Remover este trecho?'), findsOneWidget,
          reason: 'duas confirmações abertas convidam ao engano');
    });
  });
}
