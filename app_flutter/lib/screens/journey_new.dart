import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Criar uma jornada (uma viagem, fase, cidade, rotina...). Nasce como
/// rascunho; o ciclo de vida acontece na tela de detalhe.
class JourneyNewScreen extends StatefulWidget {
  const JourneyNewScreen({super.key});

  @override
  State<JourneyNewScreen> createState() => _JourneyNewScreenState();
}

class _JourneyNewScreenState extends State<JourneyNewScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _mood = TextEditingController();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Text('← Voltar',
                    style: TextStyle(color: SJColors.ink, fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 12),
              Text('Nova jornada', style: serif(28)),
              const SizedBox(height: 6),
              Text(
                'Uma viagem, uma fase da vida, uma cidade ou uma rotina — qualquer conjunto '
                'de memórias que faça sentido para você.',
                style: serif(14.5, color: SJColors.inkSoft, style: FontStyle.italic, height: 1.45),
              ),
              const FieldLabel('Nome da jornada'),
              TextField(
                controller: _title,
                decoration: const InputDecoration(hintText: 'Ex.: Fortaleza Nights'),
              ),
              const FieldLabel('Descrição (opcional)'),
              TextField(
                controller: _description,
                maxLines: 4,
                decoration:
                    const InputDecoration(hintText: 'Noites, ruas e lugares que ficaram marcados...'),
              ),
              const FieldLabel('Atmosfera (opcional)'),
              TextField(
                controller: _mood,
                decoration: const InputDecoration(hintText: 'Ex.: noturno, nostálgico, urbano'),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Uma palavra ou clima que resume o sentimento da jornada.',
                    style: TextStyle(color: SJColors.inkSoft, fontSize: 12)),
              ),
              const FieldLabel('Privacidade'),
              Row(
                children: [
                  Switch(
                    value: _isPrivate,
                    onChanged: (v) => setState(() => _isPrivate = v),
                    activeTrackColor: SJColors.cyan,
                    thumbColor: const WidgetStatePropertyAll(SJColors.ink),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isPrivate ? 'Só você vê esta jornada' : 'Pode ser compartilhada',
                      style: const TextStyle(color: SJColors.inkSoft, fontSize: 14),
                    ),
                  ),
                ],
              ),
              InlineError(_error),
              const SizedBox(height: 20),
              PrimaryButton(
                  label: _saving ? 'Criando...' : 'Criar jornada',
                  onPressed: _onSave,
                  busy: _saving),
            ],
          ),
        ),
      ),
    );
  }
}
