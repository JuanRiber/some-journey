import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/illustrations.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../models.dart';

/// # Editar jornada — corrigir o nome de um capítulo sem perdê-lo.
///
/// **Por que existe:** sem esta tela, um título errado só se conserta apagando a
/// jornada e criando outra — o que desfaz todos os vínculos com as memórias. Um
/// erro de digitação custava o capítulo inteiro.
///
/// **O que o usuário sente:** continuidade. A tela abre com o que já está
/// escrito e devolve para o detalhe, sem cerimônia de "formulário".
///
/// **Atrito:** o botão só acende quando algo mudou de fato.
///
/// O ciclo de vida (iniciar, pausar, concluir) NÃO mora aqui: são transições
/// com regra própria, e vivem no detalhe da jornada.
///
/// A capa também mora aqui, e fora do formulário: ela salva no próprio gesto de
/// escolher, como a foto do perfil. É upload, não campo — segurá-la até o
/// "Salvar" só criaria um estado em que a imagem já subiu e a tela finge que
/// não. A lista de jornadas desenha essa capa desde sempre; até agora nenhuma
/// tela sabia defini-la, e o campo só podia chegar vazio.

/// Monta o corpo do PATCH com o que REALMENTE mudou.
///
/// Duas regras que não são óbvias e que vêm do backend:
///
/// 1. Campo ausente não é tocado — então mandar tudo sempre sobrescreveria
///    trabalho de outra sessão à toa. Só vai o que o usuário mexeu.
/// 2. `null` NÃO limpa: o repositório ignora nulos (`if description is not
///    None`). Para APAGAR uma descrição é preciso mandar string vazia. Mandar
///    `null`, que seria o intuitivo, falha em silêncio: a pessoa apaga o texto,
///    salva, e ele volta.
Map<String, dynamic> journeyPatch(
  Journey original, {
  required String title,
  required String description,
  required String mood,
  required bool isPrivate,
}) {
  final patch = <String, dynamic>{};
  final t = title.trim();
  if (t != original.title) patch['title'] = t;

  final d = description.trim();
  if (d != (original.description ?? '')) patch['description'] = d;

  final m = mood.trim();
  if (m != (original.mood ?? '')) patch['mood'] = m;

  if (isPrivate != original.isPrivate) patch['is_private'] = isPrivate;
  return patch;
}

class JourneyEditScreen extends StatefulWidget {
  const JourneyEditScreen({super.key, required this.journeyId});

  final String journeyId;

  @override
  State<JourneyEditScreen> createState() => _JourneyEditScreenState();
}

class _JourneyEditScreenState extends State<JourneyEditScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _mood = TextEditingController();
  final _descriptionFocus = FocusNode();
  final _moodFocus = FocusNode();

  Journey? _original;
  bool _isPrivate = true;
  bool _saving = false;
  bool _enviandoCapa = false;
  String _error = '';
  String _loadError = '';

  /// A capa já foi gravada no servidor, mesmo que nenhum campo tenha mudado.
  /// É o que faz a tela de detalhe recarregar ao voltar: sem isso, quem só
  /// trocou a foto continuaria vendo a capa antiga até a próxima leitura.
  bool _capaMudou = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _description, _mood]) {
      c.addListener(_onChanged);
    }
    _load();
  }

  void _onChanged() => setState(() {});

  /// O botão só acende quando há o que salvar — assim ele responde a uma
  /// pergunta ("mudei alguma coisa?") em vez de convidar a um toque inútil.
  bool get _dirty {
    final o = _original;
    if (o == null) return false;
    return journeyPatch(
      o,
      title: _title.text,
      description: _description.text,
      mood: _mood.text,
      isPrivate: _isPrivate,
    ).isNotEmpty;
  }

  Future<void> _load() async {
    try {
      final j = await Api.instance.getJourney(widget.journeyId);
      if (!mounted) return;
      setState(() {
        _original = j;
        _title.text = j.title;
        _description.text = j.description ?? '';
        _mood.text = j.mood ?? '';
        _isPrivate = j.isPrivate;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() => _loadError =
          e.isNotFound ? 'Jornada não encontrada.' : e.message);
    }
  }

  Future<void> _onSave() async {
    final o = _original;
    if (o == null) return;
    setState(() => _error = '');

    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Uma jornada precisa de um nome.');
      return;
    }

    final patch = journeyPatch(
      o,
      title: _title.text,
      description: _description.text,
      mood: _mood.text,
      isPrivate: _isPrivate,
    );
    // Nada mudou nos campos: voltar é a resposta honesta, não uma requisição
    // vazia. Ainda assim a capa pode ter mudado — ela não passa pelo PATCH.
    if (patch.isEmpty) {
      Navigator.of(context).pop(_capaMudou);
      return;
    }

    setState(() => _saving = true);
    try {
      await Api.instance.updateJourney(o.id, patch);
      if (!mounted) return;
      // `true` avisa o detalhe que vale recarregar.
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  /// Escolhe a capa e já envia.
  ///
  /// Reduz ANTES de subir: o teto do backend é 5 MB e uma foto de câmera passa
  /// disso com folga — o 413 chegaria depois de a pessoa ter esperado o envio
  /// inteiro. 2048 é generoso para uma capa que ocupa a largura da tela.
  Future<void> _escolherCapa() async {
    final o = _original;
    if (o == null) return;
    final escolhida = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (escolhida == null) return;
    setState(() {
      _error = '';
      _enviandoCapa = true;
    });
    try {
      final bytes = await escolhida.readAsBytes();
      final atualizada = await Api.instance.setJourneyCover(
        o.id,
        bytes,
        escolhida.name,
        // O backend decide o tipo pelos bytes; isto é só o que o aparelho diz.
        escolhida.mimeType ?? 'image/jpeg',
      );
      if (!mounted) return;
      setState(() {
        _original = atualizada;
        _capaMudou = true;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível enviar a capa.');
    } finally {
      if (mounted) setState(() => _enviandoCapa = false);
    }
  }

  /// Tira a capa escolhida. Pode não esvaziar a foto: sem capa própria, o
  /// backend volta a mostrar a primeira imagem do rastro. Por isso o que vale
  /// é a jornada que ele devolve, e não um `null` otimista daqui.
  Future<void> _removerCapa() async {
    final o = _original;
    if (o == null) return;
    setState(() {
      _error = '';
      _enviandoCapa = true;
    });
    try {
      final atualizada = await Api.instance.removeJourneyCover(o.id);
      if (!mounted) return;
      setState(() {
        _original = atualizada;
        _capaMudou = true;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        return;
      }
      setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível remover a capa.');
    } finally {
      if (mounted) setState(() => _enviandoCapa = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _mood]) {
      c.removeListener(_onChanged);
      c.dispose();
    }
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
                    // Leva a notícia da capa: ela já foi gravada, e o detalhe
                    // precisa recarregar mesmo sem nenhum campo ter mudado.
                    onPressed: () => Navigator.of(context).maybePop(_capaMudou),
                    icon: Icon(Icons.arrow_back, color: s.ink, size: 22),
                  ),
                ),
              ),
              const SizedBox(height: SJSpace.x4),
              if (_loadError.isNotEmpty)
                _falha(s)
              else if (_original == null)
                _esperando(s)
              else
                ..._formulario(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _falha(SJScheme s) => Padding(
        padding: const EdgeInsets.only(top: SJSpace.x10),
        child: SJEmptyState(
          illustration: const SJIllustration(kind: SJIllustrationKind.error),
          title: 'Não deu para abrir este capítulo.',
          body: _loadError,
          actionLabel: 'Tentar de novo',
          onAction: () {
            setState(() => _loadError = '');
            _load();
          },
        ),
      );

  Widget _esperando(SJScheme s) => const Padding(
        padding: EdgeInsets.only(top: SJSpace.x16),
        child: Center(child: SJSpinner()),
      );

  List<Widget> _formulario(SJScheme s) => [
        const SJOverline('Editar capítulo'),
        const SizedBox(height: SJSpace.x2),
        Text('Ajustar a jornada', style: SJText.h1(color: s.ink)),
        const SizedBox(height: SJSpace.x2),
        Text(
          'Um nome pode mudar depois — o que foi vivido nele continua o mesmo.',
          style: SJText.bodySm(color: s.inkSoft).copyWith(
            fontFamily: SJType.serif,
            fontFamilyFallback: SJType.serifFallback,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: SJSpace.x6),
        _capa(s),
        const SizedBox(height: SJSpace.x6),
        SJTextField(
          label: 'Nome da jornada',
          controller: _title,
          hint: 'Mochilão pela Europa',
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
          onSubmitted: (_) => _dirty ? _onSave() : null,
        ),
        const SizedBox(height: SJSpace.x5),
        _privacidade(s),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: SJSpace.x3),
          Text(_error,
              textAlign: TextAlign.center,
              style: SJText.caption(color: s.danger)),
        ],
        const SizedBox(height: SJSpace.x6),
        SJButton(
          label: 'Salvar alterações',
          loading: _saving,
          expand: true,
          onPressed: (_saving || !_dirty) ? null : _onSave,
        ),
      ];

  /// A capa, no formato em que ela vai aparecer na lista de jornadas (4:3) —
  /// para que a escolha seja feita vendo o enquadramento real, e não uma
  /// miniatura que esconde o corte.
  Widget _capa(SJScheme s) {
    final url = _original?.coverImageUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: url == null ? 'Escolher capa' : 'Trocar a capa',
          child: SJPressable(
            onTap: _enviandoCapa ? null : _escolherCapa,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: s.surfaceAlt,
                  borderRadius: BorderRadius.circular(SJRadius.md),
                  border: Border.all(color: s.line),
                ),
                child: _dentroDaCapa(s, url),
              ),
            ),
          ),
        ),
        const SizedBox(height: SJSpace.x2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SJButton(
              label: url == null ? 'Escolher capa' : 'Trocar capa',
              variant: SJButtonVariant.text,
              onPressed: _enviandoCapa ? null : _escolherCapa,
            ),
            // Sem foto nenhuma não há o que remover — e o botão some em vez de
            // ficar aceso para uma ação que não faria nada.
            if (url != null)
              SJButton(
                label: 'Remover',
                variant: SJButtonVariant.text,
                onPressed: _enviandoCapa ? null : _removerCapa,
              ),
          ],
        ),
      ],
    );
  }

  Widget _dentroDaCapa(SJScheme s, String? url) {
    if (_enviandoCapa) return const Center(child: SJSpinner());
    if (url == null) {
      return Center(
        child: Text(
          'Toque para escolher uma capa',
          style: SJText.caption(color: s.inkFaint),
        ),
      );
    }
    // A URL é assinada e TEMPORÁRIA: pode expirar com a tela aberta. Por isso
    // há saída para o erro — e ela não pode ser uma exceção na pintura, que o
    // Flutter reportaria no console e deixaria um retângulo vazio sem explicação.
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : const Center(child: SJSpinner()),
      errorBuilder: (_, _, _) => Center(
        child: Text(
          'A capa não carregou agora.',
          style: SJText.caption(color: s.inkFaint),
        ),
      ),
    );
  }

  Widget _privacidade(SJScheme s) => Container(
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
