import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/illustrations.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../widgets/common.dart';

/// # Recuperar senha — o caminho de volta para dentro da própria história.
///
/// **Por que existe:** quem esquece a senha perde o acesso às próprias memórias.
/// Esta tela é a única porta de retorno, então precisa ser calma e clara — não
/// um beco sem saída (era um stub honesto, hoje é o fluxo real do backend).
///
/// **O que o usuário sente:** alívio. Nenhuma culpa, nenhum jargão: pede o
/// e-mail, recebe um link, escolhe uma senha nova.
///
/// **Ação principal (uma por etapa):** [_Step.request] enviar o link ·
/// [_Step.reset] salvar a nova senha.
///
/// **Atrito:** dois campos no total, teclado encadeado, e a etapa 2 já aparece
/// logo após o envio (quem está com o e-mail aberto ao lado cola o código e
/// segue, sem precisar voltar).
///
/// **Segurança (ANTI-ENUMERAÇÃO):** o backend responde SEMPRE 202 com a mesma
/// mensagem, exista a conta ou não. Portanto esta tela NUNCA afirma que o e-mail
/// existe — a confirmação é condicional ("se existir uma conta..."). Errar isso
/// transformaria a tela num oráculo de contas cadastradas.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

/// Etapas do fluxo: pedir o link e, depois, redefinir com o código recebido.
enum _Step { request, reset }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _token = TextEditingController();
  final _password = TextEditingController();

  _Step _step = _Step.request;
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Etapa 1: pede o link. Sucesso NÃO confirma que a conta existe.
  Future<void> _requestLink() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Escreva seu e-mail para receber o link.');
      return;
    }
    setState(() {
      _error = '';
      _busy = true;
    });
    try {
      await Api.instance.forgotPassword(email);
      if (mounted) setState(() => _step = _Step.reset);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro inesperado.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Etapa 2: troca a senha com o token de uso único recebido por e-mail.
  Future<void> _reset() async {
    final token = _token.text.trim();
    final password = _password.text;
    if (token.isEmpty) {
      setState(() => _error = 'Cole o código que chegou no seu e-mail.');
      return;
    }
    if (password.length < 10) {
      setState(() => _error = 'A nova senha precisa de pelo menos 10 caracteres.');
      return;
    }
    setState(() {
      _error = '';
      _busy = true;
    });
    try {
      await Api.instance.resetPassword(token, password);
      if (!mounted) return;
      // Senha trocada: volta ao login com uma confirmação discreta.
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha redefinida. Entre com a nova senha.')),
      );
    } on ApiError catch (e) {
      // 400 = token inválido/expirado/já usado (mensagem genérica do backend).
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro inesperado.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          // Rola com o teclado aberto (aparelhos baixos não escondem o botão).
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
                    const SJOverline('Recuperar acesso'),
                    const SizedBox(height: SJSpace.x2),
                    Text(
                      _step == _Step.request ? 'Esqueceu a senha?' : 'Escolha uma nova senha',
                      style: SJText.h1(color: s.ink),
                    ),
                    const SizedBox(height: SJSpace.x2),
                    Text(
                      _step == _Step.request
                          ? 'Enviamos um link para você voltar ao seu atlas.'
                          : 'Cole o código do e-mail e defina a senha que vai usar agora.',
                      style: SJText.bodySm(color: s.inkSoft).copyWith(
                        fontFamily: SJType.serif,
                        fontFamilyFallback: SJType.serifFallback,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: SJSpace.x6),
                    if (_step == _Step.request) ..._requestFields() else ..._resetFields(s),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: SJSpace.x4),
                      Text(
                        _error,
                        textAlign: TextAlign.center,
                        style: SJText.caption(color: s.danger),
                      ),
                    ],
                    const SizedBox(height: SJSpace.x6),
                    SJButton(
                      label: _step == _Step.request ? 'Enviar link' : 'Salvar nova senha',
                      loading: _busy,
                      expand: true,
                      onPressed: _busy
                          ? null
                          : (_step == _Step.request ? _requestLink : _reset),
                    ),
                    const SizedBox(height: SJSpace.x4),
                    SJButton(
                      label: _step == _Step.request ? 'Voltar ao login' : 'Pedir outro link',
                      variant: SJButtonVariant.text,
                      expand: true,
                      onPressed: _busy
                          ? null
                          : () {
                              if (_step == _Step.reset) {
                                setState(() {
                                  _step = _Step.request;
                                  _error = '';
                                  _token.clear();
                                  _password.clear();
                                });
                              } else {
                                Navigator.of(context).pop();
                              }
                            },
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

  List<Widget> _requestFields() => [
        SJTextField(
          label: 'E-mail',
          controller: _email,
          hint: 'voce@email.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _requestLink(),
        ),
      ];

  /// Etapa 2 abre com a confirmação CONDICIONAL (nunca revela se a conta existe)
  /// + a ilustração de bússola, para a tela nunca parecer um formulário seco.
  List<Widget> _resetFields(SJScheme s) => [
        Container(
          padding: const EdgeInsets.all(SJSpace.x4),
          decoration: BoxDecoration(
            color: s.surfaceAlt,
            borderRadius: BorderRadius.circular(SJRadius.md),
            border: Border.all(color: s.line),
          ),
          child: Row(
            children: [
              const SJIllustration(kind: SJIllustrationKind.empty, size: 44),
              const SizedBox(width: SJSpace.x3),
              Expanded(
                child: Text(
                  'Se existir uma conta com esse e-mail, o link já está a caminho. '
                  'Ele vale por pouco tempo e só pode ser usado uma vez.',
                  style: SJText.caption(color: s.inkSoft),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SJSpace.x5),
        SJTextField(
          label: 'Código do e-mail',
          controller: _token,
          hint: 'cole aqui',
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: SJSpace.x4),
        SJTextField(
          label: 'Nova senha',
          controller: _password,
          hint: 'ao menos 10 caracteres',
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _reset(),
        ),
      ];
}
