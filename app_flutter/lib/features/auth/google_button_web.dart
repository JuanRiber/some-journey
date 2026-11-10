import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// Na web o Google NÃO permite que o fluxo saia de um botão nosso — é preciso
/// renderizar o botão deles, que carrega a marca e o consentimento. Por isso
/// este é o único lugar do app onde um componente de fora desenha na tela.
Widget? botaoRenderizadoPeloGoogle() => web.renderButton();
