import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../widgets/common.dart';

/// # Criar conta — o primeiro capítulo em branco.
///
/// **Por que existe:** para começar a registrar a própria vida é preciso um
/// lugar só seu.
///
/// **O que o usuário sente:** convite, não cadastro. Três campos e pronto — o
/// app não pede nada que não use.
///
/// **Ação principal:** criar conta (e já entrar: o cadastro faz login em
/// seguida, então ninguém digita a senha duas vezes).
///
/// **Atrito:** teclado encadeado (nome → e-mail → senha → enviar), a regra da
/// senha aparece ANTES do erro (dica preventiva, min. 10) e a falha volta inline.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  String _error = '';

  Future<void> _onRegister() async {
    setState(() {
      _error = '';
      _loading = true;
    });
    try {
      await Api.instance.register(_name.text.trim(), _email.text.trim(), _password.text);
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
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
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
                    const SizedBox(height: SJSpace.x5),
                    const SJOverline('Começar'),
                    const SizedBox(height: SJSpace.x2),
                    Text('Criar conta', style: SJText.h1(color: s.ink)),
                    const SizedBox(height: SJSpace.x2),
                    Text(
                      'Seu atlas começa vazio — e é só seu.',
                      style: SJText.bodySm(color: s.inkSoft).copyWith(
                        fontFamily: SJType.serif,
                        fontFamilyFallback: SJType.serifFallback,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: SJSpace.x6),
                    SJTextField(
                      label: 'Nome',
                      controller: _name,
                      hint: 'Como quer ser chamado',
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _emailFocus.requestFocus(),
                    ),
                    const SizedBox(height: SJSpace.x4),
                    SJTextField(
                      label: 'E-mail',
                      controller: _email,
                      focusNode: _emailFocus,
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
                      hint: 'ao menos 10 caracteres',
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _onRegister(),
                    ),
                    const SizedBox(height: SJSpace.x2),
                    Text('Mínimo de 10 caracteres.', style: SJText.caption(color: s.inkFaint)),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: SJSpace.x3),
                      Text(
                        _error,
                        textAlign: TextAlign.center,
                        style: SJText.caption(color: s.danger),
                      ),
                    ],
                    const SizedBox(height: SJSpace.x5),
                    SJButton(
                      label: 'Criar conta',
                      loading: _loading,
                      expand: true,
                      onPressed: _loading ? null : _onRegister,
                    ),
                    const SizedBox(height: SJSpace.x5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Já tem conta?', style: SJText.bodySm(color: s.inkSoft)),
                        const SizedBox(width: SJSpace.x1),
                        SJButton(
                          label: 'Entrar',
                          variant: SJButtonVariant.text,
                          onPressed: () => Navigator.of(context).pop(),
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
