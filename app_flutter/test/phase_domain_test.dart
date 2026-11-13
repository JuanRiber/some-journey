// Fases da vida — as regras que a tela usa e que nenhum widget deveria
// precisar montar para provar.
//
// Duas guardam o que mais custaria caro errar em silêncio: o PATCH da fase,
// onde `null` LIMPA (o contrário do PATCH de jornada), e o vínculo, onde
// mandar o campo sem mudança seria uma armadilha esperando duas telas
// editarem a mesma memória.

import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/features/phases/phase_domain.dart';

LifePhase _fase({
  String id = 'f1',
  String name = 'Faculdade',
  String? description,
  PhaseColor color = PhaseColor.accent,
  String? startedOn,
  String? endedOn,
}) =>
    LifePhase(
      id: id,
      name: name,
      description: description,
      color: color,
      startedOn: startedOn,
      endedOn: endedOn,
    );

void main() {
  group('PhaseColor', () {
    test('lê os papéis da paleta pelo mesmo nome do backend', () {
      for (final c in PhaseColor.values) {
        expect(PhaseColor.parse(c.name), c);
      }
    });

    test('um papel desconhecido cai na padrão em vez de quebrar a lista', () {
      // Uma cor nova no backend antes de o app aprender não pode derrubar a
      // leitura de todas as fases.
      expect(PhaseColor.parse('ultravioleta'), PhaseColor.standard);
      expect(PhaseColor.parse(null), PhaseColor.standard);
      expect(PhaseColor.standard, PhaseColor.accent, reason: 'COR_PADRAO do backend');
    });
  });

  group('LifePhase.fromJson', () {
    test('lê a fase como a API devolve', () {
      final f = LifePhase.fromJson({
        'id': 'f1',
        'name': 'Intercâmbio',
        'description': 'Um semestre em Lisboa',
        'color': 'moss',
        'started_at': '2019-02-01T12:00:00Z',
        'ended_at': null,
        'created_at': '2026-11-10T10:00:00Z',
      });
      expect(f.name, 'Intercâmbio');
      expect(f.color, PhaseColor.moss);
      expect(f.startedOn, '2019-02-01');
      expect(f.endedOn, isNull, reason: 'é a fase em curso');
    });

    test('o dia sai das partes UTC, não do fuso do aparelho', () {
      // Meio-dia UTC é a âncora que o app grava; com offset explícito o dia
      // UTC continua sendo o mesmo — em Fortaleza e no CI.
      final f = LifePhase.fromJson({
        'id': 'f1',
        'name': 'X',
        'started_at': '2019-02-01T09:00:00-03:00',
        'ended_at': '2020-12-31T12:00:00+00:00',
      });
      expect(f.startedOn, '2019-02-01');
      expect(f.endedOn, '2020-12-31');
    });
  });

  group('período', () {
    test('as quatro formas de um capítulo', () {
      expect(_fase(startedOn: '2015-03-01', endedOn: '2019-12-01').period,
          '2015 — 2019');
      expect(_fase(startedOn: '2024-01-01').period, 'desde 2024');
      expect(_fase(endedOn: '2010-06-01').period, 'até 2010');
      expect(_fase().period, '', reason: 'sem período é permitido e não inventa um');
    });

    test('começo e fim no mesmo ano viram um ano só', () {
      expect(_fase(startedOn: '2019-02-01', endedOn: '2019-07-01').period, '2019');
    });
  });

  group('validatePhase', () {
    test('só o nome é obrigatório', () {
      expect(validatePhase(name: 'Recomeços'), isNull);
      expect(validatePhase(name: '   '), 'Dê um nome a esta fase.');
    });

    test('o teto do nome é o do backend', () {
      expect(validatePhase(name: 'a' * phaseNameMax), isNull);
      expect(validatePhase(name: 'a' * (phaseNameMax + 1)), contains('60'));
    });

    test('terminar antes de começar é recusado; em aberto, não', () {
      expect(
        validatePhase(name: 'X', startedOn: '2020-01-01', endedOn: '2019-12-31'),
        'Uma fase não pode terminar antes de começar.',
      );
      expect(validatePhase(name: 'X', startedOn: '2020-01-01'), isNull);
      expect(validatePhase(name: 'X', endedOn: '2020-01-01'), isNull);
      expect(
        validatePhase(name: 'X', startedOn: '2020-01-01', endedOn: '2020-01-01'),
        isNull,
        reason: 'uma fase de um dia é estranha, mas não é incoerente',
      );
    });
  });

  group('phaseCreateBody', () {
    test('manda só o que foi preenchido, com o dia ancorado ao meio-dia UTC', () {
      expect(
        phaseCreateBody(name: '  Faculdade ', startedOn: '2015-03-01'),
        {
          'name': 'Faculdade',
          'color': 'accent',
          'started_at': '2015-03-01T12:00:00Z',
        },
      );
    });

    test('com tudo preenchido', () {
      expect(
        phaseCreateBody(
          name: 'Intercâmbio',
          description: ' Lisboa ',
          color: PhaseColor.secondary,
          startedOn: '2019-02-01',
          endedOn: '2019-07-01',
        ),
        {
          'name': 'Intercâmbio',
          'description': 'Lisboa',
          'color': 'secondary',
          'started_at': '2019-02-01T12:00:00Z',
          'ended_at': '2019-07-01T12:00:00Z',
        },
      );
    });
  });

  group('phasePatch', () {
    final original = _fase(
      name: 'Faculdade',
      description: 'Os anos de Recife',
      color: PhaseColor.moss,
      startedOn: '2015-03-01',
      endedOn: '2019-12-01',
    );

    Map<String, dynamic> patch({
      String name = 'Faculdade',
      String description = 'Os anos de Recife',
      PhaseColor color = PhaseColor.moss,
      String startedOn = '2015-03-01',
      String endedOn = '2019-12-01',
    }) =>
        phasePatch(original,
            name: name,
            description: description,
            color: color,
            startedOn: startedOn,
            endedOn: endedOn);

    test('sem mudança, corpo vazio — o botão fica apagado', () {
      expect(patch(), isEmpty);
    });

    test('só o que mudou vai', () {
      expect(patch(name: 'Graduação', color: PhaseColor.primary),
          {'name': 'Graduação', 'color': 'primary'});
    });

    test('apagar a data de fim manda null — e é isso que a reabre', () {
      // Aqui null LIMPA. Mandar nada deixaria a fase encerrada; mandar ""
      // seria um 422 numa data.
      final p = patch(endedOn: '');
      expect(p.keys, ['ended_at']);
      expect(p['ended_at'], isNull);
    });

    test('apagar a descrição manda null', () {
      final p = patch(description: '  ');
      expect(p.keys, ['description']);
      expect(p['description'], isNull);
    });

    test('mudar uma data manda o novo dia ancorado', () {
      expect(patch(startedOn: '2014-08-01'),
          {'started_at': '2014-08-01T12:00:00Z'});
    });
  });

  group('phaseLinkPatch', () {
    test('sem mudança não manda o campo', () {
      expect(phaseLinkPatch(null, null), isEmpty);
      expect(phaseLinkPatch('f1', 'f1'), isEmpty);
    });

    test('marcar, trocar e soltar', () {
      expect(phaseLinkPatch(null, 'f1'), {'life_phase_id': 'f1'});
      expect(phaseLinkPatch('f1', 'f2'), {'life_phase_id': 'f2'});
      // Soltar é mandar null EXPLÍCITO: a chave precisa estar lá.
      final soltar = phaseLinkPatch('f1', null);
      expect(soltar.containsKey('life_phase_id'), isTrue);
      expect(soltar['life_phase_id'], isNull);
    });
  });

  group('lente', () {
    final fases = [_fase(id: 'a', name: 'Infância'), _fase(id: 'b', name: 'Faculdade')];

    test('a fase escolhida continua enquanto existir', () {
      expect(lensFor(fases, 'b'), 'b');
      expect(lensFor(fases, null), isNull);
    });

    test('a fase apagada noutra tela devolve a vida toda', () {
      expect(lensFor(fases, 'apagada'), isNull);
      expect(lensFor(const [], 'a'), isNull);
    });

    test('phaseById', () {
      expect(phaseById(fases, 'a')!.name, 'Infância');
      expect(phaseById(fases, 'z'), isNull);
      expect(phaseById(fases, null), isNull);
    });
  });
}
