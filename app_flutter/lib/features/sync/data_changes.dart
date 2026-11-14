import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../api.dart';

/// Para telas que mostram dados do servidor: chama [dadosMudaram] quando este
/// app grava algo — e espera um instante antes, porque uma ação costuma ser
/// uma rajada (a memória e depois cada foto dela): uma releitura só no fim, em
/// vez de uma por pedido.
///
/// A releitura é SILENCIOSA: quem usa já mantém o conteúdo na tela enquanto a
/// nova versão chega, então a pessoa vê a mudança aparecer, não um esqueleto.
mixin AtualizaQuandoMuda<T extends StatefulWidget> on State<T> {
  Timer? _espera;

  /// O que fazer quando os dados ficaram velhos (em geral, reler).
  void dadosMudaram();

  @override
  void initState() {
    super.initState();
    Api.instance.changes.addListener(_mudou);
  }

  void _mudou() {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 350), () {
      if (mounted) dadosMudaram();
    });
  }

  @override
  void dispose() {
    _espera?.cancel();
    Api.instance.changes.removeListener(_mudou);
    super.dispose();
  }
}
