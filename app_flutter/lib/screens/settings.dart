import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';

/// # Configurações — estruturadas para crescer.
///
/// **Por que existe:** separar o AJUSTE da IDENTIDADE. O Perfil conta a
/// história; aqui ficam os controles, atrás de uma engrenagem discreta.
///
/// **Estrutura antes de função:** as categorias (Conta, Aparência, Notificações,
/// Privacidade, Backup, Idioma, Sobre) existem desde já, mesmo com itens ainda
/// não implementados. Assim cada recurso novo encontra seu lugar em vez de
/// virar mais um item solto — e o usuário vê o mapa do que vem.
///
/// **Honestidade:** o que não funciona é marcado como "em breve" e NÃO é
/// clicável. Um controle que não faz nada é pior que um controle ausente.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _confirmingLogout = false;

  Future<void> _logout() async {
    await Api.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            SJSpace.screenX, SJSpace.x2, SJSpace.screenX, SJSpace.x12,
          ),
          children: [
            Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Voltar',
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: s.ink, size: 22),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SJSpace.x4),
            const SJOverline('Ajustes'),
            const SizedBox(height: SJSpace.x2),
            Text('Configurações', style: SJText.h1(color: s.ink)),
            const SizedBox(height: SJSpace.x8),

            _Section(title: 'Conta', children: [
              _Row(
                label: 'Alterar senha',
                onTap: () => Navigator.of(context).pushNamed('/change-password'),
              ),
              const _Row(label: 'Alterar nome', soon: true),
              const _Row(label: 'Alterar foto', soon: true),
              const _Row(label: 'Excluir conta', soon: true),
            ]),

            _Section(title: 'Aparência', children: [
              // O tema JÁ existe nos dois modos (papel/atlas). Enquanto a
              // alternância não é persistida por tela, mostramos o modo vigente
              // em vez de um controle que mentiria sobre o que faz.
              _Row(label: 'Papel (claro)', trailing: _current(s, true)),
              _Row(label: 'Atlas (escuro)', trailing: _current(s, false), soon: true),
              const _Row(label: 'Automático (sistema)', soon: true),
            ]),

            const _Section(title: 'Notificações', children: [
              _Row(label: 'Lembretes de revisita', soon: true),
              _Row(label: 'Aniversários de memórias', soon: true),
            ]),

            const _Section(title: 'Privacidade', children: [
              _Row(label: 'Visibilidade das jornadas', soon: true),
              _Row(label: 'Dados de localização', soon: true),
            ]),

            const _Section(title: 'Backup e dados', children: [
              _Row(label: 'Exportar meus dados', soon: true),
              _Row(label: 'Exportar PDF da jornada', soon: true),
            ]),

            const _Section(title: 'Idioma', children: [
              _Row(label: 'Português (Brasil)', soon: true),
            ]),

            const _Section(title: 'Sobre', children: [
              _Row(label: 'Some Journey · versão 1.0'),
              _Row(label: 'A vida deixa rastros.'),
            ]),

            const SizedBox(height: SJSpace.x8),
            // Sair é discreto de propósito: não é a ação principal de ninguém.
            if (!_confirmingLogout)
              SJButton(
                label: 'Sair da conta',
                variant: SJButtonVariant.text,
                expand: true,
                onPressed: () => setState(() => _confirmingLogout = true),
              )
            else
              Column(
                children: [
                  Text(
                    'Sair desta conta?',
                    style: SJText.bodySm(color: s.ink),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: SJSpace.x3),
                  Row(
                    children: [
                      Expanded(
                        child: SJButton(
                          label: 'Cancelar',
                          variant: SJButtonVariant.secondary,
                          onPressed: () => setState(() => _confirmingLogout = false),
                        ),
                      ),
                      const SizedBox(width: SJSpace.x3),
                      Expanded(
                        child: SJButton(label: 'Sair', onPressed: _logout),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Marca o modo vigente sem prometer alternância que ainda não persiste.
  Widget? _current(SJScheme s, bool isLight) =>
      (s.brightness == Brightness.light) == isLight
          ? const SJBadge('Em uso')
          : null;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SJSpace.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SJOverline(title),
          const SizedBox(height: SJSpace.x3),
          SJCard(child: Column(children: children)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, this.onTap, this.trailing, this.soon = false});

  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// "em breve": visível (mostra o mapa do produto) mas NÃO clicável.
  final bool soon;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final enabled = onTap != null && !soon;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: SJSpace.x3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: SJText.body(color: soon ? s.inkFaint : s.ink),
            ),
          ),
          ?trailing,
          if (soon)
            Text('em breve', style: SJText.caption(color: s.inkFaint))
          else if (enabled)
            Icon(Icons.chevron_right, size: 18, color: s.inkSoft),
        ],
      ),
    );
    if (!enabled) return Semantics(enabled: false, child: row);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SJRadius.sm),
      child: row,
    );
  }
}
