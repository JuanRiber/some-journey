// O que as telas de jornada SABEM, sem desenhar nada.
//
// A estante e a abertura do capítulo dividem estas regras, e era por estarem
// dentro de uma tela que elas não tinham teste nenhum: a mesma jornada se
// chamava "Ativa" numa e "Em curso" na outra, e a frase que o comentário
// prometia ("entre março e junho de 2026") nunca foi a que o código escrevia.

import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/features/journeys/journey_domain.dart';
import 'package:some_journey/models.dart';

Journey _jornada({
  String id = 'j1',
  String status = 'finished',
  String? inicio,
  String? fim,
  String criada = '2026-01-10T12:00:00Z',
  int momentos = 0,
}) =>
    Journey(
      id: id,
      title: 'Capítulo $id',
      isPrivate: true,
      status: status,
      startedAt: inicio,
      endedAt: fim,
      createdAt: criada,
      pointsCount: momentos,
    );

JourneyPoint _ponto(String id, {int? posicao, String titulo = 'Parada'}) =>
    JourneyPoint(
      memoryId: id,
      title: titulo,
      latitude: -3.7,
      longitude: -38.5,
      occurredAt: '2018-07-07T12:00:00Z',
      position: posicao,
      placeLabel: 'Fortaleza',
    );

Memory _memoria(
  String id, {
  String texto = '',
  List<String> fotos = const [],
  String? capa,
}) =>
    Memory(
      id: id,
      title: 'Memória $id',
      text: texto,
      latitude: -3.7,
      longitude: -38.5,
      occurredAt: '2018-07-07T12:00:00Z',
      createdAt: '2018-07-07T12:00:00Z',
      images: [
        for (var i = 0; i < fotos.length; i++)
          MemoryImage(id: '$id-$i', url: fotos[i]),
      ],
      imageUrl: capa,
    );

void main() {
  group('o período', () {
    test('mesmo mês: dito uma vez', () {
      final j = _jornada(
          inicio: '2018-07-05T12:00:00Z', fim: '2018-07-16T12:00:00Z');
      expect(journeyPeriodLabel(j), 'julho de 2018');
      expect(journeyPeriodPhrase(j), 'em julho de 2018');
    });

    test('mesmo ano: o ano aparece uma vez só', () {
      final j = _jornada(
          inicio: '2019-02-10T12:00:00Z', fim: '2019-07-20T12:00:00Z');
      expect(journeyPeriodLabel(j), 'fevereiro — julho de 2019');
      expect(journeyPeriodPhrase(j), 'entre fevereiro e julho de 2019');
    });

    test('atravessando a virada: cada ponta com o seu ano', () {
      final j = _jornada(
          inicio: '2019-11-02T12:00:00Z', fim: '2020-02-20T12:00:00Z');
      expect(journeyPeriodLabel(j), 'novembro de 2019 — fevereiro de 2020');
      expect(
          journeyPeriodPhrase(j), 'entre novembro de 2019 e fevereiro de 2020');
    });

    test('ainda aberta: desde quando', () {
      final j = _jornada(status: 'active', inicio: '2026-10-30T12:00:00Z');
      expect(journeyPeriodLabel(j), 'desde outubro de 2026');
      expect(journeyPeriodPhrase(j), 'desde outubro de 2026');
    });

    test('sem datas: quando foi aberta', () {
      final j = _jornada(status: 'draft', criada: '2026-11-24T12:00:00Z');
      expect(journeyPeriodLabel(j), 'novembro de 2026');
      expect(journeyPeriodPhrase(j), 'aberto em novembro de 2026');
    });

    test('o dia é o de UTC — o fuso do aparelho não puxa para a véspera', () {
      // Meia-noite UTC do dia 1º: em Fortaleza ainda é dia 31 do mês anterior.
      final j = _jornada(
          inicio: '2019-03-01T00:00:00Z', fim: '2019-03-01T00:00:00Z');
      expect(journeyPeriodLabel(j), 'março de 2019');
    });
  });

  group('a frase do capítulo', () {
    test('conta momentos, nunca "0 memórias"', () {
      expect(
        journeyChapterStory(
            _jornada(status: 'draft', criada: '2026-11-24T12:00:00Z')),
        'Um capítulo em branco, aberto em novembro de 2026 — esperando o '
        'primeiro momento.',
      );
      expect(
        journeyChapterStory(_jornada(
            momentos: 1,
            inicio: '2018-07-05T12:00:00Z',
            fim: '2018-07-16T12:00:00Z')),
        'Um momento registrado, em julho de 2018.',
      );
      expect(
        journeyChapterStory(_jornada(
            momentos: 4,
            inicio: '2019-02-10T12:00:00Z',
            fim: '2019-07-20T12:00:00Z')),
        '4 momentos registrados, entre fevereiro e julho de 2019.',
      );
    });

    test('a linha do card segue a mesma contagem', () {
      expect(journeyMomentsLine(_jornada()),
          'Ainda sem momentos — este capítulo está em branco');
      expect(journeyMomentsLine(_jornada(momentos: 1)), 'Um momento guardado');
      expect(journeyMomentsLine(_jornada(momentos: 7)), '7 momentos guardados');
    });
  });

  group('o estado', () {
    test('um vocabulário só, para a estante e para a abertura', () {
      expect(journeyStatusLabel('draft'), 'Rascunho');
      expect(journeyStatusLabel('active'), 'Em curso');
      expect(journeyStatusLabel('paused'), 'Em pausa');
      expect(journeyStatusLabel('finished'), 'Concluída');
    });

    test('estado desconhecido aparece como veio, em vez de sumir', () {
      expect(journeyStatusLabel('archived'), 'archived');
    });
  });

  group('a ação principal', () {
    test('rascunho: começar lidera, e o capítulo já aceita memória', () {
      final e = journeyStage('draft');
      expect(e.lead, JourneyAction.start);
      expect(e.quiet, isEmpty);
      expect(e.acceptsMemories, isTrue);
      expect(e.newMemoryLeads, isFalse);
    });

    test('em curso: a memória nova lidera; pausar e finalizar ficam discretos',
        () {
      final e = journeyStage('active');
      expect(e.lead, isNull);
      expect(e.quiet, [JourneyAction.pause, JourneyAction.finish]);
      expect(e.newMemoryLeads, isTrue);
    });

    test('em pausa: retomar lidera, finalizar fica discreto', () {
      final e = journeyStage('paused');
      expect(e.lead, JourneyAction.resume);
      expect(e.quiet, [JourneyAction.finish]);
      expect(e.newMemoryLeads, isFalse);
    });

    test('concluída: nenhuma ação, e o capítulo não recebe memória', () {
      final e = journeyStage('finished');
      expect(e.lead, isNull);
      expect(e.quiet, isEmpty);
      expect(e.acceptsMemories, isFalse);
      expect(e.newMemoryLeads, isFalse);
    });

    test('nunca há duas ações principais', () {
      for (final status in ['draft', 'active', 'paused', 'finished', 'outro']) {
        final e = journeyStage(status);
        final principais = [if (e.lead != null) 1, if (e.newMemoryLeads) 1];
        expect(principais.length, lessThanOrEqualTo(1), reason: status);
        expect(e.quiet, isNot(contains(e.lead)), reason: status);
      }
    });

    test('estado desconhecido: nenhuma transição oferecida', () {
      final e = journeyStage('archived');
      expect(e.lead, isNull);
      expect(e.quiet, isEmpty);
      expect(e.acceptsMemories, isTrue);
    });

    test('cada ação tem um nome de botão', () {
      expect(journeyActionLabel(JourneyAction.start), 'Iniciar jornada');
      expect(journeyActionLabel(JourneyAction.pause), 'Pausar');
      expect(journeyActionLabel(JourneyAction.resume), 'Retomar jornada');
      expect(journeyActionLabel(JourneyAction.finish), 'Finalizar jornada');
    });
  });

  group('a ordem da estante', () {
    test('em curso abre, depois a em pausa, as guardadas, e os rascunhos no fim',
        () {
      final ordem = shelfOrder([
        _jornada(id: 'rascunho', status: 'draft'),
        _jornada(id: 'guardada', status: 'finished'),
        _jornada(id: 'pausada', status: 'paused'),
        _jornada(id: 'viva', status: 'active'),
      ]);
      expect([for (final j in ordem) j.id],
          ['viva', 'pausada', 'guardada', 'rascunho']);
    });

    test('dentro de cada grupo, a ordem da API fica como veio', () {
      final ordem = shelfOrder([
        _jornada(id: 'c', status: 'finished'),
        _jornada(id: 'r2', status: 'draft'),
        _jornada(id: 'a', status: 'finished'),
        _jornada(id: 'r1', status: 'draft'),
        _jornada(id: 'b', status: 'finished'),
      ]);
      expect([for (final j in ordem) j.id], ['c', 'a', 'b', 'r2', 'r1']);
    });

    test('não mexe na lista que recebeu', () {
      final original = [
        _jornada(id: 'rascunho', status: 'draft'),
        _jornada(id: 'viva', status: 'active'),
      ];
      shelfOrder(original);
      expect(original.first.id, 'rascunho');
    });

    test('estado desconhecido fica entre as guardadas, não some', () {
      final ordem = shelfOrder([
        _jornada(id: 'rascunho', status: 'draft'),
        _jornada(id: 'estranha', status: 'archived'),
        _jornada(id: 'viva', status: 'active'),
      ]);
      expect([for (final j in ordem) j.id], ['viva', 'estranha', 'rascunho']);
    });

    test('o destaque é o capítulo que está sendo vivido', () {
      final comViva = shelfOrder([
        _jornada(id: 'guardada'),
        _jornada(id: 'viva', status: 'active'),
      ]);
      expect(shelfLead(comViva)?.id, 'viva');

      final soPausada = shelfOrder([
        _jornada(id: 'guardada'),
        _jornada(id: 'pausada', status: 'paused'),
      ]);
      expect(shelfLead(soPausada)?.id, 'pausada');
    });

    test('sem nada em curso, ninguém é destaque', () {
      expect(shelfLead(shelfOrder([_jornada(), _jornada(status: 'draft')])),
          isNull);
      expect(shelfLead(const []), isNull);
    });
  });

  group('o roteiro', () {
    test('a ordem é a do rastro, não a das memórias', () {
      final paradas = itineraryStops(
        [_ponto('b', posicao: 1), _ponto('a', posicao: 2)],
        [_memoria('a'), _memoria('b')],
      );
      expect([for (final p in paradas) p.memoryId], ['b', 'a']);
      expect([for (final p in paradas) p.number], [1, 2]);
    });

    test('sem posição vinda da API, conta pela ordem', () {
      final paradas = itineraryStops([_ponto('a'), _ponto('b')], const []);
      expect([for (final p in paradas) p.number], [1, 2]);
    });

    test('a memória dá a foto, a contagem e o texto', () {
      final parada = itineraryStops(
        [_ponto('a', posicao: 1)],
        [
          _memoria('a',
              capa: 'https://x.test/1.jpg',
              fotos: ['https://x.test/1.jpg', 'https://x.test/2.jpg'],
              texto: 'Subimos no escuro.\n\n  De lanterna.'),
        ],
      ).single;
      expect(parada.hasPhoto, isTrue);
      expect(parada.photoUrl, 'https://x.test/1.jpg');
      expect(parada.photoCount, 2);
      expect(parada.excerpt, 'Subimos no escuro. De lanterna.');
    });

    test('sem a capa pronta, vale a primeira foto da memória', () {
      final parada = itineraryStops(
        [_ponto('a')],
        [_memoria('a', fotos: ['https://x.test/9.jpg'])],
      ).single;
      expect(parada.photoUrl, 'https://x.test/9.jpg');
    });

    test('memória que não chegou não tira a parada do roteiro', () {
      final paradas = itineraryStops(
        [_ponto('a', titulo: 'Morro'), _ponto('b', titulo: 'Poço')],
        [_memoria('b', capa: 'https://x.test/b.jpg')],
      );
      expect(paradas, hasLength(2));
      expect(paradas.first.title, 'Morro');
      expect(paradas.first.hasPhoto, isFalse);
      expect(paradas.first.photoCount, 0);
      expect(paradas.first.excerpt, '');
      expect(paradas.first.placeLabel, 'Fortaleza');
      expect(paradas.last.hasPhoto, isTrue);
    });

    test('título em branco não conta como título', () {
      final parada =
          itineraryStops([_ponto('a', titulo: '   ')], const []).single;
      expect(parada.hasTitle, isFalse);
    });

    test('sem pontos, sem paradas', () {
      expect(itineraryStops(const [], [_memoria('a')]), isEmpty);
    });
  });

  group('a data da parada', () {
    test('dia, mês curto e ano', () {
      expect(stopDateLabel('2018-07-07T12:00:00Z'), '07 JUL 2018');
      expect(stopDateLabel('2026-11-01T12:00:00Z'), '01 NOV 2026');
    });

    test('pelas partes UTC, em qualquer fuso', () {
      // 01h de UTC: em Fortaleza (UTC-3) ainda seria a véspera.
      expect(stopDateLabel('2019-03-02T01:00:00Z'), '02 MAR 2019');
      // E um horário com offset é levado para UTC antes de ler o dia.
      expect(stopDateLabel('2019-03-01T22:00:00-03:00'), '02 MAR 2019');
    });
  });

  group('trocar a ordem', () {
    const ids = ['a', 'b', 'c'];

    test('sobe e desce trocando com a vizinha', () {
      expect(movedOrder(ids, 1, -1), ['b', 'a', 'c']);
      expect(movedOrder(ids, 1, 1), ['a', 'c', 'b']);
    });

    test('a primeira não sobe, a última não desce', () {
      expect(movedOrder(ids, 0, -1), isNull);
      expect(movedOrder(ids, 2, 1), isNull);
    });

    test('índice fora da lista não inventa ordem', () {
      expect(movedOrder(ids, 5, -1), isNull);
      expect(movedOrder(ids, -1, 1), isNull);
      expect(movedOrder(const [], 0, 1), isNull);
    });

    test('não mexe na lista que recebeu', () {
      final original = ['a', 'b', 'c'];
      movedOrder(original, 0, 1);
      expect(original, ['a', 'b', 'c']);
    });
  });
}
