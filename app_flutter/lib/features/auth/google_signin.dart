import 'package:google_sign_in/google_sign_in.dart';

/// # Entrar com o Google — contrato e configuração
///
/// O cliente fala com o Google, recebe um `id_token` e manda para o NOSSO
/// backend, que verifica a assinatura. O app nunca decide quem a pessoa é —
/// ele só carrega o token de um lado para o outro.
///
/// ## Por que uma interface (de novo)
///
/// Mesmo motivo do [MusicProvider]: a UI conversa com um contrato, não com um
/// SDK. Aqui o ganho é concreto e imediato — o fluxo do Google não roda em
/// teste, e sem esta fronteira NADA do que a tela faz com o token (sucesso,
/// cancelamento, erro, conta vinculada) poderia ser verificado.

/// O client id, por `--dart-define`, igual ao `API_URL`.
///
/// Vazio é o estado normal de quem ainda não criou a credencial no Google
/// Cloud — e é o que mantém o botão DESLIGADO em vez de ligado e quebrado. O
/// passo a passo para obter o valor está no README.
const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

/// Há credencial para tentar?
bool get googleConfigurado => googleClientId.isNotEmpty;

/// O que pode dar errado, no vocabulário da TELA — não no do SDK.
enum GoogleFalha {
  /// A pessoa fechou a janela do Google. Não é erro: não mostra mensagem.
  cancelado,

  /// O SDK não entrega login direto nesta plataforma (é o caso da web, que
  /// exige o botão renderizado pelo próprio Google).
  naoSuportado,

  /// Qualquer outra: rede, configuração errada, SDK indisponível.
  falhou,
}

class GoogleErro implements Exception {
  const GoogleErro(this.tipo);
  final GoogleFalha tipo;
}

/// Contrato: devolve um `id_token` ou levanta [GoogleErro].
abstract interface class SJGoogleSignIn {
  Future<String> idToken();
}

/// Implementação real sobre o `google_sign_in` 7.x.
class GoogleSignInReal implements SJGoogleSignIn {
  GoogleSignInReal({GoogleSignIn? sdk}) : _sdk = sdk ?? GoogleSignIn.instance;

  final GoogleSignIn _sdk;
  bool _iniciado = false;

  @override
  Future<String> idToken() async {
    if (!googleConfigurado) throw const GoogleErro(GoogleFalha.falhou);
    try {
      if (!_iniciado) {
        // `clientId` identifica ESTE aplicativo para o Google; é o mesmo valor
        // que o backend espera encontrar no `aud` do token.
        await _sdk.initialize(clientId: googleClientId);
        _iniciado = true;
      }
      if (!_sdk.supportsAuthenticate()) {
        // Web: o Google não permite um botão nosso chamando o fluxo; é preciso
        // renderizar o botão deles. Quem trata isso é a camada de UI.
        throw const GoogleErro(GoogleFalha.naoSuportado);
      }
      final conta = await _sdk.authenticate();
      final token = conta.authentication.idToken;
      if (token == null || token.isEmpty) {
        // Sem `idToken` não há o que o backend verifique. Acontece quando o
        // client id da plataforma não bate com o configurado.
        throw const GoogleErro(GoogleFalha.falhou);
      }
      return token;
    } on GoogleErro {
      rethrow;
    } on GoogleSignInException catch (e) {
      throw GoogleErro(
        e.code == GoogleSignInExceptionCode.canceled
            ? GoogleFalha.cancelado
            : GoogleFalha.falhou,
      );
    } catch (_) {
      throw const GoogleErro(GoogleFalha.falhou);
    }
  }
}
