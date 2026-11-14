/// # Lugar — CAMADA DE DOMÍNIO (Dart puro, zero Flutter).
///
/// Como uma memória diz ONDE aconteceu. O backend geocodifica em segundo plano
/// e devolve `place_label` ("Praia de Iracema, Fortaleza"); até isso resolver,
/// o campo vem nulo e a tela precisa dizer alguma coisa. A regra mora aqui para
/// que timeline, detalhe e rastro da jornada digam a MESMA coisa.
library;

/// Coordenada em linguagem de atlas ("23.55° S · 46.63° O") em vez de dois
/// números com sinal. É o mesmo dado — só deixou de parecer log de sistema.
String atlasCoords(double latitude, double longitude) {
  final ns = latitude >= 0 ? 'N' : 'S';
  final eo = longitude >= 0 ? 'L' : 'O';
  return '${latitude.abs().toStringAsFixed(2)}° $ns · '
      '${longitude.abs().toStringAsFixed(2)}° $eo';
}

/// O nome do lugar quando o backend já o resolveu; a coordenada de atlas
/// enquanto não. Rótulo em branco conta como ausente: mostrar "" seria uma
/// linha vazia que parece defeito.
String placeLine(String? placeLabel, double latitude, double longitude) {
  final label = placeLabel?.trim() ?? '';
  return label.isNotEmpty ? label : atlasCoords(latitude, longitude);
}
