import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tokens.dart';

/// # Controlador de modo (claro/escuro)
///
/// Guarda a preferência de aparência do usuário e a notifica à árvore. A regra
/// do produto: o "papel quente" (claro) é o PADRÃO — a primeira abertura, ou
/// qualquer estado sem preferência salva, cai em [ThemeMode.light]. O usuário
/// pode fixar claro/escuro num toggle (persistido) ou pedir para acompanhar o
/// sistema ([ThemeMode.system]).
///
/// Por que um [ChangeNotifier] "manual" em vez de um pacote de estado? Porque a
/// dependência é mínima (só `shared_preferences`, que o app já usa para o
/// token) e o `MaterialApp` só precisa reconstruir quando o modo muda —
/// `AnimatedBuilder`/`ListenableBuilder` em cima deste notifier resolve.
class SjThemeController extends ChangeNotifier {
  /// Chave única de persistência (isolada por prefixo do produto).
  static const String _prefsKey = 'sj_theme_mode';

  /// Padrão do produto: papel quente. Só muda após [loadSaved] ou [setMode].
  ThemeMode _mode = ThemeMode.light;

  /// Modo atual — o `MaterialApp` liga isto no `themeMode`.
  ThemeMode get mode => _mode;

  /// Lê a preferência salva (se houver) e atualiza o modo. Chamado uma vez no
  /// boot, antes de montar o app. Ausência de valor = mantém o padrão claro,
  /// então uma instalação nova nunca "pisca" escuro.
  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    final resolved = _decode(saved);
    if (resolved != _mode) {
      _mode = resolved;
      notifyListeners();
    }
  }

  /// Fixa um modo e persiste. Não faz nada se já estiver nesse modo (evita
  /// notificação e escrita redundantes).
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _encode(mode));
  }

  /// Alterna entre claro e escuro. Se o modo atual for [ThemeMode.system],
  /// resolve o "oposto" a partir do brilho da plataforma informado — assim o
  /// primeiro toque sempre inverte o que o usuário está VENDO, sem exigir um
  /// segundo toque para "sair do system".
  Future<void> toggle({Brightness platformBrightness = Brightness.light}) async {
    final effective = _mode == ThemeMode.system
        ? (platformBrightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light)
        : _mode;
    await setMode(effective == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  /// Resolve o [SJScheme] concreto a valer AGORA, dado o modo escolhido e —
  /// quando o modo é [ThemeMode.system] — o brilho da plataforma lido do
  /// `MediaQuery`. Útil para pintar fora do `Theme` (ex.: overlays, splashes)
  /// ou para componentes que precisam do esquema sem depender do `SJTheme`.
  SJScheme schemeFor(BuildContext context) {
    final brightness = switch (_mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    return brightness == Brightness.dark ? sjDark : sjLight;
  }

  // ── Serialização (string estável, independente do índice do enum) ─────────
  static ThemeMode _decode(String? raw) => switch (raw) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.light, // padrão do produto quando ausente/inválido
      };

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.dark => 'dark',
        ThemeMode.light => 'light',
        ThemeMode.system => 'system',
      };
}
