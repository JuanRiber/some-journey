/// As fotos sobem DEPOIS de a memória estar salva — e sem segurar a tela.
///
/// Salvar uma memória com cinco fotos deixava a pessoa parada no formulário
/// enquanto as cinco subiam em fila: com um celular em 4G, dezenas de segundos
/// olhando um botão girar, por uma memória que já estava gravada desde o
/// primeiro instante. O texto, a data e o lugar são uma requisição pequena; as
/// fotos é que pesam.
///
/// Agora a tela fecha quando a MEMÓRIA está salva, e as fotos entram nesta
/// fila. Elas sobem uma de cada vez, na ordem em que foram escolhidas (a
/// primeira é a capa), enquanto a pessoa já está de volta ao atlas. Cada foto
/// que chega avisa as listas pelo `Api.changes` de sempre, e aparece.
///
/// **O que isto custa, dito às claras:** as fotos na fila existem só na
/// memória do app. Se ele for fechado antes de a fila esvaziar, as que
/// faltavam não sobem — a memória fica salva sem elas, e dá para anexá-las de
/// novo editando. Por isso o envio nunca é silencioso: [PhotoUploadsBanner]
/// mostra o andamento em qualquer tela, e uma foto que falha fica na fila de
/// falhas, com "Tentar de novo", em vez de sumir.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../design/components/type_styles.dart';
import '../../design/sj_theme.dart';
import '../../design/tokens.dart';

/// Uma foto esperando a vez, já com os bytes lidos.
class FotoPendente {
  const FotoPendente({
    required this.memoryId,
    required this.bytes,
    required this.name,
    required this.mimeType,
  });

  final String memoryId;
  final List<int> bytes;
  final String name;
  final String mimeType;
}

class PhotoUploads extends ChangeNotifier {
  PhotoUploads._();
  static final PhotoUploads instance = PhotoUploads._();

  final List<FotoPendente> _fila = [];
  final List<FotoPendente> _falhas = [];
  bool _rodando = false;

  /// Quantas fotos esta leva tem ao todo, e quantas já chegaram. Zeram quando
  /// a fila esvazia sem falhas — a próxima memória começa a contar do um.
  int _total = 0;
  int _enviadas = 0;

  /// De quem são as fotos na fila. Sair da conta com fotos por subir não pode
  /// mandá-las para a memória de outra pessoa (nem tentar).
  Object? _dono;

  bool get enviando => _rodando;
  int get total => _total;
  int get enviadas => _enviadas;
  int get falhas => _falhas.length;
  bool get ocioso => !_rodando && _falhas.isEmpty;

  /// Põe fotos na fila e começa a subir, se já não estiver subindo.
  void enqueue(Iterable<FotoPendente> fotos) {
    final novas = fotos.toList();
    if (novas.isEmpty) return;
    _conferirSessao();
    _fila.addAll(novas);
    _total += novas.length;
    notifyListeners();
    if (!_rodando) unawaited(_rodar());
  }

  Future<void> _rodar() async {
    _rodando = true;
    notifyListeners();
    final sessao = _dono;
    while (_fila.isNotEmpty) {
      // A sessão mudou no meio da fila: nada do que sobrou é de quem entrou.
      if (Api.instance.sessionTag != sessao) break;
      final foto = _fila.removeAt(0);
      try {
        await Api.instance
            .addMemoryImage(foto.memoryId, foto.bytes, foto.name, foto.mimeType);
        _enviadas++;
      } catch (_) {
        _falhas.add(foto);
      }
      notifyListeners();
    }
    _rodando = false;
    if (Api.instance.sessionTag != sessao) {
      _esvaziar();
    } else if (_falhas.isEmpty) {
      _total = 0;
      _enviadas = 0;
    }
    notifyListeners();
  }

  /// Tenta de novo as fotos que falharam, na mesma ordem.
  void retry() {
    if (_falhas.isEmpty) return;
    final deNovo = List<FotoPendente>.of(_falhas);
    _falhas.clear();
    _total = _enviadas + _fila.length + deNovo.length;
    _fila.addAll(deNovo);
    notifyListeners();
    if (!_rodando) unawaited(_rodar());
  }

  /// Desiste das que falharam. A memória fica como está; as fotos podem ser
  /// anexadas de novo pela edição.
  void dismissFailures() {
    if (_falhas.isEmpty) return;
    _falhas.clear();
    if (!_rodando) {
      _total = 0;
      _enviadas = 0;
    }
    notifyListeners();
  }

  /// Esquece tudo (sair da conta, excluir a conta).
  void clear() {
    _esvaziar();
    notifyListeners();
  }

  void _esvaziar() {
    _fila.clear();
    _falhas.clear();
    _total = 0;
    _enviadas = 0;
  }

  void _conferirSessao() {
    final sessao = Api.instance.sessionTag;
    if (sessao != _dono) {
      _esvaziar();
      _dono = sessao;
    }
  }
}

/// O andamento do envio, visível em QUALQUER tela.
///
/// Fica por cima do navegador (ver `main.dart`), porque a pessoa não fica na
/// tela onde escolheu as fotos — é esse o ponto. Sem fila e sem falha, não
/// ocupa espaço nenhum.
class PhotoUploadsBanner extends StatelessWidget {
  const PhotoUploadsBanner({super.key, PhotoUploads? uploads}) : _uploads = uploads;

  final PhotoUploads? _uploads;

  @override
  Widget build(BuildContext context) {
    final uploads = _uploads ?? PhotoUploads.instance;
    return AnimatedBuilder(
      animation: uploads,
      builder: (context, _) {
        if (uploads.ocioso) return const SizedBox.shrink();
        final s = SJTheme.of(context);
        final falhou = !uploads.enviando && uploads.falhas > 0;
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(SJSpace.x3),
              child: Material(
                color: s.ink,
                elevation: 6,
                borderRadius: BorderRadius.circular(SJRadius.lg),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SJSpace.x4, vertical: SJSpace.x2,
                  ),
                  child: falhou ? _falha(s, uploads) : _andamento(s, uploads),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _andamento(SJScheme s, PhotoUploads u) {
    // "2 de 5" é a foto que está subindo AGORA, não as que já chegaram.
    final atual = (u.enviadas + u.falhas + 1).clamp(1, u.total);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: s.bg),
        ),
        const SizedBox(width: SJSpace.x3),
        Text(
          u.total == 1 ? 'Enviando a foto…' : 'Enviando fotos… $atual de ${u.total}',
          style: SJText.bodySm(color: s.bg),
        ),
      ],
    );
  }

  Widget _falha(SJScheme s, PhotoUploads u) {
    final n = u.falhas;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            n == 1 ? '1 foto não subiu.' : '$n fotos não subiram.',
            style: SJText.bodySm(color: s.bg),
          ),
        ),
        TextButton(
          onPressed: u.retry,
          child: Text('Tentar de novo', style: SJText.bodySm(color: s.bg)),
        ),
        Semantics(
          button: true,
          label: 'Desistir destas fotos',
          child: IconButton(
            onPressed: u.dismissFailures,
            icon: Icon(Icons.close, size: 16, color: s.bg),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}
