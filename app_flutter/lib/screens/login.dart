import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../widgets/common.dart';

/// # Entrar — a porta do próprio atlas.
///
/// **Por que existe:** as memórias são privadas; esta é a única entrada.
///
/// **O que o usuário sente:** reconhecimento e calma. A arte de marca ocupa o
/// topo (é o que diz "você chegou em casa"), e o formulário é curto o bastante
/// para não parecer burocracia.
///
/// **Ação principal:** entrar. Secundárias: recuperar senha e criar conta.
///
/// **Atrito:** dois campos, teclado encadeado (e-mail → senha → enviar), rolagem
/// que respeita o teclado e erro inline (nunca um diálogo que interrompe).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  String _error = '';

  Future<void> _onLogin() async {
    setState(() {
      _error = '';
      _loading = true;
    });
    try {
      await Api.instance.login(_email.text.trim(), _password.text);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/tabs', (_) => false);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Erro inesperado.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: SJSpace.x10 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const HeroArt(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SJSpace.screenX),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: SJSpace.x6),
                    SJTextField(
                      label: 'E-mail',
                      controller: _email,
                      hint: 'voce@email.com',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _passwordFocus.requestFocus(),
                    ),
                    const SizedBox(height: SJSpace.x4),
                    SJTextField(
                      label: 'Senha',
                      controller: _password,
                      focusNode: _passwordFocus,
                      hint: '••••••••',
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _onLogin(),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SJButton(
                        label: 'Esqueci minha senha',
                        variant: SJButtonVariant.text,
                        onPressed: () => Navigator.of(context).pushNamed('/forgot'),
                      ),
                    ),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: SJSpace.x2),
                      Text(
                        _error,
                        textAlign: TextAlign.center,
                        style: SJText.caption(color: s.danger),
                      ),
                    ],
                    const SizedBox(height: SJSpace.x4),
                    SJButton(
                      label: 'Entrar',
                      loading: _loading,
                      expand: true,
                      onPressed: _loading ? null : _onLogin,
                    ),
                    const SizedBox(height: SJSpace.x5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Não tem conta?', style: SJText.bodySm(color: s.inkSoft)),
                        const SizedBox(width: SJSpace.x1),
                        SJButton(
                          label: 'Criar conta',
                          variant: SJButtonVariant.text,
                          onPressed: () => Navigator.of(context).pushNamed('/register'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
