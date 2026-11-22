/// O que já passou pela tela nesta sessão, para abrir de novo SEM esperar.
///
/// A timeline traz cada memória inteira — título, texto, fotos, música. Tocar
/// numa delas abria o detalhe em branco e ia buscar na rede exatamente o que a
/// lista acabara de mostrar: com o servidor nos EUA, meio segundo olhando um
/// esqueleto por um dado que já estava na mão. O mesmo com a jornada que a
/// pessoa abre, fecha e abre de novo.
///
/// Aqui fica a última versão vista de cada coisa, por id. A tela de detalhe
/// nasce com ela e relê por baixo: se algo mudou, troca; se não, ninguém viu
/// espera nenhuma. É "mostre o que tem, confira depois" — nunca "confie no que
/// tem": toda abertura ainda vai ao servidor.
///
/// Quem enche é o cliente da API, no único lugar por onde toda resposta passa
/// (`api.dart`); as telas só leem. E vale só para a sessão em que foi guardado
/// — mesma regra do [SessionCache]: depois de sair, ou de entrar com outra
/// conta, não sobra nada de ninguém.
library;

import '../../api.dart';
import '../../models.dart';

class SeenCache<T> {
  SeenCache({this.capacidade = 300});

  /// Teto de itens. Passou disso, sai o que foi visto há mais tempo — a
  /// memória do aparelho não é lugar para o acervo inteiro.
  final int capacidade;

  final _itens = <String, T>{};
  Object? _dono;

  /// Outra sessão (ou nenhuma) é outra pessoa: o que estava guardado some.
  void _conferirSessao() {
    final sessao = Api.instance.sessionTag;
    if (sessao == _dono) return;
    _itens.clear();
    _dono = sessao;
  }

  T? operator [](String id) {
    _conferirSessao();
    return _dono == null ? null : _itens[id];
  }

  void operator []=(String id, T valor) {
    _conferirSessao();
    if (_dono == null) return;
    // Tira e põe de volta: o mapa guarda a ordem de entrada, e o mais recente
    // tem de ir para o fim da fila de saída.
    _itens.remove(id);
    _itens[id] = valor;
    if (_itens.length > capacidade) _itens.remove(_itens.keys.first);
  }

  void remove(String id) => _itens.remove(id);

  int get length {
    _conferirSessao();
    return _itens.length;
  }
}

/// O percurso real de uma jornada: o mapa e os trechos, que chegam juntos.
typedef PercursoVisto = ({JourneyMap? map, List<JourneyTrack> tracks});

final memoriasVistas = SeenCache<Memory>();
final jornadasVistas = SeenCache<JourneyDetail>(capacidade: 60);
final percursosVistos = SeenCache<PercursoVisto>(capacidade: 30);
