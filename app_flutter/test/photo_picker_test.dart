// O encolhimento que faltava na foto da memória.
//
// O backend corta o upload em 5MB e devolve 413. O avatar e a capa de jornada
// sempre encolheram antes de enviar; a foto da memória ia em resolução cheia,
// nas DUAS telas que a escolhem. Resultado: o caminho mais percorrido do
// produto falhava para a foto comum de celular (3 a 12MB) e só funcionava
// para captura de tela.
//
// O defeito não aparecia em teste nenhum porque ninguém observa os ARGUMENTOS
// de um seletor de imagem — a tela compila, abre a galeria e devolve arquivos
// do mesmo jeito. É isso que este arquivo passa a observar.

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:some_journey/features/photos/photo_picker.dart';

/// Seletor de mentira: anota com que limites foi chamado e devolve o que
/// mandarem devolver.
class _PickerFalso extends ImagePicker {
  _PickerFalso({this.devolve = 0});

  final int devolve;
  double? maxWidthRecebido;
  double? maxHeightRecebido;
  int? qualidadeRecebida;
  int? limiteRecebido;
  int chamadas = 0;

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    chamadas++;
    maxWidthRecebido = maxWidth;
    maxHeightRecebido = maxHeight;
    qualidadeRecebida = imageQuality;
    limiteRecebido = limit;
    return [for (var i = 0; i < devolve; i++) XFile('/tmp/foto$i.jpg')];
  }
}

void main() {
  test('a foto sai encolhida, e não em resolução cheia', () async {
    // A asserção que teria pego o defeito: sem estes três argumentos o
    // `image_picker` devolve o arquivo original da câmera.
    final picker = _PickerFalso(devolve: 1);
    await SJPhoto.escolher(restantes: 3, picker: picker);

    expect(picker.maxWidthRecebido, SJPhoto.maxLado.toDouble());
    expect(picker.maxHeightRecebido, SJPhoto.maxLado.toDouble());
    expect(picker.qualidadeRecebida, SJPhoto.qualidade);
  });

  test('o limite pedido é o que ainda cabe na memória', () async {
    final picker = _PickerFalso();
    await SJPhoto.escolher(restantes: 2, picker: picker);
    expect(picker.limiteRecebido, 2);
  });

  test('sem vaga, a galeria nem abre', () async {
    // Abrir a galeria para depois descartar tudo seria pior que não abrir:
    // a pessoa escolhe fotos e elas somem sem explicação.
    final picker = _PickerFalso(devolve: 3);
    final fotos = await SJPhoto.escolher(restantes: 0, picker: picker);

    expect(fotos, isEmpty);
    expect(picker.chamadas, 0);
  });

  test('galeria que devolve mais que o pedido é cortada aqui', () async {
    // `limit` é uma DICA para a galeria nativa, não uma garantia — algumas
    // implementações ignoram. Sem o corte, a memória passaria do teto e o
    // backend recusaria a última foto com 409, depois de já ter subido as
    // outras.
    final picker = _PickerFalso(devolve: 5);
    final fotos = await SJPhoto.escolher(restantes: 2, picker: picker);
    expect(fotos.length, 2);
  });

  test('o teto por memória é o mesmo que o backend aplica', () {
    // `_MAX_IMAGES` em memory_service.py. Divergir aqui faria a tela oferecer
    // uma vaga que o servidor recusa.
    expect(SJPhoto.maxPorMemoria, 5);
  });
}
