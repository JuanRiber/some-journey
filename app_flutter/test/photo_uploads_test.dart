// As fotos sobem depois de a memória estar salva, sem segurar a tela.
//
// O risco de tirar uma espera da frente da pessoa é o trabalho passar a
// acontecer onde ela não vê — e falhar onde ela não vê. Por isso o que este
// arquivo prende, além de "sobe": a ORDEM (a primeira foto é a capa), que uma
// falha não some nem trava as outras, que dá para tentar de novo, e que a
// faixa de andamento diz a verdade.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/features/photos/photo_uploads.dart';

FotoPendente _foto(String memoria, String nome) => FotoPendente(
      memoryId: memoria,
      bytes: const [0xFF, 0xD8, 0xFF],
      name: nome,
      mimeType: 'image/jpeg',
    );

void main() {
  final fila = PhotoUploads.instance;
  late http.Client anterior;

  /// Os arquivos que chegaram ao servidor, na ordem: "memória/nome".
  late List<String> chegaram;

  /// Nomes de arquivo que o servidor recusa.
  late Set<String> recusa;

  /// Com isto, cada envio espera o teste liberar.
  Completer<void>? portao;

  setUp(() {
    chegaram = [];
    recusa = {};
    portao = null;
    Api.instance.debugSetToken('sessao-de-teste');
    fila.clear();
    anterior = Api.instance.swapClient(MockClient.streaming((req, corpo) async {
      final bytes = await corpo.toBytes();
      final texto = String.fromCharCodes(bytes);
      final nome = RegExp(r'filename="([^"]+)"').firstMatch(texto)!.group(1)!;
      final memoria = req.url.pathSegments[1];
      await portao?.future;
      if (recusa.contains(nome)) {
        return http.StreamedResponse(Stream.value('{"detail":"caiu"}'.codeUnits), 503);
      }
      chegaram.add('$memoria/$nome');
      return http.StreamedResponse(Stream.value('{}'.codeUnits), 200,
          headers: {'content-type': 'application/json'});
    }));
  });

  tearDown(() {
    fila.clear();
    Api.instance.swapClient(anterior);
    Api.instance.debugSetToken(null);
  });

  Future<void> assentar() => Future<void>.delayed(const Duration(milliseconds: 40));

  group('a fila', () {
    test('sobe uma de cada vez, na ordem em que foram escolhidas', () async {
      fila.enqueue([_foto('m1', 'a.jpg'), _foto('m1', 'b.jpg'), _foto('m1', 'c.jpg')]);
      await assentar();

      expect(chegaram, ['m1/a.jpg', 'm1/b.jpg', 'm1/c.jpg'],
          reason: 'a primeira foto é a capa: fora de ordem, a capa muda');
      expect(fila.ocioso, isTrue);
      expect(fila.total, 0, reason: 'fila limpa: a próxima memória conta do um');
    });

    test('enfileirar não espera o envio', () async {
      portao = Completer<void>();

      fila.enqueue([_foto('m1', 'a.jpg')]);

      // Voltou na hora, com o envio ainda no ar: é isto que solta a tela.
      expect(chegaram, isEmpty);
      expect(fila.enviando, isTrue);

      portao!.complete();
      await assentar();
      expect(chegaram, ['m1/a.jpg']);
    });

    test('fotos de outra memória entram atrás, sem furar a fila', () async {
      portao = Completer<void>();
      fila.enqueue([_foto('m1', 'a.jpg'), _foto('m1', 'b.jpg')]);
      fila.enqueue([_foto('m2', 'x.jpg')]);
      expect(fila.total, 3);

      portao!.complete();
      await assentar();

      expect(chegaram, ['m1/a.jpg', 'm1/b.jpg', 'm2/x.jpg']);
    });

    test('uma foto que falha não some nem trava as outras', () async {
      recusa = {'b.jpg'};

      fila.enqueue([_foto('m1', 'a.jpg'), _foto('m1', 'b.jpg'), _foto('m1', 'c.jpg')]);
      await assentar();

      expect(chegaram, ['m1/a.jpg', 'm1/c.jpg']);
      expect(fila.falhas, 1);
      expect(fila.ocioso, isFalse, reason: 'há uma falha à espera de decisão');
      expect((fila.enviadas, fila.total), (2, 3));
    });

    test('tentar de novo sobe só a que faltava', () async {
      recusa = {'b.jpg'};
      fila.enqueue([_foto('m1', 'a.jpg'), _foto('m1', 'b.jpg')]);
      await assentar();

      recusa = {};
      fila.retry();
      await assentar();

      expect(chegaram, ['m1/a.jpg', 'm1/b.jpg']);
      expect(fila.falhas, 0);
      expect(fila.ocioso, isTrue);
    });

    test('desistir das que falharam limpa a faixa', () async {
      recusa = {'a.jpg'};
      fila.enqueue([_foto('m1', 'a.jpg')]);
      await assentar();

      fila.dismissFailures();

      expect(fila.ocioso, isTrue);
      expect(fila.total, 0);
    });

    test('sair da conta abandona o que faltava subir', () async {
      portao = Completer<void>();
      fila.enqueue([_foto('m1', 'a.jpg'), _foto('m1', 'b.jpg')]);

      await Api.instance.logout();
      portao!.complete();
      await assentar();

      expect(chegaram, ['m1/a.jpg'],
          reason: 'a que já estava no ar termina; a seguinte não é de quem entrar');
      expect(fila.ocioso, isTrue);
      expect(fila.total, 0);
    });

    test('lista vazia não mexe em nada', () {
      fila.enqueue(const []);
      expect(fila.ocioso, isTrue);
    });
  });

  group('a faixa de andamento', () {
    Future<void> mostrar(WidgetTester tester) => tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: PhotoUploadsBanner())),
        );

    testWidgets('sem fila, não ocupa espaço nenhum', (tester) async {
      await mostrar(tester);
      expect(find.byType(Material).evaluate().length, 1, reason: 'só o do Scaffold');
      expect(find.textContaining('Enviando'), findsNothing);
    });

    testWidgets('diz qual foto está subindo, e some quando acaba', (tester) async {
      portao = Completer<void>();
      await mostrar(tester);

      fila.enqueue([_foto('m1', 'a.jpg'), _foto('m1', 'b.jpg'), _foto('m1', 'c.jpg')]);
      await tester.pump();
      expect(find.text('Enviando fotos… 1 de 3'), findsOneWidget);

      portao!.complete();
      await tester.runAsync(assentar);
      await tester.pump();

      expect(find.textContaining('Enviando'), findsNothing);
    });

    testWidgets('uma foto só não conta "1 de 1"', (tester) async {
      portao = Completer<void>();
      await mostrar(tester);

      fila.enqueue([_foto('m1', 'a.jpg')]);
      await tester.pump();

      expect(find.text('Enviando a foto…'), findsOneWidget);
      portao!.complete();
      await tester.runAsync(assentar);
    });

    testWidgets('falha fica à vista, com saída', (tester) async {
      recusa = {'a.jpg', 'b.jpg'};
      await mostrar(tester);

      fila.enqueue([_foto('m1', 'a.jpg'), _foto('m1', 'b.jpg')]);
      await tester.runAsync(assentar);
      await tester.pump();

      expect(find.text('2 fotos não subiram.'), findsOneWidget);

      recusa = {};
      await tester.tap(find.text('Tentar de novo'));
      await tester.runAsync(assentar);
      await tester.pump();

      expect(chegaram, ['m1/a.jpg', 'm1/b.jpg']);
      expect(find.textContaining('não subiram'), findsNothing);
    });
  });
}
