// Leitura do Perfil — fixada contra respostas REAIS de GET /me/profile.
//
// As duas cargas abaixo saíram de um servidor de verdade (FastAPI + PostGIS):
// uma conta com história (memórias geocodificadas, foto, música salva, percurso
// gravado e jornada em andamento) e uma recém-criada. Um JSON escrito a partir
// da minha leitura do schema validaria o meu entendimento, não o contrato — e é
// justamente no parse que uma mudança no backend chega CALADA: campo renomeado,
// nulo onde havia objeto, contador novo dentro de `stats`. O resultado é tela
// quebrada ou, pior, número errado com cara de certo.
//
// Regra que atravessa o arquivo: o Perfil é a primeira coisa que a pessoa abre
// depois do login, então falta de campo opcional NUNCA pode virar exceção.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/features/profile/profile_models.dart';

/// Conta com história. Capturada do servidor; o fuso vem como offset (-03:00)
/// porque a máquina que gravou não roda em UTC — e é exatamente esse formato
/// que o app recebe em produção.
///
/// Os dez contadores de `stats` são todos DIFERENTES entre si de propósito: com
/// dois valores iguais, trocar duas chaves de lugar na leitura passaria batido.
const _respostaReal = '''
{
  "identity": {
    "id": "e25b96f0-f66d-4aac-a32f-42dfe3322005",
    "name": "Juan Pedro Ribeiro",
    "email": "u_d33265c364@test.com",
    "joined_at": "2026-10-11T01:19:05.515328-03:00",
    "member_since": "2026-03-14T12:42:09.118374-03:00",
    "username": "juanviaja",
    "avatar_url": null,
    "bio": "Colecionando pôres do sol e trilhas no litoral."
  },
  "stats": {
    "memories": 12,
    "journeys": 4,
    "journeys_finished": 3,
    "cities": 7,
    "countries": 5,
    "continents": 2,
    "photos": 9,
    "tracks": 6,
    "tracked_meters": 313.4808553694319,
    "active_days": 8,
    "pending_geocode": 1
  },
  "passport": [
    {"continent": "América do Sul", "visited": true},
    {"continent": "América do Norte", "visited": false},
    {"continent": "Europa", "visited": true},
    {"continent": "África", "visited": false},
    {"continent": "Ásia", "visited": false},
    {"continent": "Oceania", "visited": false},
    {"continent": "Antártida", "visited": false}
  ],
  "last_adventure": {
    "city": "Paris",
    "country": "França",
    "country_code": "FR",
    "occurred_at": "2026-08-09T15:10:00-03:00"
  },
  "current_journey": {
    "id": "b2e7073d-05cf-431d-ad9c-d8555762eb77",
    "title": "Verão no Ceará",
    "started_at": "2026-10-11T01:19:07.385919-03:00",
    "points_count": 2
  }
}
''';

/// Conta recém-criada, também capturada: o outro extremo do contrato. Tudo
/// zerado, passaporte inteiro por explorar, os dois blocos opcionais nulos.
const _respostaContaNova = '''
{
  "identity": {
    "id": "5c406694-961f-4a11-845d-d25f4c57a825",
    "name": "Ana",
    "email": "u_c8a58f8ad6@test.com",
    "joined_at": "2026-10-11T01:15:08.206551-03:00",
    "member_since": null,
    "username": null,
    "avatar_url": null,
    "bio": null
  },
  "stats": {
    "memories": 0,
    "journeys": 0,
    "journeys_finished": 0,
    "cities": 0,
    "countries": 0,
    "continents": 0,
    "photos": 0,
    "tracks": 0,
    "tracked_meters": 0.0,
    "active_days": 0,
    "pending_geocode": 0
  },
  "passport": [
    {"continent": "América do Sul", "visited": false},
    {"continent": "América do Norte", "visited": false},
    {"continent": "Europa", "visited": false},
    {"continent": "África", "visited": false},
    {"continent": "Ásia", "visited": false},
    {"continent": "Oceania", "visited": false},
    {"continent": "Antártida", "visited": false}
  ],
  "last_adventure": null,
  "current_journey": null
}
''';

/// Cópia fresca da carga a cada uso — cada teste mexe na sua sem contaminar o
/// vizinho.
Map<String, dynamic> _real() =>
    jsonDecode(_respostaReal) as Map<String, dynamic>;

Map<String, dynamic> _contaNova() =>
    jsonDecode(_respostaContaNova) as Map<String, dynamic>;

/// Bloco interno da carga, pronto para ser podado ou adulterado.
Map<String, dynamic> _bloco(Map<String, dynamic> carga, String nome) =>
    carga[nome] as Map<String, dynamic>;

void main() {
  group('payload completo', () {
    test('identidade atravessa a fronteira inteira', () {
      final p = Profile.fromJson(_real());

      expect(p.identity.id, 'e25b96f0-f66d-4aac-a32f-42dfe3322005');
      expect(p.identity.name, 'Juan Pedro Ribeiro');
      expect(p.identity.email, 'u_d33265c364@test.com');
      expect(p.identity.username, 'juanviaja');
      expect(p.identity.bio, 'Colecionando pôres do sol e trilhas no litoral.');
      expect(p.identity.avatarUrl, isNull);
    });

    test('data com offset vira UTC — a tela não pode reinterpretar no fuso local', () {
      final p = Profile.fromJson(_real());

      // 01:19 em -03:00 é 04:19 em UTC. Se isto virar hora local, "Explorador
      // desde <ano>" erra na virada do ano e a última aventura muda de dia.
      expect(p.identity.joinedAt.isUtc, isTrue);
      expect(p.identity.joinedAt,
          DateTime.utc(2026, 10, 11, 4, 19, 5, 515, 328));
      // member_since é a PRIMEIRA memória, bem anterior ao cadastro nesta conta.
      expect(p.identity.memberSince,
          DateTime.utc(2026, 3, 14, 15, 42, 9, 118, 374));
    });

    test('cada contador de stats chega no campo certo', () {
      final s = Profile.fromJson(_real()).stats;

      expect(s.memories, 12);
      expect(s.journeys, 4);
      expect(s.journeysFinished, 3);
      expect(s.cities, 7);
      expect(s.countries, 5);
      expect(s.continents, 2);
      expect(s.photos, 9);
      expect(s.activeDays, 8);
      expect(s.pendingGeocode, 1);
      expect(s.trackedMeters, closeTo(313.48, 0.01));
      expect(s.isEmpty, isFalse);
    });

    test('passaporte traz TODOS os continentes, carimbados ou não', () {
      final p = Profile.fromJson(_real());

      // O vazio é convite, não ausência de dado: a lista não pode vir filtrada.
      expect(p.passport, hasLength(7));
      expect(p.passport.first.continent, 'América do Sul');
      expect(p.passport.first.visited, isTrue);
      expect(p.passport.where((c) => c.visited).map((c) => c.continent),
          ['América do Sul', 'Europa']);
      expect(p.passport.last.continent, 'Antártida');
      expect(p.passport.last.visited, isFalse);
    });

    test('última aventura e jornada atual', () {
      final p = Profile.fromJson(_real());

      expect(p.lastAdventure!.city, 'Paris');
      expect(p.lastAdventure!.country, 'França');
      expect(p.lastAdventure!.countryCode, 'FR');
      expect(p.lastAdventure!.occurredAt, DateTime.utc(2026, 8, 9, 18, 10));
      expect(p.lastAdventure!.label, 'Paris, França');

      expect(p.currentJourney!.id, 'b2e7073d-05cf-431d-ad9c-d8555762eb77');
      expect(p.currentJourney!.title, 'Verão no Ceará');
      expect(p.currentJourney!.pointsCount, 2);
      expect(p.currentJourney!.startedAt,
          DateTime.utc(2026, 10, 11, 4, 19, 7, 385, 919));
    });

    test('conta recém-criada: tudo zero, nenhum bloco opcional, sem explosão', () {
      final p = Profile.fromJson(_contaNova());

      expect(p.stats.isEmpty, isTrue);
      expect(p.stats.trackedMeters, 0);
      expect(p.identity.username, isNull);
      expect(p.identity.bio, isNull);
      expect(p.identity.memberSince, isNull);
      expect(p.lastAdventure, isNull);
      expect(p.currentJourney, isNull);
      expect(p.passport, hasLength(7));
      expect(p.passport.every((c) => !c.visited), isTrue);
    });
  });

  group('campos opcionais ausentes', () {
    // Pydantic manda a chave com null, mas um backend mais novo (ou um mock, ou
    // uma resposta cortada por proxy) pode simplesmente OMITIR. As duas formas
    // têm que dar no mesmo.
    test('identidade sem avatar, bio e @username não quebra', () {
      final carga = _real();
      _bloco(carga, 'identity')
        ..remove('avatar_url')
        ..remove('bio')
        ..remove('username')
        ..remove('member_since');

      final p = Profile.fromJson(carga);

      expect(p.identity.avatarUrl, isNull);
      expect(p.identity.bio, isNull);
      expect(p.identity.username, isNull);
      expect(p.identity.memberSince, isNull);
      // O que não é opcional continua lá.
      expect(p.identity.name, 'Juan Pedro Ribeiro');
      expect(p.identity.joinedAt, isNotNull);
    });

    test('nome e e-mail nulos viram texto vazio, não null', () {
      // A tela concatena esses dois em Text(); null ali seria crash de render.
      final carga = _real();
      _bloco(carga, 'identity')
        ..['name'] = null
        ..['email'] = null;

      final identity = Profile.fromJson(carga).identity;

      expect(identity.name, '');
      expect(identity.email, '');
      expect(identity.initials, '?');
    });

    test('avatar assinado é lido como veio (URL temporária do bucket privado)', () {
      // A captura real traz null porque o Storage fica desabilitado em teste; em
      // produção vem a URL ASSINADA, com query string e tudo.
      const assinada =
          'https://projeto.supabase.co/storage/v1/object/sign/media/avatars/e25b.jpg?token=abc.def';
      final carga = _real();
      _bloco(carga, 'identity')['avatar_url'] = assinada;

      expect(Profile.fromJson(carga).identity.avatarUrl, assinada);
    });

    test('passaporte ausente vira lista vazia', () {
      final carga = _real()..remove('passport');

      expect(Profile.fromJson(carga).passport, isEmpty);
    });

    test('blocos opcionais omitidos (não só nulos) somem sem erro', () {
      final carga = _real()
        ..remove('last_adventure')
        ..remove('current_journey');

      final p = Profile.fromJson(carga);

      expect(p.lastAdventure, isNull);
      expect(p.currentJourney, isNull);
    });

    test('última aventura sem cidade ainda rotula o país', () {
      // Memória geocodificada só até o país: o cartão mostra "França", não
      // ", França" nem string vazia.
      final carga = _real();
      _bloco(carga, 'last_adventure')
        ..['city'] = null
        ..['occurred_at'] = null;

      final a = Profile.fromJson(carga).lastAdventure!;

      expect(a.label, 'França');
      expect(a.occurredAt, isNull);
    });

    test('última aventura sem lugar nenhum tem rótulo vazio', () {
      final carga = _real();
      _bloco(carga, 'last_adventure')
        ..['city'] = null
        ..['country'] = null;

      expect(Profile.fromJson(carga).lastAdventure!.label, '');
    });
  });

  group('contrato do servidor mudando', () {
    test('contador novo em stats não derruba a leitura', () {
      // `tracks` (músicas salvas) entrou em `stats` depois que esta tela foi
      // escrita e já vem na captura acima; o cliente ainda não expõe esse
      // número, e ler o resto não pode depender disso. Vale para o próximo
      // contador e para o próximo bloco de primeiro nível que chegarem.
      final carga = _real();
      expect(_bloco(carga, 'stats')['tracks'], 6, reason: 'o servidor já manda');
      _bloco(carga, 'stats')['conquistas'] = 12;
      carga['collections_preview'] = {'total': 3};

      final p = Profile.fromJson(carga);

      expect(p.stats.memories, 12);
      expect(p.stats.photos, 9);
      expect(p.passport, hasLength(7));
    });

    test('contador que o servidor parar de mandar lê zero, não quebra', () {
      final carga = _real();
      _bloco(carga, 'stats')
        ..remove('photos')
        ..remove('pending_geocode')
        ..remove('journeys_finished')
        ..remove('tracked_meters');

      final s = Profile.fromJson(carga).stats;

      expect(s.photos, 0);
      expect(s.pendingGeocode, 0);
      expect(s.journeysFinished, 0);
      expect(s.trackedMeters, 0);
      // E o que continuou vindo segue íntegro.
      expect(s.memories, 12);
    });

    test('tracked_meters inteiro (sem casa decimal) continua sendo double', () {
      // O servidor manda float, mas distância exata vira `0` ou `800` no JSON
      // conforme o serializador. Ler como int explodiria em "type cast".
      final carga = _real();
      _bloco(carga, 'stats')['tracked_meters'] = 800;

      final s = Profile.fromJson(carga).stats;

      expect(s.trackedMeters, isA<double>());
      expect(s.trackedMeters, 800.0);
    });

    test('carimbo incompleto no passaporte conta como não visitado', () {
      final carga = _real();
      (carga['passport'] as List)[0] = <String, dynamic>{'continent': 'Europa'};

      final stamp = Profile.fromJson(carga).passport.first;

      expect(stamp.continent, 'Europa');
      expect(stamp.visited, isFalse);
    });

    test('jornada atual sem título e sem contagem não some da tela', () {
      final carga = _real();
      _bloco(carga, 'current_journey')
        ..['title'] = null
        ..remove('points_count')
        ..remove('started_at');

      final j = Profile.fromJson(carga).currentJourney!;

      expect(j.title, '');
      expect(j.pointsCount, 0);
      expect(j.startedAt, isNull);
      expect(j.id, 'b2e7073d-05cf-431d-ad9c-d8555762eb77');
    });
  });

  group('iniciais do avatar', () {
    ProfileIdentity comNome(String nome) {
      final carga = _real();
      _bloco(carga, 'identity')['name'] = nome;
      return Profile.fromJson(carga).identity;
    }

    test('primeiro e último nome', () {
      expect(comNome('Juan Pedro Ribeiro').initials, 'JR');
    });

    test('nome único usa só a primeira letra', () {
      expect(comNome('Ana').initials, 'A');
    });

    test('espaço sobrando não vira inicial em branco', () {
      expect(comNome('  Ana   Beatriz  ').initials, 'AB');
    });

    test('nome só com espaços cai na interrogação', () {
      expect(comNome('   ').initials, '?');
    });

    test('acento sobrevive ao corte', () {
      expect(comNome('Ângela Nóbrega').initials, 'ÂN');
    });

    test('emoji não é cortado no meio do grafema', () {
      // A bandeira é UM grafema feito de dois code units; cortar por índice
      // devolveria meio caractere e a tela mostraria um losango.
      expect(comNome('🇧🇷 Viajante').initials, '🇧🇷V');
    });
  });

  group('distância legível', () {
    Profile comMetros(num metros) {
      final carga = _real();
      _bloco(carga, 'stats')['tracked_meters'] = metros;
      return Profile.fromJson(carga);
    }

    test('abaixo de 1 km fica em metros inteiros', () {
      // 313.48… da captura real.
      expect(Profile.fromJson(_real()).trackedLabel, '313 m');
      expect(comMetros(0).trackedLabel, '0 m');
      expect(comMetros(999).trackedLabel, '999 m');
    });

    test('a partir de 1 km usa vírgula decimal (pt-BR)', () {
      expect(comMetros(1000).trackedLabel, '1,0 km');
      expect(comMetros(12400).trackedLabel, '12,4 km');
    });

    test('a partir de 100 km arredonda e separa milhar com ponto', () {
      expect(comMetros(120000).trackedLabel, '120 km');
      expect(comMetros(2430000).trackedLabel, '2.430 km');
    });
  });
}
