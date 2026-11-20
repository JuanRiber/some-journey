// Onde a sessão fica guardada no aparelho.
//
// No celular os tokens saem do `shared_preferences` — um arquivo de texto na
// pasta do app — e vão para o cofre do sistema (Keychain / Keystore). O que
// este arquivo prende: o que vai para onde, a mudança de quem já estava
// logado, e o que acontece quando o cofre não responde.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:some_journey/features/auth/token_store.dart';

const _cofre = FlutterSecureStorage();

/// Um cofre que recusa tudo — o keychain bloqueado, o plugin que falhou.
class _CofreQuebrado implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('cofre fora');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const sessao =
      StoredSession(accessToken: 'access-1', refreshToken: 'refresh-1');

  group('cofre do sistema (celular)', () {
    test('guarda os dois tokens no cofre, e nada no arquivo de texto', () async {
      const store = SecureTokenStore();

      expect(await store.write(sessao), isTrue);

      expect(await _cofre.read(key: accessTokenKey), 'access-1');
      expect(await _cofre.read(key: refreshTokenKey), 'refresh-1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('lê de volta o que guardou', () async {
      const store = SecureTokenStore();
      await store.write(sessao);

      final lida = await store.read();

      expect(lida?.accessToken, 'access-1');
      expect(lida?.refreshToken, 'refresh-1');
    });

    test('sem nada guardado, não há sessão', () async {
      expect(await const SecureTokenStore().read(), isNull);
    });

    test('sessão sem refresh token apaga o refresh antigo do cofre', () async {
      const store = SecureTokenStore();
      await store.write(sessao);

      await store.write(const StoredSession(accessToken: 'access-2'));

      expect(await _cofre.read(key: refreshTokenKey), isNull);
      expect((await store.read())?.refreshToken, isNull);
    });

    test('sair apaga do cofre', () async {
      const store = SecureTokenStore();
      await store.write(sessao);

      expect(await store.write(null), isTrue);

      expect(await _cofre.readAll(), isEmpty);
      expect(await store.read(), isNull);
    });
  });

  group('quem já estava logado antes da mudança', () {
    test('a sessão do arquivo de texto é MUDADA para o cofre', () async {
      SharedPreferences.setMockInitialValues({accessTokenKey: 'token-antigo'});

      final lida = await const SecureTokenStore().read();

      expect(lida?.accessToken, 'token-antigo',
          reason: 'atualizar o app não pode deslogar ninguém');
      expect(await _cofre.read(key: accessTokenKey), 'token-antigo');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(accessTokenKey), isNull,
          reason: 'a cópia no arquivo de texto é o que a mudança existe para tirar');
    });

    test('o cofre manda: sessão nele vence a que sobrou no arquivo', () async {
      SharedPreferences.setMockInitialValues({accessTokenKey: 'sobra'});
      FlutterSecureStorage.setMockInitialValues({accessTokenKey: 'do-cofre'});

      final lida = await const SecureTokenStore().read();

      expect(lida?.accessToken, 'do-cofre');
    });

    test('sair apaga também a sobra do arquivo de texto', () async {
      SharedPreferences.setMockInitialValues({accessTokenKey: 'sobra'});

      await const SecureTokenStore().write(null);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(accessTokenKey), isNull);
      expect(await const SecureTokenStore().read(), isNull,
          reason: 'senão a sessão de quem saiu voltava na próxima abertura');
    });
  });

  group('cofre que não responde', () {
    test('gravar falha sem lançar, e NÃO cai para o arquivo de texto', () async {
      final store = SecureTokenStore(storage: _CofreQuebrado());

      expect(await store.write(sessao), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty,
          reason: 'refresh token em texto puro é o que não pode acontecer');
    });

    test('ler falha sem lançar: sem sessão, o app vai para o login', () async {
      expect(await SecureTokenStore(storage: _CofreQuebrado()).read(), isNull);
    });

    test('a sessão antiga ainda é usada, e fica onde está para a próxima',
        () async {
      SharedPreferences.setMockInitialValues({accessTokenKey: 'token-antigo'});

      final lida = await SecureTokenStore(storage: _CofreQuebrado()).read();

      expect(lida?.accessToken, 'token-antigo');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(accessTokenKey), 'token-antigo',
          reason: 'apagar sem ter gravado no cofre perderia a sessão');
    });
  });

  group('navegador', () {
    test('guarda e lê do shared_preferences (o localStorage)', () async {
      const store = PrefsTokenStore();

      await store.write(sessao);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(accessTokenKey), 'access-1');
      expect(prefs.getString(refreshTokenKey), 'refresh-1');
      expect((await store.read())?.refreshToken, 'refresh-1');
    });

    test('sair apaga os dois', () async {
      const store = PrefsTokenStore();
      await store.write(sessao);

      await store.write(null);

      expect(await store.read(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });
  });
}
