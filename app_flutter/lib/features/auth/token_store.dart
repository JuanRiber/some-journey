/// Onde a sessão fica guardada no aparelho.
///
/// A sessão são dois segredos: o access token (vale uma hora) e o refresh token
/// (vale semanas, e é o que abre a próxima hora). Os dois moravam — o primeiro
/// sozinho, até aqui — no `shared_preferences`, que no celular é um arquivo de
/// texto dentro da pasta do app: um backup do aparelho, um celular com root ou
/// outro app com acesso a essa pasta leem o que está ali. Para um token de uma
/// hora era um risco pequeno; para um refresh token de 30 dias não é.
///
/// **No celular** os dois vão para o cofre do sistema: Keychain no iOS,
/// Keystore no Android (via `flutter_secure_storage`). **Na web** continuam no
/// `shared_preferences` — que ali é o `localStorage`. Não é descuido: o
/// navegador não tem cofre. O que o plugin oferece na web é cifrar o valor com
/// uma chave guardada no MESMO `localStorage`, que não protege de nada do que
/// já alcança um e ganharia um jeito novo de falhar.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Os dois segredos da sessão, como foram guardados.
class StoredSession {
  const StoredSession({required this.accessToken, this.refreshToken});

  final String accessToken;

  /// Nulo em sessão antiga, aberta antes de existir renovação: ela vale até o
  /// access token vencer, como sempre valeu.
  final String? refreshToken;
}

/// O contrato de quem guarda a sessão. Existe para o cliente da API não saber
/// em qual das duas plataformas está — e para um teste trocar o cofre por um
/// mapa.
abstract class TokenStore {
  /// A sessão guardada, ou null. NUNCA lança: armazenamento indisponível é
  /// "sem sessão", e o app segue para o login.
  Future<StoredSession?> read();

  /// Guarda a sessão; `null` apaga. Devolve se ela ficou de fato guardada.
  /// NUNCA lança: quem chama mantém a sessão em memória de qualquer jeito.
  Future<bool> write(StoredSession? session);

  /// O cofre certo para a plataforma em que o app está rodando.
  static TokenStore platform() =>
      kIsWeb ? const PrefsTokenStore() : const SecureTokenStore();
}

const accessTokenKey = 'sj_access_token';
const refreshTokenKey = 'sj_refresh_token';

/// `shared_preferences` — o `localStorage` na web.
class PrefsTokenStore implements TokenStore {
  const PrefsTokenStore();

  @override
  Future<StoredSession?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Outra aba pode ter renovado a sessão: sem reler, esta aba enxergaria
      // para sempre a cópia que carregou ao abrir.
      await prefs.reload();
      final access = prefs.getString(accessTokenKey);
      if (access == null) return null;
      return StoredSession(
        accessToken: access,
        refreshToken: prefs.getString(refreshTokenKey),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> write(StoredSession? session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (session == null) {
        await prefs.remove(accessTokenKey);
        await prefs.remove(refreshTokenKey);
        return true;
      }
      await prefs.setString(accessTokenKey, session.accessToken);
      final refresh = session.refreshToken;
      if (refresh == null) {
        await prefs.remove(refreshTokenKey);
      } else {
        await prefs.setString(refreshTokenKey, refresh);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Keychain (iOS, macOS) e Keystore (Android).
///
/// Na primeira leitura depois da atualização, a sessão que estava no
/// `shared_preferences` é MUDADA para o cofre — copiada e, só depois de
/// gravada, apagada de lá. Sem isso, atualizar o app deslogaria todo mundo; e
/// deixar a cópia antiga para trás manteria no arquivo de texto exatamente o
/// que esta classe existe para tirar de lá.
class SecureTokenStore implements TokenStore {
  const SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? _padrao;

  final FlutterSecureStorage _storage;

  static const _padrao = FlutterSecureStorage(
    // Legível depois do primeiro desbloqueio desde que o aparelho ligou, e não
    // só com a tela aberta: o envio de um lote de GPS com o celular no bolso
    // precisa do token. `this_device`: não viaja em backup para outro aparelho.
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    // O keychain de proteção de dados exige a capacidade Keychain Sharing, que
    // por sua vez exige perfil de provisionamento. O app não compartilha item
    // nenhum com outro app: o keychain comum basta.
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      usesDataProtectionKeychain: false,
    ),
  );

  /// Teto de cada ida ao cofre. Um keychain que não responde (aparelho
  /// bloqueado logo após ligar, plugin sem plataforma do outro lado) não pode
  /// segurar o login nem a abertura do app: passado isto, vale como falha.
  static const _teto = Duration(seconds: 4);

  @override
  Future<StoredSession?> read() async {
    try {
      final access = await _storage.read(key: accessTokenKey).timeout(_teto);
      if (access != null) {
        return StoredSession(
          accessToken: access,
          refreshToken:
              await _storage.read(key: refreshTokenKey).timeout(_teto),
        );
      }
    } catch (_) {
      // Cofre indisponível: ainda vale olhar se há sessão antiga para ler.
    }
    return _migrar();
  }

  /// Traz para o cofre a sessão que uma versão anterior deixou no
  /// `shared_preferences`. Se o cofre não aceitar, ela é usada assim mesmo
  /// nesta abertura e fica onde está — perder a sessão seria pior que adiar a
  /// mudança para a próxima vez.
  Future<StoredSession?> _migrar() async {
    const antigo = PrefsTokenStore();
    final sessao = await antigo.read();
    if (sessao == null) return null;
    if (await _gravar(sessao)) await antigo.write(null);
    return sessao;
  }

  @override
  Future<bool> write(StoredSession? session) async {
    if (session == null) {
      // Sair apaga dos DOIS lugares: uma migração que não se completou não
      // pode devolver, na próxima abertura, a sessão de quem acabou de sair.
      final limpouAntigo = await const PrefsTokenStore().write(null);
      try {
        await _storage.delete(key: accessTokenKey).timeout(_teto);
        await _storage.delete(key: refreshTokenKey).timeout(_teto);
        return limpouAntigo;
      } catch (_) {
        return false;
      }
    }
    final gravou = await _gravar(session);
    // Com a sessão nova no cofre, a cópia antiga (se houver) não tem mais
    // serventia. Se o cofre recusou, NÃO cai para o arquivo de texto: a sessão
    // vale em memória até o app fechar, que é melhor do que gravar o refresh
    // token onde ele não deveria estar.
    if (gravou) await const PrefsTokenStore().write(null);
    return gravou;
  }

  Future<bool> _gravar(StoredSession session) async {
    try {
      await _storage
          .write(key: accessTokenKey, value: session.accessToken)
          .timeout(_teto);
      final refresh = session.refreshToken;
      if (refresh == null) {
        await _storage.delete(key: refreshTokenKey).timeout(_teto);
      } else {
        await _storage.write(key: refreshTokenKey, value: refresh).timeout(_teto);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
