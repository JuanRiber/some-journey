import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import 'components.dart';
import 'sj_theme.dart';
import 'tokens.dart';

/// # Galeria do design system — `DesignGalleryScreen`
///
/// PORQUÊ existe: é o "espelho" onde VEMOS o sistema inteiro nos dois modos ao
/// mesmo tempo — paleta, escala tipográfica e TODOS os componentes. Renderiza
/// dois painéis empilhados: um em `sjLight` (papel quente, padrão) e outro em
/// `sjDark` (atlas noturno), cada um embrulhado no seu `SJTheme`, para conferir
/// contraste, respiro e coerência lado a lado. Não é tela de produto; é a
/// bancada de verificação do time.
class DesignGalleryScreen extends StatelessWidget {
  const DesignGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Dois painéis, um por modo. Cada um reprovê o esquema à sua subárvore.
    return ColoredBox(
      color: sjDark.bgDeep,
      child: SingleChildScrollView(
        child: Column(
          children: const [
            SJTheme(
              scheme: sjLight,
              child: _GalleryPanel(modeLabel: 'CLARO · PAPEL QUENTE'),
            ),
            SJTheme(
              scheme: sjDark,
              child: _GalleryPanel(modeLabel: 'ESCURO · ATLAS NOTURNO'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Um painel completo do sistema num único modo (lê `SJTheme.of(context)`).
class _GalleryPanel extends StatelessWidget {
  const _GalleryPanel({required this.modeLabel});

  final String modeLabel;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Container(
      width: double.infinity,
      color: s.bg,
      padding: const EdgeInsets.symmetric(
        horizontal: SJSpace.screenX,
        vertical: SJSpace.x10,
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SJOverline(modeLabel),
            const SizedBox(height: SJSpace.x2),
            Text('Some Journey', style: SJText.display(color: s.ink)),
            Text(
              'Sua vida contada através dos lugares.',
              style: SJText.body(
                color: s.inkSoft,
              ).copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: SJSpace.x10),

            _Block(
              numeral: '01',
              overline: 'PALETA',
              title: 'Papéis de cor',
              child: _Swatches(scheme: s),
            ),
            _Block(
              numeral: '02',
              overline: 'TIPOGRAFIA',
              title: 'Escala',
              child: _TypeScale(scheme: s),
            ),
            _Block(
              numeral: '03',
              overline: 'AÇÃO',
              title: 'Botões',
              child: _Buttons(),
            ),
            _Block(
              numeral: '04',
              overline: 'ENTRADA',
              title: 'Campos',
              child: _Fields(),
            ),
            _Block(
              numeral: '05',
              overline: 'CONTEÚDO',
              title: 'Cards',
              child: _Cards(scheme: s),
            ),
            _Block(
              numeral: '06',
              overline: 'MARCADORES',
              title: 'Chips e selos',
              child: _ChipsBadges(scheme: s),
            ),
            _Block(
              numeral: '07',
              overline: 'FLUTUANTE',
              title: 'Sheet e FAB',
              child: _SheetAndFab(),
            ),
            _Block(
              numeral: '08',
              overline: 'GUIA',
              title: 'Estado vazio',
              child: SJCard(
                padding: EdgeInsets.zero,
                child: SizedBox(
                  height: 320,
                  child: SJEmptyState(
                    illustration: Icon(
                      Icons.explore_outlined,
                      size: 64,
                      color: s.frame,
                    ),
                    title: 'Nenhuma jornada ainda',
                    body:
                        'Toque em criar para abrir seu primeiro capítulo — escolha um destino e comece a colecionar momentos.',
                    actionLabel: 'Criar primeira jornada',
                    onAction: () {},
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bloco de seção da galeria: cabeçalho numerado + conteúdo, com respiro amplo.
class _Block extends StatelessWidget {
  const _Block({
    required this.numeral,
    required this.overline,
    required this.title,
    required this.child,
  });

  final String numeral;
  final String overline;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SJSpace.x12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SJSectionHeader(title: title, overline: overline, numeral: numeral),
          const SizedBox(height: SJSpace.x5),
          child,
        ],
      ),
    );
  }
}

/// Amostras de todos os papéis de cor do esquema ativo.
class _Swatches extends StatelessWidget {
  const _Swatches({required this.scheme});
  final SJScheme scheme;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, Color)>[
      ('bg', scheme.bg),
      ('surface', scheme.surface),
      ('surfaceAlt', scheme.surfaceAlt),
      ('ink', scheme.ink),
      ('inkSoft', scheme.inkSoft),
      ('line', scheme.line),
      ('frame', scheme.frame),
      ('primary', scheme.primary),
      ('secondary', scheme.secondary),
      ('accent', scheme.accent),
      ('moss', scheme.moss),
      ('highlight', scheme.highlight),
      ('danger', scheme.danger),
    ];
    return Wrap(
      spacing: SJSpace.x3,
      runSpacing: SJSpace.x3,
      children: [
        for (final (name, color) in entries)
          SizedBox(
            width: 72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(SJRadius.md),
                    border: Border.all(color: scheme.line),
                  ),
                ),
                const SizedBox(height: SJSpace.x1),
                Text(name, style: SJText.caption(color: scheme.inkSoft)),
              ],
            ),
          ),
      ],
    );
  }
}

/// A escala tipográfica inteira, com o nome de cada nível ao lado.
class _TypeScale extends StatelessWidget {
  const _TypeScale({required this.scheme});
  final SJScheme scheme;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, TextStyle)>[
      ('display', SJText.display(color: scheme.ink)),
      ('h1', SJText.h1(color: scheme.ink)),
      ('h2', SJText.h2(color: scheme.ink)),
      ('title', SJText.title(color: scheme.ink)),
      ('body', SJText.body(color: scheme.ink)),
      ('bodySm', SJText.bodySm(color: scheme.inkSoft)),
      ('caption', SJText.caption(color: scheme.inkSoft)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (name, style) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: SJSpace.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SJOverline(name, color: scheme.inkFaint),
                Text('Um dia inteiro numa foto', style: style),
              ],
            ),
          ),
        const SizedBox(height: SJSpace.x2),
        const SJOverline('01 / OVERLINE MONO', numeral: '01'),
      ],
    );
  }
}

/// Todas as variantes e estados do botão.
class _Buttons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: SJSpace.x3,
      runSpacing: SJSpace.x3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SJButton(label: 'Salvar', onPressed: () {}),
        SJButton(
          label: 'Voltar',
          variant: SJButtonVariant.secondary,
          onPressed: () {},
        ),
        SJButton(
          label: 'Saber mais',
          variant: SJButtonVariant.text,
          onPressed: () {},
        ),
        SJButton(
          label: 'Com ícone',
          icon: Icons.place_outlined,
          onPressed: () {},
        ),
        const SJButton(label: 'Desabilitado'),
        const SJButton(label: 'Carregando', loading: true),
      ],
    );
  }
}

/// Campos em repouso e em erro (o foco é demonstrável tocando o campo).
class _Fields extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        SJTextField(label: 'E-mail', hint: 'voce@exemplo.com'),
        SizedBox(height: SJSpace.x5),
        SJTextField(
          label: 'Senha',
          hint: '••••••••',
          obscureText: true,
          errorText: 'Senha muito curta (mínimo 8).',
        ),
        SizedBox(height: SJSpace.x5),
        SJTextField(
          label: 'Nota',
          hint: 'O que esse lugar te fez sentir?',
          maxLines: 3,
        ),
      ],
    );
  }
}

/// Card comum + card foto-protagonista (com placeholder de foto).
class _Cards extends StatelessWidget {
  const _Cards({required this.scheme});
  final SJScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SJCard(
          onTap: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Manhã em Sintra', style: SJText.title(color: scheme.ink)),
              const SizedBox(height: SJSpace.x2),
              Text(
                'A névoa subia entre os palácios enquanto tomávamos o primeiro café.',
                style: SJText.body(color: scheme.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: SJSpace.x5),
        SJPhotoCard(
          overline: 'PORTUGAL · 2025',
          title: 'A costa até o fim do mundo',
          subtitle: '12 momentos · 340 km',
          onTap: () {},
          trailing: const SJBadge('ATIVA'),
          // Placeholder de foto: um gradiente do frame ao primary do modo.
          imageChild: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.frame, scheme.primary],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Chips (tonais, com estado selecionado) e badges (selos cheios).
class _ChipsBadges extends StatelessWidget {
  const _ChipsBadges({required this.scheme});
  final SJScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: SJSpace.x2,
          runSpacing: SJSpace.x2,
          children: [
            SJChip(
              label: 'Praia',
              icon: Icons.beach_access_outlined,
              onTap: () {},
            ),
            SJChip(label: 'Cidade', selected: true, onTap: () {}),
            SJChip(label: 'Natureza', color: scheme.moss, onTap: () {}),
            SJChip(label: 'Gastronomia', color: scheme.highlight, onTap: () {}),
          ],
        ),
        const SizedBox(height: SJSpace.x5),
        Wrap(
          spacing: SJSpace.x2,
          runSpacing: SJSpace.x2,
          children: [
            const SJBadge('ATIVA'),
            SJBadge('RASCUNHO', color: scheme.inkSoft),
            SJBadge('CONCLUÍDA', color: scheme.moss),
            SJBadge('PAUSADA', color: scheme.highlight),
          ],
        ),
      ],
    );
  }
}

/// Gatilho do bottom sheet + o FAB.
class _SheetAndFab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SJButton(
          label: 'Abrir sheet',
          variant: SJButtonVariant.secondary,
          onPressed: () => showSJSheet<void>(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Adicionar momento', style: SJText.h2(color: s.ink)),
                const SizedBox(height: SJSpace.x2),
                Text(
                  'Escolha de onde vem esta memória.',
                  style: SJText.body(color: s.inkSoft),
                ),
                const SizedBox(height: SJSpace.x6),
                SJButton(
                  label: 'Da câmera',
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: SJSpace.x6),
        SJFab(icon: Icons.add, semanticLabel: 'Nova memória', onTap: () {}),
      ],
    );
  }
}
