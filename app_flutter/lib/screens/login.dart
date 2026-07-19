import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const HeroArt(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    const FieldLabel('E-mail'),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(hintText: 'voce@email.com'),
                    ),
                    const FieldLabel('Senha'),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      onSubmitted: (_) => _onLogin(),
                      decoration: const InputDecoration(hintText: '••••••••'),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pushNamed('/forgot'),
                        child: const Text(
                          'Esqueci minha senha',
                          style: TextStyle(color: SJColors.cyan, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    InlineError(_error),
                    const SizedBox(height: 14),
                    PrimaryButton(label: _loading ? 'Entrando...' : 'Entrar', onPressed: _onLogin, busy: _loading),
                    const SizedBox(height: 26),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Não tem conta? ', style: TextStyle(color: SJColors.inkSoft, fontSize: 14)),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pushNamed('/register'),
                          child: const Text(
                            'Criar conta',
                            style: TextStyle(color: SJColors.cyan, fontSize: 14, fontWeight: FontWeight.w700),
                          ),
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
