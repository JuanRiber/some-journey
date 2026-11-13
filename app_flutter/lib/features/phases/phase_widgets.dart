import 'package:flutter/widgets.dart';

import '../../design/components.dart';
import '../../design/sj_theme.dart';
import '../../design/tokens.dart';
import 'phase_domain.dart';
import 'phase_store.dart';

/// O tom do papel da paleta no modo ATIVO. É aqui, e só aqui, que um
/// [PhaseColor] vira cor: o mesmo papel pinta diferente no papel quente e no
/// atlas noturno, e é por isso que a fase guarda o papel e não a cor.
Color phaseTone(SJScheme s, PhaseColor c) => switch (c) {
      PhaseColor.primary => s.primary,
      PhaseColor.secondary => s.secondary,
      PhaseColor.accent => s.accent,
      PhaseColor.moss => s.moss,
      PhaseColor.highlight => s.highlight,
    };

/// O ponto colorido que identifica a fase nas listas.
class PhaseDot extends StatelessWidget {
  const PhaseDot({super.key, required this.color, this.size = 10});

  final PhaseColor color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: phaseTone(SJTheme.of(context), color),
          shape: BoxShape.circle,
        ),
      );
}

/// A etiqueta da fase no detalhe de uma memória ou jornada: o ponto e o nome.
///
/// Lê o nome do [PhaseStore] em vez de receber pronto porque a API devolve só
/// o id no vínculo — e assim a etiqueta acompanha uma fase renomeada sem que o
/// detalhe precise recarregar. Sem fase, ou com uma que a lista ainda não
/// trouxe, não desenha nada.
class PhaseTag extends StatelessWidget {
  const PhaseTag({super.key, required this.phaseId});

  final String? phaseId;

  @override
  Widget build(BuildContext context) {
    if (phaseId == null) return const SizedBox.shrink();
    return ValueListenableBuilder<List<LifePhase>>(
      valueListenable: PhaseStore.instance,
      builder: (context, phases, _) {
        final fase = phaseById(phases, phaseId);
        if (fase == null) return const SizedBox.shrink();
        final s = SJTheme.of(context);
        return Semantics(
          label: 'Fase da vida: ${fase.name}',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhaseDot(color: fase.color, size: 8),
              const SizedBox(width: SJSpace.x2),
              Flexible(
                child: Text(
                  fase.name,
                  style: SJText.caption(color: s.inkSoft),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Uma fileira de fases para escolher UMA — ou nenhuma.
///
/// É a mesma peça na lente (timeline, atlas) e no seletor (formulários); muda
/// só o nome do "nenhuma" e o que tocar de novo na escolhida faz. Sem fase
/// cadastrada ela não desenha nada: quem nunca criou uma fase não deve ver um
/// controle vazio pedindo atenção.
class _PhaseChoice extends StatelessWidget {
  const _PhaseChoice({
    required this.phases,
    required this.selected,
    required this.onChanged,
    required this.noneLabel,
    required this.label,
    required this.scrolls,
    required this.toggles,
  });

  final List<LifePhase> phases;
  final String? selected;
  final ValueChanged<String?> onChanged;
  final String noneLabel;
  final String label;

  /// Lente: uma linha que rola de lado (o topo da tela não pode crescer).
  /// Seletor: quebra em linhas, porque num formulário cada opção precisa estar
  /// à vista para a escolha ser feita olhando todas.
  final bool scrolls;

  /// Na lente, tocar na fase já escolhida volta para a vida toda — o gesto de
  /// "tirar o filtro" que a pessoa tenta primeiro. No seletor não: desfazer a
  /// escolha é tocar em "Nenhuma", que está ali do lado.
  final bool toggles;

  @override
  Widget build(BuildContext context) {
    if (phases.isEmpty) return const SizedBox.shrink();
    final s = SJTheme.of(context);

    Widget chip(String text, String? id, Color? color) {
      final escolhido = selected == id;
      return Semantics(
        selected: escolhido,
        inMutuallyExclusiveGroup: true,
        child: SJChip(
          label: text,
          color: color,
          selected: escolhido,
          onTap: () => onChanged(escolhido && toggles ? null : id),
        ),
      );
    }

    final chips = <Widget>[
      chip(noneLabel, null, null),
      for (final p in phases) chip(p.name, p.id, phaseTone(s, p.color)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label.toUpperCase(), style: SJText.overline(color: s.accent)),
        const SizedBox(height: SJSpace.x2),
        if (scrolls)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final c in chips)
                  Padding(
                    padding: const EdgeInsets.only(right: SJSpace.x2),
                    child: c,
                  ),
              ],
            ),
          )
        else
          Wrap(spacing: SJSpace.x2, runSpacing: SJSpace.x2, children: chips),
      ],
    );
  }
}

/// A LENTE: reler a timeline ou o atlas por uma fase.
///
/// `null` é a vida toda. Some quando não há fase cadastrada.
class PhaseLens extends StatelessWidget {
  const PhaseLens({
    super.key,
    required this.phases,
    required this.selected,
    required this.onChanged,
  });

  final List<LifePhase> phases;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => _PhaseChoice(
        phases: phases,
        selected: selected,
        onChanged: onChanged,
        noneLabel: 'A vida toda',
        label: 'Ler por fase',
        scrolls: true,
        toggles: true,
      );
}

/// O SELETOR: em que fase esta memória ou jornada mora.
///
/// `null` é nenhuma — e continua sendo o normal. Some quando não há fase
/// cadastrada: o formulário de quem não usa fases fica exatamente como era.
class PhasePicker extends StatelessWidget {
  const PhasePicker({
    super.key,
    required this.phases,
    required this.selected,
    required this.onChanged,
  });

  final List<LifePhase> phases;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => _PhaseChoice(
        phases: phases,
        selected: selected,
        onChanged: onChanged,
        noneLabel: 'Nenhuma',
        label: 'Fase da vida (opcional)',
        scrolls: false,
        toggles: false,
      );
}
