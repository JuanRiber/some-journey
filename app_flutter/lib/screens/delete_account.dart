import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../features/phases/phase_store.dart';
import '../features/profile/profile_models.dart';
import '../widgets/api_error_view.dart';

/// # Excluir conta — ir embora levando tudo.
///
/// **Por que existe:** o que a pessoa guarda aqui é dela. Poder apagar tudo e
/// sair é parte de confiar o suficiente para guardar.
///
/// **O que o usuário sente:** que está sendo levado a sério, não empurrado nem
/// retido. A tela diz o que some, diz que não tem volta, e não tenta
/// convencer ninguém a ficar.
///
/// **Ação principal:** NÃO é excluir. A ação em destaque é a que não destrói
/// nada ("Manter minha conta"); a exclusão fica no botão discreto, e só acende
/// depois das duas confirmações.
///
/// **Atrito, e aqui ele é de propósito:** digitar o próprio e-mail (a trava
/// contra o toque errado) e, se a conta tem senha, a senha atual (a trava
/// contra quem pegou o aparelho destravado). As duas são conferidas de novo no
/// servidor — o botão apagado é cortesia, não segurança.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  ProfileIdentity? _conta;
  ApiError? _falhaAoAbrir;
  bool _excluindo = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    // O botão acende conforme a pessoa digita.
    _email.addListener(_redesenhar);
    _password.addListener(_redesenhar);
    _carregar();
  }

  void _redesenhar() => setState(() {});

  /// A tela precisa de duas coisas da conta antes de pedir qualquer coisa: o
  /// e-mail, para comparar com o digitado, e se ela tem senha.
  Future<void> _carregar() async {
    setState(() => _falhaAoAbrir = null);
    try {
      final perfil = await Api.instance.getProfile();
      if (mounted) setState(() => _conta = perfil.identity);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) return _irParaOLogin();
      setState(() => _falhaAoAbrir = e);
    } catch (_) {
      if (mounted) {
        setState(() => _falhaAoAbrir = ApiError(
            0, 'Não foi possível abrir esta tela agora.',
            kind: ApiFailure.request));
      }
    }
  }

  void _irParaOLogin() =>
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);

  bool get _emailConfere {
    final conta = _conta;
    return conta != null &&
        _email.text.trim().toLowerCase() == conta.email.toLowerCase();
  }

  bool get _pronto =>
      _emailConfere &&
      (!(_conta?.hasPassword ?? true) || _password.text.isNotEmpty);

  Future<void> _excluir() async {
    final conta = _conta;
    if (conta == null || !_pronto || _excluindo) return;
    setState(() {
      _error = '';
      _excluindo = true;
    });
    // Capturado antes de a tela sair: o aviso aparece já no login.
    final avisos = ScaffoldMessenger.of(context);
    try {
      await Api.instance.deleteAccount(
        email: _email.text.trim(),
        password: conta.hasPassword ? _password.text : null,
      );
      // As fases ficam em memória entre as telas; a conta delas não existe mais.
      PhaseStore.instance.clear();
      if (!mounted) return;
      _irParaOLogin();
      avisos.showSnackBar(const SnackBar(
        content: Text('Sua conta e tudo o que estava nela foram excluídos.'),
      ));
    } on ApiError catch (e) {
      if (!mounted) return;
      // Sem sessão não há a quem mostrar o erro: a renovação falhou e o
      // aparelho já esqueceu a conta.
      if (e.isUnauthorized && !Api.instance.hasToken) return _irParaOLogin();
      setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível excluir a conta agora.');
      }
    } finally {
      if (mounted) setState(() => _excluindo = false);
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SJSpace.screenX),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: SJSpace.x2),
                _topBar(s),
                const SizedBox(height: SJSpace.x4),
                const SJOverline('Sua conta'),
                const SizedBox(height: SJSpace.x2),
                Text('Excluir conta', style: SJText.h1(color: s.ink)),
                const SizedBox(height: SJSpace.x4),
                ..._corpo(s),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

  List<Widget> _corpo(SJScheme s) {
    final falha = _falhaAoAbrir;
    if (falha != null) {
      return [
        const SizedBox(height: SJSpace.x6),
        ApiErrorView(
          error: falha,
          fallbackTitle: 'Esta tela não abriu',
          onRetry: _carregar,
          illustrationSize: 120,
        ),
      ];
    }
    final conta = _conta;
    if (conta == null) {
      return [
        const SizedBox(height: SJSpace.x8),
        Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: s.primary),
          ),
        ),
      ];
    }
    return _formulario(s, conta);
  }

  List<Widget> _formulario(SJScheme s, ProfileIdentity conta) => [
        Text(
          'Isto apaga a sua conta e tudo o que você guardou nela:',
          style: SJText.body(color: s.ink),
        ),
        const SizedBox(height: SJSpace.x3),
        for (final item in const [
          'suas memórias, com as fotos e as músicas',
          'suas jornadas e os percursos gravados',
          'suas fases da vida',
          'seu perfil e a sua foto',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: SJSpace.x1),
            child: Text('—  $item', style: SJText.bodySm(color: s.inkSoft)),
          ),
        const SizedBox(height: SJSpace.x4),
        Text(
          'Não tem volta. Não guardamos cópia, e depois de excluir nem nós '
          'conseguimos recuperar.',
          style: SJText.bodySm(color: s.danger),
        ),
        const SizedBox(height: SJSpace.x6),
        SJTextField(
          label: 'Digite seu e-mail para confirmar',
          controller: _email,
          hint: 'o e-mail desta conta',
          keyboardType: TextInputType.emailAddress,
          enabled: !_excluindo,
          textInputAction:
              conta.hasPassword ? TextInputAction.next : TextInputAction.done,
          onSubmitted: (_) =>
              conta.hasPassword ? _passwordFocus.requestFocus() : _excluir(),
        ),
        const SizedBox(height: SJSpace.x4),
        if (conta.hasPassword)
          SJTextField(
            label: 'Senha atual',
            controller: _password,
            focusNode: _passwordFocus,
            hint: '••••••••',
            obscureText: true,
            enabled: !_excluindo,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _excluir(),
          )
        else
          Text(
            'Sua conta entra pelo Google e não tem senha: o e-mail basta.',
            style: SJText.caption(color: s.inkSoft),
          ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: SJSpace.x3),
          Text(_error,
              textAlign: TextAlign.center,
              style: SJText.caption(color: s.danger)),
        ],
        const SizedBox(height: SJSpace.x8),
        // A ação em destaque é a que não destrói nada.
        SJButton(
          label: 'Manter minha conta',
          expand: true,
          onPressed:
              _excluindo ? null : () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(height: SJSpace.x3),
        SJButton(
          label: 'Excluir minha conta para sempre',
          variant: SJButtonVariant.secondary,
          loading: _excluindo,
          expand: true,
          onPressed: _pronto && !_excluindo ? _excluir : null,
        ),
      ];
}
