import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';

/// # Nova jornada — abrir um capítulo da vida.
///
/// **Por que existe:** uma jornada não é uma pasta: é uma FASE (o mochilão, a
/// faculdade, a mudança de cidade). Dar nome a ela é o gesto que transforma
/// pontos soltos em narrativa.
///
/// **O que o usuário sente:** começo. A tela pergunta pouco de propósito — o
/// capítulo se escreve depois, com as memórias.
///
/// **Ação principal:** criar (nasce como rascunho; o ciclo de vida — iniciar,
/// pausar, concluir — vive na tela de detalhe).
///
/// **Atrito:** só o TÍTULO é obrigatório. Descrição e atmosfera são convites,
/// não exigências, e a privacidade já vem no padrão mais protetor.
class JourneyNewScreen extends StatefulWidget {
  const JourneyNewScreen({super.key});

  @override
  State<JourneyNewScreen> createState() => _JourneyNewScreenState();
}

class _JourneyNewScreenState extends State<JourneyNewScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _mood = TextEditingController();
  final _descriptionFocus = FocusNode();
  final _moodFocus = FocusNode();
  bool _isPrivate = true;
  bool _saving = false;
  String _error = '';

  Future<void> _onSave() async {
    setState(() => _error = '');
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Dê um nome à sua jornada.');
      return;
    }
    setState(() => _saving = true);
    try {
      final j = await Api.instance.createJourney({
        'title': _title.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        'mood': _mood.text.trim().isEmpty ? null : _mood.text.trim(),
        'is_private': _isPrivate,
      });
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/journey', arguments: j.id);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
        return;
      }
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _mood.dispose();
    _descriptionFocus.dispose();
    _moodFocus.dispose();
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
            left: SJSpace.screenX,
            right: SJSpace.screenX,
            top: SJSpace.x2,
            bottom: SJSpace.x12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: 'Voltar',
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: s.ink, size: 22),
                  ),
                ),
              ),
              const SizedBox(height: SJSpace.x4),
              const SJOverline('Novo capítulo'),
              const SizedBox(height: SJSpace.x2),
              Text('Uma nova jornada', style: SJText.h1(color: s.ink)),
              const SizedBox(height: SJSpace.x2),
              Text(
                'Uma fase, uma viagem, um recomeço — dê o nome que ela tem na sua cabeça.',
                style: SJText.bodySm(color: s.inkSoft).copyWith(
                  fontFamily: SJType.serif,
                  fontFamilyFallback: SJType.serifFallback,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: SJSpace.x6),
              SJTextField(
                label: 'Nome da jornada',
                controller: _title,
                hint: 'Mochilão pela Europa',
                autofocus: true,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _descriptionFocus.requestFocus(),
              ),
              const SizedBox(height: SJSpace.x4),
              SJTextField(
                label: 'Sobre ela (opcional)',
                controller: _description,
                focusNode: _descriptionFocus,
                hint: 'O que essa fase significou',
                maxLines: 3,
                minLines: 2,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _moodFocus.requestFocus(),
              ),
              const SizedBox(height: SJSpace.x4),
              SJTextField(
                label: 'Atmosfera (opcional)',
                controller: _mood,
                focusNode: _moodFocus,
                hint: 'contemplativo, intenso, leve...',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _onSave(),
              ),
              const SizedBox(height: SJSpace.x5),
              _privacyRow(s),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: SJSpace.x3),
                Text(_error, textAlign: TextAlign.center, style: SJText.caption(color: s.danger)),
              ],
              const SizedBox(height: SJSpace.x6),
              SJButton(
                label: 'Criar jornada',
                loading: _saving,
                expand: true,
                onPressed: _saving ? null : _onSave,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Privacidade como uma linha calma (não um "formulário de permissões"): o
  /// padrão é privado, e o texto explica o que isso significa hoje.
  Widget _privacyRow(SJScheme s) => Container(
        padding: const EdgeInsets.all(SJSpace.x4),
        decoration: BoxDecoration(
          color: s.surfaceAlt,
          borderRadius: BorderRadius.circular(SJRadius.md),
          border: Border.all(color: s.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Só para mim', style: SJText.bodySm(color: s.ink)),
                  const SizedBox(height: SJSpace.x1),
                  Text(
                    'Suas jornadas são privadas por padrão.',
                    style: SJText.caption(color: s.inkSoft),
                  ),
                ],
              ),
            ),
            Switch(
              value: _isPrivate,
              activeThumbColor: s.primary,
              onChanged: (v) => setState(() => _isPrivate = v),
            ),
          ],
        ),
      );
}
