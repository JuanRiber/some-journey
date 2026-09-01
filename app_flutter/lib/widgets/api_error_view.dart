import 'package:flutter/widgets.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/illustrations.dart';

/// O que a tela mostra quando a API não respondeu.
///
/// PORQUÊ: até aqui toda falha virava a mesma coisa na tela — o título da tela
/// ("Não conseguimos abrir seu álbum") e, por baixo, o texto que o servidor
/// mandou. Isso mente de dois jeitos quando o servidor está fora do ar. Diz que
/// o problema é o álbum, quando nenhuma tela do app está funcionando; e mostra
/// "Internal Server Error", ou a página do proxy, para quem só queria ver as
/// próprias memórias.
///
/// Então a notícia vem da natureza da falha, não da tela: se o servidor caiu, o
/// título é que o servidor caiu, em qualquer tela. O título específico da tela
/// (`fallbackTitle`) só sobrevive quando o erro é da requisição — aí ele é a
/// informação mais útil que existe.
class ApiErrorView extends StatelessWidget {
  const ApiErrorView({
    super.key,
    required this.error,
    required this.fallbackTitle,
    this.onRetry,
    this.illustrationSize = 144,
  });

  final ApiError error;

  /// Título da tela, usado só quando a falha é da requisição.
  final String fallbackTitle;

  /// Lado da ilustração. Telas que já carregam um cabeçalho pedem uma arte
  /// menor para o estado não empurrar tudo para fora da dobra.
  final double illustrationSize;

  /// Sem ação de repetir, nenhum botão aparece — oferecer "Tentar de novo" para
  /// um 422 seria convidar a pessoa a repetir o que já não deu certo.
  final VoidCallback? onRetry;

  String get _title => switch (error.kind) {
        ApiFailure.offline => 'Você está sem conexão.',
        ApiFailure.timeout => 'O servidor demorou demais.',
        ApiFailure.unavailable => 'O servidor está fora do ar.',
        ApiFailure.serverError => 'Algo quebrou do nosso lado.',
        ApiFailure.request => fallbackTitle,
      };

  /// Nuvem cortada para o que é do caminho ou do servidor estar ausente;
  /// bússola quebrada para o que quebrou de fato.
  SJIllustrationKind get _kind => switch (error.kind) {
        ApiFailure.offline ||
        ApiFailure.timeout ||
        ApiFailure.unavailable =>
          SJIllustrationKind.offline,
        ApiFailure.serverError || ApiFailure.request => SJIllustrationKind.error,
      };

  @override
  Widget build(BuildContext context) => SJEmptyState(
        illustration: SJIllustration(kind: _kind, size: illustrationSize),
        title: _title,
        body: error.message,
        actionLabel: onRetry == null ? null : 'Tentar de novo',
        onAction: onRetry,
      );
}
