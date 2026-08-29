// O corpo do PATCH de uma jornada: o que vai e o que fica de fora.
//
// Duas regras do backend que estes testes travam, porque errar qualquer uma
// delas falha em SILÊNCIO — a pessoa salva, nada acontece, e não há erro:
//
//  1. Campo ausente não é tocado. Mandar tudo sempre sobrescreveria trabalho
//     alheio à toa.
//  2. `null` NÃO limpa. O repositório faz `if description is not None`, então
//     apagar um texto exige mandar string vazia. Mandar null, que seria o
//     intuitivo, faz o texto antigo voltar.

import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/models.dart';
import 'package:some_journey/screens/journey_edit.dart';

Journey _journey({
  String title = 'Mochilão',
  String? description = 'Três meses de estrada',
  String? mood = 'leve',
  bool isPrivate = true,
}) =>
    Journey(
      id: 'j1',
      title: title,
      description: description,
      mood: mood,
      status: 'active',
      isPrivate: isPrivate,
      pointsCount: 3,
      createdAt: '2026-06-01T12:00:00Z',
    );

/// Chama o patch com os valores atuais da jornada, sobrescrevendo só o que o
/// teste quer mudar — assim cada caso fala de UMA edição.
Map<String, dynamic> _patch(
  Journey o, {
  String? title,
  String? description,
  String? mood,
  bool? isPrivate,
}) =>
    journeyPatch(
      o,
      title: title ?? o.title,
      description: description ?? o.description ?? '',
      mood: mood ?? o.mood ?? '',
      isPrivate: isPrivate ?? o.isPrivate,
    );

void main() {
  group('nada mudou', () {
    test('devolve um patch vazio', () {
      expect(_patch(_journey()), isEmpty);
    });

    test('espaço em volta não conta como edição', () {
      final o = _journey();
      expect(_patch(o, title: '  Mochilão  '), isEmpty,
          reason: 'o valor é comparado já aparado');
    });

    test('campos nulos na origem equivalem a campos vazios na tela', () {
      final o = _journey(description: null, mood: null);
      expect(_patch(o), isEmpty,
          reason: 'a tela mostra "" para um campo nulo; isso não é uma mudança');
    });
  });

  group('só o que mudou entra', () {
    test('editar o título manda apenas o título', () {
      final p = _patch(_journey(), title: 'Mochilão pela Europa');
      expect(p, {'title': 'Mochilão pela Europa'});
    });

    test('trocar a privacidade manda apenas ela', () {
      expect(_patch(_journey(), isPrivate: false), {'is_private': false});
    });

    test('duas edições vão juntas', () {
      final p = _patch(_journey(), title: 'Outro nome', mood: 'intenso');
      expect(p, {'title': 'Outro nome', 'mood': 'intenso'});
    });

    test('o título é aparado antes de ir', () {
      expect(_patch(_journey(), title: '  Novo  '), {'title': 'Novo'});
    });
  });

  group('apagar um campo', () {
    test('descrição limpa vai como string vazia, nunca null', () {
      final p = _patch(_journey(), description: '');
      expect(p.containsKey('description'), isTrue);
      expect(p['description'], '',
          reason: 'null seria ignorado pelo backend e o texto voltaria');
      expect(p['description'], isNot(isNull));
    });

    test('atmosfera limpa também', () {
      expect(_patch(_journey(), mood: ''), {'mood': ''});
    });

    test('limpar o que já era nulo não vira edição', () {
      final o = _journey(description: null);
      expect(_patch(o, description: ''), isEmpty);
    });

    test('só espaços equivale a apagar', () {
      expect(_patch(_journey(), description: '   '), {'description': ''});
    });
  });

  group('privacidade', () {
    test('false é enviado — não é confundido com ausência', () {
      final o = _journey(isPrivate: true);
      final p = journeyPatch(o,
          title: o.title, description: '', mood: '', isPrivate: false);
      expect(p['is_private'], false);
      expect(p.containsKey('is_private'), isTrue,
          reason: 'um bool falso é um valor, não a falta de um');
    });

    test('voltar para privada também é enviado', () {
      expect(_patch(_journey(isPrivate: false), isPrivate: true),
          {'is_private': true});
    });
  });
}
