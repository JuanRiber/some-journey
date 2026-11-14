import '../../api.dart';

/// A última versão de uma tela, para ela abrir JÁ preenchida enquanto relê.
///
/// Perfil e estante de jornadas são telas que se empilham e se desempilham o
/// tempo todo, e cada abertura começava em esqueleto até a rede responder —
/// com o servidor nos EUA, uma espera que se sente toda vez. Com o cache, a
/// tela abre com o que a pessoa viu da última vez e troca pelo novo quando
/// ele chega.
///
/// O valor vale só para a sessão em que foi guardado: depois de sair ou de
/// entrar com outra conta, ele simplesmente não aparece — nunca o perfil de
/// uma pessoa na tela de outra.
class SessionCache<T> {
  Object? _dono;
  T? _valor;

  T? get valor {
    final sessao = Api.instance.sessionTag;
    return (sessao != null && sessao == _dono) ? _valor : null;
  }

  set valor(T? novo) {
    _valor = novo;
    _dono = Api.instance.sessionTag;
  }
}
