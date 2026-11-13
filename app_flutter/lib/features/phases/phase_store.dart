import 'package:flutter/foundation.dart';

import '../../api.dart';
import 'phase_domain.dart';

/// As fases da pessoa, compartilhadas entre as telas.
///
/// **Por que existe:** a timeline e o atlas são abas — não recarregam quando a
/// pessoa volta delas. Sem um lugar comum, quem cria uma fase e volta para a
/// timeline não a encontraria na lente até puxar para atualizar, e quem apaga
/// a fase pela qual a lente está olhando continuaria filtrando por um id que
/// devolve 404. Com o notificador, as telas que dependem das fases mudam no
/// mesmo instante em que elas mudam.
///
/// Não é cache de verdade: toda tela que abre pede um [refresh]. A lista é
/// curta (quantos capítulos tem uma vida?) e ler de novo custa menos que
/// decidir quando ela envelheceu.
class PhaseStore extends ValueNotifier<List<LifePhase>> {
  PhaseStore._() : super(const []);

  static final PhaseStore instance = PhaseStore._();

  /// Relê do servidor e devolve o erro, se houve — sem levantar.
  ///
  /// Fase é opcional, e falhar ao buscá-las não pode derrubar a timeline nem
  /// o atlas: quem só quer ver as memórias continua vendo. Por isso a falha
  /// mantém a última lista conhecida, e só a tela de fases, que existe para
  /// elas, olha o erro devolvido.
  ///
  /// A exceção é a sessão expirada: aí a lista pode ser de OUTRA conta (troca
  /// de usuário no mesmo aparelho), e mostrá-la seria vazar capítulos alheios.
  Future<ApiError?> refresh() async {
    try {
      value = await Api.instance.listPhases();
      return null;
    } on ApiError catch (e) {
      if (e.isUnauthorized) clear();
      return e;
    }
  }

  /// Esquece as fases (saída da conta).
  void clear() => value = const [];

  /// Põe uma lista sem passar pela rede (testes).
  @visibleForTesting
  void debugSet(List<LifePhase> phases) => value = phases;
}
