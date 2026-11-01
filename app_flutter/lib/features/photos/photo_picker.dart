import 'package:image_picker/image_picker.dart';

/// # Escolha de fotos da memória — com o encolhimento que faltava
///
/// PORQUÊ este arquivo existe: o backend corta o upload em 5MB
/// (`MAX_IMAGE_BYTES`) e devolve 413. Uma foto que sai da câmera de um celular
/// atual tem de 3 a 12MB — ou seja, o caminho MAIS percorrido do produto,
/// anexar foto a uma memória, falhava justamente para a foto comum. Só subia
/// captura de tela e imagem já comprimida pela web.
///
/// O avatar e a capa de jornada sempre encolheram antes de enviar; a foto da
/// memória era a única que ia em resolução cheia, e nas DUAS telas que a
/// escolhem. Por isso o ajuste mora aqui e não em cada uma: duas cópias de um
/// limite é um limite que vai ser corrigido pela metade.
///
/// Os números: 2048px no maior lado e qualidade 85 deixam a foto tipicamente
/// entre 400KB e 1,2MB — folga larga sobre o teto, e ainda mais pixels do que
/// qualquer tela de celular mostra, inclusive no visualizador em tela cheia.
/// O avatar usa 1024 porque é exibido num círculo pequeno; aqui seria perda
/// visível.
abstract final class SJPhoto {
  /// Maior lado, em pixels, depois do encolhimento.
  static const int maxLado = 2048;

  /// Qualidade JPEG. 85 é o joelho da curva: abaixo disso aparece artefato em
  /// céu e pele, acima o arquivo cresce sem diferença perceptível.
  static const int qualidade = 85;

  /// Teto por memória — o mesmo que o backend aplica (`_MAX_IMAGES`).
  static const int maxPorMemoria = 5;

  /// Abre a galeria para escolher até [restantes] fotos, já encolhidas.
  static Future<List<XFile>> escolher({
    required int restantes,
    ImagePicker? picker,
  }) async {
    if (restantes <= 0) return const [];
    final escolhidas = await (picker ?? ImagePicker()).pickMultiImage(
      limit: restantes,
      maxWidth: maxLado.toDouble(),
      maxHeight: maxLado.toDouble(),
      imageQuality: qualidade,
    );
    // O `limit` é uma dica para a galeria nativa, não uma garantia: algumas
    // implementações devolvem mais. O corte é nosso.
    return escolhidas.take(restantes).toList();
  }
}
