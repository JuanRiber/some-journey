import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../design/components.dart';
import '../../design/sj_theme.dart';
import '../../design/tokens.dart';
import 'google_signin.dart';
import 'google_button_stub.dart'
    if (dart.library.js_interop) 'google_button_web.dart';

/// # O botão de entrar com o Google
///
/// Três estados, e a escolha entre eles é a parte honesta deste widget:
///
/// - **Sem client id** — desenhado e DESLIGADO, com "em breve" escrito. É o
///   estado padrão de quem ainda não criou a credencial no Google Cloud, e
///   ligar o botão antes disso seria um botão que não faz nada.
/// - **Plataforma com fluxo direto** (Android, iOS, macOS) — botão nosso, no
///   design system, chamando o SDK.
/// - **Web** — o botão renderizado pelo próprio Google. Não é escolha de
///   estilo: o Google não autoriza o fluxo a sair de um botão de terceiro, e a
///   resposta chega por um stream em vez de pelo retorno da chamada.
class GoogleBotao extends StatefulWidget {
  const GoogleBotao({
    super.key,
    required this.onToken,
    required this.onFalha,
    this.ocupado = false,
    this.servico,
    this.habilitado,
  });

  /// Recebeu um `id_token` — a tela troca por uma sessão nossa.
  final ValueChanged<String> onToken;

  /// Algo impediu. Cancelamento NÃO chega aqui: fechar a janela do Google não
  /// é erro e não merece mensagem.
  final ValueChanged<GoogleFalha> onFalha;

  final bool ocupado;

  /// Injetável para teste; em produção é o SDK de verdade.
  final SJGoogleSignIn? servico;

  /// Sobrescreve a checagem de credencial. Existe para o TESTE conseguir ver
  /// os dois estados: `googleClientId` é const de compilação, então sem isto
  /// metade deste widget só seria exercitada recompilando a suíte com outro
  /// `--dart-define` — ou seja, nunca.
  final bool? habilitado;

  @override
  State<GoogleBotao> createState() => _GoogleBotaoState();
}

class _GoogleBotaoState extends State<GoogleBotao> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _inscricao;
  late final SJGoogleSignIn _servico = widget.servico ?? GoogleSignInReal();

  bool get _ligado => widget.habilitado ?? googleConfigurado;

  @override
  void initState() {
    super.initState();
    if (_ligado && botaoRenderizadoPeloGoogle() != null) {
      // Caminho da web: o token não volta da chamada, chega por evento.
      _inscricao = GoogleSignIn.instance.authenticationEvents.listen(
        (evento) {
          if (evento is GoogleSignInAuthenticationEventSignIn) {
            final token = evento.user.authentication.idToken;
            if (token != null && token.isNotEmpty) widget.onToken(token);
          }
        },
        onError: (_) => widget.onFalha(GoogleFalha.falhou),
      );
      GoogleSignIn.instance.initialize(clientId: googleClientId).catchError(
        (_) => widget.onFalha(GoogleFalha.falhou),
      );
    }
  }

  @override
  void dispose() {
    _inscricao?.cancel();
    super.dispose();
  }

  Future<void> _entrar() async {
    try {
      widget.onToken(await _servico.idToken());
    } on GoogleErro catch (e) {
      // Cancelar é uma decisão da pessoa, não uma falha do app.
      if (e.tipo != GoogleFalha.cancelado) widget.onFalha(e.tipo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);

    if (!_ligado) return _Desligado(scheme: s);

    final doGoogle = botaoRenderizadoPeloGoogle();
    if (doGoogle != null) {
      return Semantics(
        button: true,
        label: 'Continuar com Google',
        child: Center(child: doGoogle),
      );
    }

    return SJButton(
      label: 'Continuar com Google',
      variant: SJButtonVariant.secondary,
      expand: true,
      onPressed: widget.ocupado ? null : _entrar,
    );
  }
}

/// Desenhado e desligado, com o motivo escrito. A composição da tela sobrevive
/// e ninguém é enganado.
class _Desligado extends StatelessWidget {
  const _Desligado({required this.scheme});

  final SJScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.55,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.line),
          borderRadius: BorderRadius.circular(SJRadius.md),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                'Continuar com Google',
                style: SJText.bodySm(color: scheme.ink),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: SJSpace.x2),
            SJBadge('em breve', color: scheme.inkFaint),
          ],
        ),
      ),
    );
  }
}
