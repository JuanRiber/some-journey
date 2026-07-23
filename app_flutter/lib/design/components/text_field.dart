import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/services.dart' show TextInputType, TextInputAction;
import 'package:flutter/widgets.dart';

import '../sj_theme.dart';
import '../tokens.dart';
import 'overline.dart';
import 'type_styles.dart';

/// # Campo de texto — `SJTextField`
///
/// Anatomia (do design doc): overline mono `accent` como label acima · caixa
/// preenchida em `surfaceAlt` · hairline `line` em repouso · foco = `secondary`
/// a 1.5px · texto de erro em `danger` abaixo. Sem borda dura, sem "floating
/// label" do Material.
///
/// PORQUÊ `CupertinoTextField` e não `TextField`: queremos um campo de edição
/// completo (cursor, seleção, teclado) SEM arrastar a decoração/ink do Material.
/// Zeramos a decoração dele (`decoration: null`) e desenhamos a nossa caixa por
/// fora — assim o look é 100% do sistema e não depende de um ancestral Material.
class SJTextField extends StatefulWidget {
  const SJTextField({
    super.key,
    this.label,
    this.controller,
    this.hint,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
  });

  /// Overline mono acima do campo (ex.: "E-MAIL").
  final String? label;
  final TextEditingController? controller;
  final String? hint;

  /// Quando não-nulo/não-vazio, pinta a borda de `danger` e mostra a mensagem.
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final int? minLines;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Widget à direita dentro da caixa (ex.: ícone de "mostrar senha").
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<SJTextField> createState() => _SJTextFieldState();
}

class _SJTextFieldState extends State<SJTextField> {
  FocusNode? _internal;
  FocusNode get _node => widget.focusNode ?? (_internal ??= FocusNode());
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  void _onFocus() {
    if (_focused != _node.hasFocus) setState(() => _focused = _node.hasFocus);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _internal?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    // Prioridade da borda: erro > foco > repouso. Foco/erro engrossam para 1.5.
    final Color borderColor = hasError
        ? s.danger
        : _focused
        ? s.secondary
        : s.line;
    final double borderWidth = (_focused || hasError) ? 1.5 : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          SJOverline(widget.label!),
          const SizedBox(height: SJSpace.x2),
        ],
        AnimatedContainer(
          duration: SJMotion.fast,
          curve: SJMotion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: SJSpace.x4,
            vertical: SJSpace.x1,
          ),
          decoration: BoxDecoration(
            color: widget.enabled
                ? s.surfaceAlt
                : s.surfaceAlt.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(SJRadius.md),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: CupertinoTextField(
                  controller: widget.controller,
                  focusNode: _node,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  obscureText: widget.obscureText,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  maxLines: widget.obscureText ? 1 : widget.maxLines,
                  minLines: widget.minLines,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  cursorColor: s.secondary,
                  padding: const EdgeInsets.symmetric(vertical: SJSpace.x3),
                  // Zera a caixa do Cupertino: a nossa é o AnimatedContainer.
                  decoration: const BoxDecoration(),
                  placeholder: widget.hint,
                  placeholderStyle: SJText.body(color: s.inkFaint),
                  style: SJText.body(color: s.ink),
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: SJSpace.x2),
                widget.trailing!,
              ],
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: SJSpace.x1),
          Text(widget.errorText!, style: SJText.caption(color: s.danger)),
        ],
      ],
    );
  }
}
