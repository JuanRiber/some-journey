// Os números do Perfil como portas: o recorte que cada um abre, as listas
// por trás de "cidades", "países" e "dias no app", e os textos delas.
//
// A API é falada por um cliente HTTP falso — sem rede, sem backend de pé.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/features/collection/collection_domain.dart';

void main() {
  group('MemoryFilter', () {
    test('vazio não acrescenta nada à querystring', () {
      expect(MemoryFilter.all.isEmpty, isTrue);
      expect(MemoryFilter.all.toQuery(), isEmpty);
    });

    test('só entra o que recorta', () {
      expect(
        const MemoryFilter(city: 'Valencia', countryCode: 'ES').toQuery(),
        {'city': 'Valencia', 'country_code': 'ES'},
      );
      expect(const MemoryFilter(hasImages: true).toQuery(), {'has_images': 'true'});
      expect(
        const MemoryFilter(createdOn: '2026-03-10').toQuery(),
        {'created_on': '2026-03-10'},
      );
    });

    test('a cidade da lista abre com o país junto', () {
      const c = CityEntry(city: 'Valencia', countryCode: 'VE', memories: 2);
      expect(c.filter, const MemoryFilter(city: 'Valencia', countryCode: 'VE'));
    });
  });

  group('listas da coleção', () {
    test('país sem nome mostra o código, não uma linha vazia', () {
      const sem = CountryEntry(countryCode: 'PT', country: ' ', memories: 1, cities: 1);
      const com = CountryEntry(
          countryCode: 'PT', country: 'Portugal', memories: 1, cities: 1);
      expect(sem.name, 'PT');
      expect(com.name, 'Portugal');
    });

    test('Places lê as duas listas e tolera chave ausente', () {
      final p = Places.fromJson({
        'cities': [
          {'city': 'Fortaleza', 'country': 'Brasil', 'country_code': 'BR', 'memories': 3},
        ],
      });
      expect(p.cities.single.city, 'Fortaleza');
      expect(p.cities.single.memories, 3);
      expect(p.countries, isEmpty);
    });
  });

  group('textos dos dias', () {
    // Lidos como texto: o mesmo resultado em qualquer fuso (CI roda em UTC,
    // a máquina em America/Fortaleza).
    test('dia, semana e mês por extenso', () {
      expect(dayLabel('2026-03-10'), '10 de março de 2026');
      expect(weekdayLabel('2026-03-10'), 'terça');
      expect(weekdayLabel('2026-11-15'), 'domingo');
      expect(monthLabel('2026-12-01'), 'dezembro de 2026');
    });

    test('contagem no singular e no plural', () {
      expect(countLabel(1, 'memória', 'memórias'), '1 memória');
      expect(countLabel(0, 'memória', 'memórias'), '0 memórias');
      expect(countLabel(4, 'país', 'países'), '4 países');
    });
  });

  group('Api', () {
    late http.Client original;
    final chamadas = <Uri>[];

    setUp(() {
      chamadas.clear();
      Api.instance.debugSetToken('token-de-teste');
    });

    tearDown(() => Api.instance.swapClient(original));

    void responder(Object corpo, {Map<String, String> headers = const {}}) {
      original = Api.instance.swapClient(MockClient((req) async {
        chamadas.add(req.url);
        return http.Response(jsonEncode(corpo), 200,
            headers: {'content-type': 'application/json', ...headers});
      }));
    }

    test('listMemories leva o recorte e o cursor juntos', () async {
      responder(<dynamic>[]);
      await Api.instance.listMemories(
        cursor: 'abc=',
        filter: const MemoryFilter(city: 'São Paulo', countryCode: 'BR'),
      );
      final q = chamadas.single.queryParameters;
      expect(chamadas.single.path, endsWith('/memories'));
      expect(q['cursor'], 'abc=');
      expect(q['city'], 'São Paulo');
      expect(q['country_code'], 'BR');
      expect(q.containsKey('has_images'), isFalse);
    });

    test('getPlaces lê GET /me/places', () async {
      responder({
        'cities': <dynamic>[],
        'countries': [
          {'country_code': 'BR', 'country': 'Brasil', 'memories': 5, 'cities': 2},
        ],
      });
      final p = await Api.instance.getPlaces();
      expect(chamadas.single.path, endsWith('/me/places'));
      expect(p.countries.single.cities, 2);
    });

    test('getDays lê GET /me/days na ordem da API', () async {
      responder([
        {'day': '2026-05-02', 'memories': 1},
        {'day': '2026-03-10', 'memories': 2},
      ]);
      final days = await Api.instance.getDays();
      expect(chamadas.single.path, endsWith('/me/days'));
      expect(days.map((d) => d.day), ['2026-05-02', '2026-03-10']);
      expect(days.last.filter, const MemoryFilter(createdOn: '2026-03-10'));
    });
  });
}
