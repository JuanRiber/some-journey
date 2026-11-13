import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../features/phases/phase_domain.dart';
import '../features/phases/phase_store.dart';
import '../features/phases/phase_widgets.dart';
import '../widgets/api_error_view.dart';
import '../widgets/date_field.dart';

/// Itálico serifado das linhas afetivas, composto só a partir dos tokens.
TextStyle _diario(SJScheme s) => TextStyle(
      fontFamily: SJType.serif,
      fontFamilyFallback: SJType.serifFallback,
      fontSize: SJType.bodySmSize,
      height: SJType.bodySmLine / SJType.bodySmSize,
      fontStyle: FontStyle.italic,
      color: s.inkSoft,
    );

Widget _voltar(BuildContext context, SJScheme s) => Row(
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
    );

/// # Fases da vida — os capítulos que a pessoa reconhece
///
/// **Por que existe:** a timeline divide a vida por ano, que é a divisão do
/// calendário. A fase é a divisão DELA: a faculdade, o intercâmbio, o
/// recomeço depois da mudança. Criada aqui, ela vira uma lente na timeline e
/// no atlas.
///
/// **O que esta tela não faz:** não sugere fases, não pede período e não
/// reclama de sobreposição. "Vida adulta" e "recomeços" convivem; exigir o
/// contrário transformaria memória em planilha.
class PhasesScreen extends StatefulWidget {
  const PhasesScreen({super.key});

  @override
  State<PhasesScreen> createState() => _PhasesScreenState();
}

class _PhasesScreenState extends State<PhasesScreen> {
  final _store = PhaseStore.instance;
  ApiError? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final falha = await _store.refresh();
    if (!mounted) return;
    if (falha != null && falha.isUnauthorized) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      return;
    }
    setState(() {
      _error = falha;
      _loading = false;
    });
  }

  /// Abre o formulário e relê ao voltar com mudança — a lista e, pelo
  /// [PhaseStore], a lente da timeline e do atlas.
  Future<void> _open([LifePhase? phase]) async {
    final mudou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PhaseEditScreen(phase: phase)),
    );
    if (mudou == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        child: ValueListenableBuilder<List<LifePhase>>(
          valueListenable: _store,
          builder: (context, phases, _) => RefreshIndicator(
            onRefresh: _load,
            color: s.primary,
            backgroundColor: s.surface,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                SJSpace.screenX, SJSpace.x2, SJSpace.screenX, SJSpace.x12,
              ),
              children: [
                _voltar(context, s),
                const SizedBox(height: SJSpace.x4),
                const SJOverline('Capítulos'),
                const SizedBox(height: SJSpace.x2),
                Text('Fases da vida', style: SJText.h1(color: s.ink)),
                const SizedBox(height: SJSpace.x2),
                Text(
                  'Os capítulos que você reconhece na sua história. Com eles, '
                  'a timeline e o atlas podem ser relidos por partes.',
                  style: _diario(s),
                ),
                const SizedBox(height: SJSpace.x8),
                ..._body(s, phases),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(SJScheme s, List<LifePhase> phases) {
    final falha = _error;
    // A lista antiga continua valendo numa falha de releitura; o erro só
    // ocupa a tela quando não há nada para mostrar no lugar dele.
    if (falha != null && phases.isEmpty) {
      return [
        ApiErrorView(
          error: falha,
          fallbackTitle: 'Suas fases não abriram.',
          onRetry: _load,
          illustrationSize: 120,
        ),
      ];
    }
    if (_loading && phases.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.only(top: SJSpace.x12),
          child: Center(child: SJSpinner()),
        ),
      ];
    }
    if (phases.isEmpty) {
      return [
        SJEmptyState(
          title: 'Nenhuma fase ainda.',
          body: 'A infância, os anos de faculdade, um recomeço — uma fase é um '
              'capítulo que você reconhece. Ninguém precisa de uma para guardar '
              'memórias; ela existe para reler o que já foi guardado.',
          actionLabel: 'Criar uma fase',
          onAction: _open,
        ),
      ];
    }
    return [
      for (final p in phases) ...[
        _card(s, p),
        const SizedBox(height: SJSpace.x3),
      ],
      const SizedBox(height: SJSpace.x5),
      SJButton(label: 'Nova fase', expand: true, onPressed: _open),
    ];
  }

  Widget _card(SJScheme s, LifePhase p) {
    final periodo = p.period;
    final descricao = (p.description ?? '').trim();
    return SJCard(
      padding: const EdgeInsets.all(SJSpace.x5),
      onTap: () => _open(p),
      semanticLabel: periodo.isEmpty ? p.name : '${p.name}, $periodo',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: SJSpace.x2),
            child: PhaseDot(color: p.color, size: 12),
          ),
          const SizedBox(width: SJSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: SJText.h2(color: s.ink)),
                if (periodo.isNotEmpty) ...[
                  const SizedBox(height: SJSpace.x1),
                  Text(periodo, style: SJText.caption(color: s.inkSoft)),
                ],
                if (descricao.isNotEmpty) ...[
                  const SizedBox(height: SJSpace.x2),
                  Text(
                    descricao,
                    style: SJText.bodySm(color: s.inkSoft),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// # Criar ou editar uma fase
///
/// Com [phase] nulo, cria; senão, edita e oferece apagar. Volta `true` quando
/// algo foi gravado, para a lista saber que vale reler.
///
/// Só o nome é obrigatório. As duas datas ficam em aberto de propósito: nem
/// toda pessoa sabe quando a infância virou outra coisa, e pedir data de fim
/// seria pedir que ela decretasse o próprio presente no passado.
class PhaseEditScreen extends StatefulWidget {
  const PhaseEditScreen({super.key, this.phase});

  final LifePhase? phase;

  @override
  State<PhaseEditScreen> createState() => _PhaseEditScreenState();
}

class _PhaseEditScreenState extends State<PhaseEditScreen> {
  late final _name = TextEditingController(text: widget.phase?.name ?? '');
  late final _description =
      TextEditingController(text: widget.phase?.description ?? '');
  late PhaseColor _color = widget.phase?.color ?? PhaseColor.standard;
  late String _start = widget.phase?.startedOn ?? '';
  late String _end = widget.phase?.endedOn ?? '';

  bool _saving = false;
  bool _confirmingDelete = false;
  String _error = '';

  bool get _editing => widget.phase != null;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _description]) {
      c.addListener(_onChanged);
    }
  }

  void _onChanged() => setState(() {});

  Map<String, dynamic> get _patch => phasePatch(
        widget.phase!,
        name: _name.text,
        description: _description.text,
        color: _color,
        startedOn: _start,
        endedOn: _end,
      );

  /// Na edição, o botão só acende quando algo mudou; na criação, quando há
  /// nome — o único campo sem o qual a fase não existe.
  bool get _canSave =>
      !_saving &&
      (_editing ? _patch.isNotEmpty : _name.text.trim().isNotEmpty);

  Future<void> _save() async {
    final aviso = validatePhase(
      name: _name.text,
      startedOn: _start,
      endedOn: _end,
    );
    if (aviso != null) {
      setState(() => _error = aviso);
      return;
    }
    setState(() {
      _error = '';
      _saving = true;
    });
    try {
      if (_editing) {
        await Api.instance.updatePhase(widget.phase!.id, _patch);
      } else {
        await Api.instance.createPhase(phaseCreateBody(
          name: _name.text,
          description: _description.text,
          color: _color,
          startedOn: _start,
          endedOn: _end,
        ));
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      _falhou(e);
    }
  }

  Future<void> _delete() async {
    setState(() {
      _error = '';
      _saving = true;
    });
    try {
      await Api.instance.deletePhase(widget.phase!.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      _falhou(e);
    }
  }

  void _falhou(ApiError e) {
    if (!mounted) return;
    if (e.isUnauthorized) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      return;
    }
    setState(() {
      // 404 aqui é a fase apagada noutra tela enquanto esta estava aberta.
      _error = e.status == 404 ? 'Essa fase não existe mais.' : e.message;
      _saving = false;
      _confirmingDelete = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        // Coluna rolável, como os outros formulários do app, e não ListView:
        // o formulário é curto e precisa existir inteiro — o botão de salvar
        // não pode depender de ter sido rolado até a vista para ser construído.
        // A folga de baixo acompanha o teclado.
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: SJSpace.screenX,
            right: SJSpace.screenX,
            top: SJSpace.x2,
            bottom: SJSpace.x12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _voltar(context, s),
              const SizedBox(height: SJSpace.x4),
              SJOverline(_editing ? 'Editar capítulo' : 'Novo capítulo'),
              const SizedBox(height: SJSpace.x2),
              Text(
                _editing ? 'Ajustar a fase' : 'Nomear uma fase',
                style: SJText.h1(color: s.ink),
              ),
              const SizedBox(height: SJSpace.x2),
              Text(
                'Dê o nome que ela tem na sua cabeça. O resto pode ficar em branco.',
                style: _diario(s),
              ),
              const SizedBox(height: SJSpace.x6),
              SJTextField(
                label: 'Nome da fase',
                controller: _name,
                hint: 'Os anos de faculdade',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: SJSpace.x4),
              SJTextField(
                label: 'Sobre ela (opcional)',
                controller: _description,
                hint: 'O que marcou esse capítulo',
                maxLines: 3,
                minLines: 2,
              ),
              const SizedBox(height: SJSpace.x5),
              _cores(s),
              const SizedBox(height: SJSpace.x5),
              _data(
                s,
                label: 'Começou (opcional)',
                value: _start,
                onChange: (v) => setState(() => _start = v),
              ),
              const SizedBox(height: SJSpace.x4),
              _data(
                s,
                label: 'Terminou (opcional)',
                value: _end,
                onChange: (v) => setState(() => _end = v),
                hint: 'Em branco é a fase em que você ainda está.',
              ),
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
                label: _editing ? 'Salvar alterações' : 'Criar fase',
                loading: _saving && !_confirmingDelete,
                expand: true,
                onPressed: _canSave ? _save : null,
              ),
              if (_editing) ...[
                const SizedBox(height: SJSpace.x8),
                _apagar(s),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Os cinco papéis da paleta, cada um no tom que ele tem NESTE modo.
  Widget _cores(SJScheme s) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('COR', style: SJText.overline(color: s.accent)),
          const SizedBox(height: SJSpace.x2),
          Wrap(
            spacing: SJSpace.x2,
            runSpacing: SJSpace.x2,
            children: [
              for (final c in PhaseColor.values)
                Semantics(
                  selected: c == _color,
                  inMutuallyExclusiveGroup: true,
                  child: SJChip(
                    label: c.label,
                    color: phaseTone(s, c),
                    selected: c == _color,
                    onTap: () => setState(() => _color = c),
                  ),
                ),
            ],
          ),
        ],
      );

  /// Data opcional: o campo de data do app, mais um jeito de voltar a deixá-la
  /// em branco — sem ele, escolher uma data seria um caminho sem volta.
  Widget _data(
    SJScheme s, {
    required String label,
    required String value,
    required ValueChanged<String> onChange,
    String? hint,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SJDateField(label: label, value: value, onChange: onChange),
          if (hint != null || value.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    hint ?? '',
                    style: SJText.caption(color: s.inkFaint),
                  ),
                ),
                if (value.isNotEmpty)
                  SJButton(
                    label: 'Deixar em branco',
                    variant: SJButtonVariant.text,
                    onPressed: () => onChange(''),
                  ),
              ],
            ),
        ],
      );

  /// Apagar é discreto e pede confirmação — e a confirmação diz o que NÃO
  /// acontece, que é a dúvida de quem está prestes a tocar: as memórias ficam.
  Widget _apagar(SJScheme s) {
    if (!_confirmingDelete) {
      return SJButton(
        label: 'Apagar esta fase',
        variant: SJButtonVariant.text,
        expand: true,
        onPressed: _saving ? null : () => setState(() => _confirmingDelete = true),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Apagar esta fase? As memórias e jornadas dela continuam onde estão '
          '— só perdem a etiqueta.',
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
                onPressed:
                    _saving ? null : () => setState(() => _confirmingDelete = false),
              ),
            ),
            const SizedBox(width: SJSpace.x3),
            Expanded(
              child: SJButton(
                label: 'Apagar',
                loading: _saving,
                onPressed: _saving ? null : _delete,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
