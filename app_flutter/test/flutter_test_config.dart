// Configuração comum a TODOS os arquivos de teste (o `flutter test` a carrega
// sozinho, pelo nome).
//
// Existe por causa do cofre da sessão. Fora da web o app guarda os tokens no
// Keychain/Keystore, por um plugin; num teste não há plataforma do outro lado
// do canal, e a chamada não falha — ela nunca responde. Um `await` nela dentro
// de um `testWidgets` (relógio falso) fica pendurado para sempre: o login
// "não termina" e o teste falha longe da causa, numa asserção qualquer.
//
// Cada teste começa então com um cofre de mentira, VAZIO. Vazio de propósito:
// os testes que simulam sessão salva continuam declarando-a no
// `shared_preferences`, que é onde a versão anterior a guardava — e de quebra
// exercitam a migração para o cofre a cada execução.

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/features/hero/hero_scene.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    // A cena do login anda para sempre. Com o relógio falso do `testWidgets`,
    // um `pumpAndSettle` em qualquer tela que a tenha por baixo esperaria por
    // um repouso que não vem. Aqui ela fica num quadro só; quem testa o
    // movimento (`hero_scene_test.dart`) liga de volta.
    HeroScene.autoplay = false;
  });
  await testMain();
}
