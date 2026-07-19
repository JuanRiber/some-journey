import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _loading = false;
  bool _done = false;
  String _error = '';

  Future<void> _onSubmit() async {
    setState(() => _error = '');
    if (_current.text.isEmpty || _next.text.length < 10) {
      setState(() => _error = 'Informe a senha atual e uma nova com pelo menos 10 caracteres.');
      return;
    }
    setState(() => _loading = true);
    try {
      await Api.instance.changePassword(_current.text, _next.text);
      setState(() => _done = true);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível alterar a senha.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
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
                child: _done
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 16),
                          Text('Senha alterada', style: serif(28)),
                          const SizedBox(height: 22),
                          const Text(
                            'Sua senha foi alterada com sucesso.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: SJColors.cyan, fontSize: 15, height: 1.45),
                          ),
                          const SizedBox(height: 28),
                          PrimaryButton(label: 'Voltar', onPressed: () => Navigator.of(context).pop()),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 16),
                          Text('Alterar senha', style: serif(28)),
                          const FieldLabel('Senha atual'),
                          TextField(
                            controller: _current,
                            obscureText: true,
                            decoration: const InputDecoration(hintText: '••••••••'),
                          ),
                          const FieldLabel('Nova senha'),
                          TextField(
                            controller: _next,
                            obscureText: true,
                            onSubmitted: (_) => _onSubmit(),
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
                            label: _loading ? 'Alterando...' : 'Alterar senha',
                            onPressed: _onSubmit,
                            busy: _loading,
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('← Voltar',
                                  style: TextStyle(color: SJColors.ink, fontSize: 14)),
                            ),
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
