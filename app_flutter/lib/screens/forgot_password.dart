import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';

/// Recuperação por e-mail ainda não existe (pós-MVP). Tela honesta, como no
/// app Expo: explica os caminhos reais de hoje.
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

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
                    Text('Recuperar senha', style: serif(28)),
                    const SizedBox(height: 6),
                    Text('A recuperação por e-mail ainda não está disponível.',
                        style: serif(14.5, color: SJColors.inkSoft, style: FontStyle.italic)),
                    const SizedBox(height: 18),
                    const Text(
                      'Se você já está logado, troque a senha em "Alterar senha", no seu Atlas.\n\n'
                      'Se esqueceu e não consegue entrar, peça ao desenvolvedor para redefinir a sua senha.',
                      style: TextStyle(color: SJColors.inkSoft, fontSize: 14, height: 1.55),
                    ),
                    const SizedBox(height: 28),
                    PrimaryButton(
                      label: 'Voltar ao login',
                      onPressed: () => Navigator.of(context).pop(),
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
