import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/theme_controller.dart';
import '../design/tokens.dart';
import '../features/phases/phase_store.dart';

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
    // As fases ficam em memória entre as telas; quem entrar depois neste
    // aparelho não pode ver os capítulos de quem saiu.
    PhaseStore.instance.clear();
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

            const _Section(title: 'Aparência', children: [_Aparencia()]),

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
}

/// Os três modos de aparência, como grupo de escolha.
///
/// Era um mostrador: os dois temas existiam desde sempre, mas nada ligava a
/// preferência ao app, então a tela exibia o modo vigente com um selo "Em uso"
/// e marcava os outros dois como "em breve". Agora que a escolha é real e
/// persistida, o controle certo é rádio — selo diz o que É, rádio diz o que se
/// PODE escolher, e a diferença entre os dois é exatamente o que mudou aqui.
class _Aparencia extends StatelessWidget {
  const _Aparencia();

  @override
  Widget build(BuildContext context) {
    final tema = SjThemeScope.of(context);
    final s = SJTheme.of(context);
    final escuro = s.brightness == Brightness.dark;
    return Column(
      children: [
        const _Modo(mode: ThemeMode.light, label: 'Papel (claro)'),
        const _Modo(mode: ThemeMode.dark, label: 'Atlas (escuro)'),
        _Modo(
          mode: ThemeMode.system,
          label: 'Automático (sistema)',
          // Só no automático a escolha não diz o resultado: "sistema" pode ser
          // qualquer um dos dois, e a pessoa precisa saber em qual está.
          nota: tema.mode == ThemeMode.system
              ? 'Agora: ${escuro ? 'atlas (escuro)' : 'papel (claro)'}'
              : null,
        ),
      ],
    );
  }
}

class _Modo extends StatelessWidget {
  const _Modo({required this.mode, required this.label, this.nota});

  final ThemeMode mode;
  final String label;
  final String? nota;

  @override
  Widget build(BuildContext context) {
    final tema = SjThemeScope.of(context);
    final s = SJTheme.of(context);
    final ativo = tema.mode == mode;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: ativo,
      child: InkWell(
        // O modo ativo não é tocável: tocar nele não faria nada, e um toque
        // sem efeito é o jeito mais rápido de alguém achar que o app travou.
        onTap: ativo ? null : () => tema.setMode(mode),
        borderRadius: BorderRadius.circular(SJRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SJSpace.x3),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: SJText.body(color: s.ink)),
                    if (nota != null) ...[
                      const SizedBox(height: SJSpace.x1),
                      Text(nota!, style: SJText.caption(color: s.inkFaint)),
                    ],
                  ],
                ),
              ),
              Icon(
                ativo ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 20,
                color: ativo ? s.primary : s.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  const _Row({required this.label, this.onTap, this.soon = false});

  final String label;
  final VoidCallback? onTap;

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
