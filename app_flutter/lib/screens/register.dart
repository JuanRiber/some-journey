import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
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
                    const SizedBox(height: 16),
                    Text('Criar conta', style: serif(28)),
                    const FieldLabel('Nome'),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(hintText: 'Como quer ser chamado'),
                    ),
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
                      onSubmitted: (_) => _onRegister(),
                      decoration: const InputDecoration(hintText: '••••••••'),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Mínimo de 10 caracteres.',
                          style: TextStyle(color: SJColors.inkSoft, fontSize: 12)),
                    ),
                    InlineError(_error),
                    const SizedBox(height: 14),
                    PrimaryButton(
                        label: _loading ? 'Criando...' : 'Criar conta',
                        onPressed: _onRegister,
                        busy: _loading),
                    const SizedBox(height: 26),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Já tem conta? ',
                            style: TextStyle(color: SJColors.inkSoft, fontSize: 14)),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: const Text(
                            'Entrar',
                            style: TextStyle(
                                color: SJColors.cyan, fontSize: 14, fontWeight: FontWeight.w700),
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
