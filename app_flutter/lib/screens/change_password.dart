import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/illustrations.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';

/// # Alterar senha — cuidar da chave de casa.
///
/// **Por que existe:** quem já está dentro precisa poder trocar a própria senha
/// sem passar pela recuperação por e-mail.
///
/// **O que o usuário sente:** controle e segurança. A tela é curta, confirma o
/// sucesso de forma inequívoca e avisa o efeito colateral importante: trocar a
/// senha DERRUBA as sessões antigas (o backend invalida os tokens anteriores).
///
/// **Ação principal:** salvar a nova senha.
///
/// **Atrito:** dois campos, validação preventiva antes de chamar a API, teclado
/// encadeado e erro inline. Sem a arte de marca aqui — é uma tela interna, e a
/// arte pertence à porta de entrada.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _nextFocus = FocusNode();
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
      if (mounted) setState(() => _done = true);
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
    _nextFocus.dispose();
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SJSpace.screenX),
            child: _done ? _success(s) : _form(s),
          ),
        ),
      ),
    );
  }

  /// Barra superior mínima: só o caminho de volta (tela interna, sem hero).
  Widget _topBar(SJScheme s) => Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          label: 'Voltar',
          child: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back, color: s.ink, size: 22),
          ),
        ),
      );

  Widget _form(SJScheme s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: SJSpace.x2),
          _topBar(s),
          const SizedBox(height: SJSpace.x4),
          const SJOverline('Sua conta'),
          const SizedBox(height: SJSpace.x2),
          Text('Alterar senha', style: SJText.h1(color: s.ink)),
          const SizedBox(height: SJSpace.x2),
          Text(
            'Ao salvar, as sessões abertas em outros aparelhos são encerradas.',
            style: SJText.bodySm(color: s.inkSoft),
          ),
          const SizedBox(height: SJSpace.x6),
          SJTextField(
            label: 'Senha atual',
            controller: _current,
            hint: '••••••••',
            obscureText: true,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _nextFocus.requestFocus(),
          ),
          const SizedBox(height: SJSpace.x4),
          SJTextField(
            label: 'Nova senha',
            controller: _next,
            focusNode: _nextFocus,
            hint: 'ao menos 10 caracteres',
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _onSubmit(),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: SJSpace.x3),
            Text(_error, textAlign: TextAlign.center, style: SJText.caption(color: s.danger)),
          ],
          const SizedBox(height: SJSpace.x6),
          SJButton(
            label: 'Salvar nova senha',
            loading: _loading,
            expand: true,
            onPressed: _loading ? null : _onSubmit,
          ),
        ],
      );

  /// Sucesso como um ESTADO próprio (não um toast que passa): a pessoa precisa
  /// ter certeza de que a senha mudou.
  Widget _success(SJScheme s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: SJSpace.x2),
          _topBar(s),
          const SizedBox(height: SJSpace.x8),
          SJEmptyState(
            illustration: const SJIllustration(kind: SJIllustrationKind.empty, size: 120),
            title: 'Senha alterada',
            body: 'Sua nova senha já está valendo. Guarde-a bem — ela é a chave do seu atlas.',
            actionLabel: 'Voltar ao atlas',
            onAction: () => Navigator.of(context).maybePop(),
          ),
        ],
      );
}
