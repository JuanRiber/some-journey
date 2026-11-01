// O cadastro em livro, de ponta a ponta com um servidor falso.
//
// A animação é o que se vê; o que este arquivo guarda é o que está por baixo
// dela. Duas coisas, as duas capazes de machucar de verdade:
//
// 1. **A ORDEM do envio.** `POST /auth/register` só aceita nome, e-mail e
//    senha — @username, bio e avatar moram no Perfil, atrás de autenticação.
//    Então são três passos (cadastra → entra → aplica) e o primeiro é
//    IRREVERSÍVEL. Trocar a ordem, ou repetir o primeiro numa segunda
//    tentativa, significa conta duplicada ou 401 silencioso.
//
// 2. **O erro que cai na página virada.** Num celular o livro mostra uma
//    página por vez: apertar "Criar conta" com o e-mail vazio precisa VIRAR o
//    livro de volta. Sem isso o erro existe, está escrito, e está de costas.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:some_journey/api.dart';
import 'package:some_journey/screens/register.dart';

/// O menor perfil que `Profile.fromJson` aceita — o PATCH devolve o perfil já
/// atualizado, e a tela precisa conseguir decodificá-lo.
const _perfil = {
  'identity': {
    'id': 'u1',
    'name': 'Juan',
    'email': 'juan@email.com',
    'joined_at': '2026-10-12T00:00:00Z',
  },
  'stats': <String, dynamic>{},
};

void main() {
  late http.Client original;
  late List<String> chamadas;
  late List<Map<String, dynamic>> corpos;

  /// Respostas do servidor falso, por rota. Um teste troca só a que lhe
  /// interessa.
  late Map<String, http.Response> respostas;

  setUp(() {
    // Sem isto o `login()` trava no meio do envio: ao guardar a sessão ele
    // chama `SharedPreferences.getInstance()`, cujo canal de plataforma não
    // existe no teste — o Future nunca completa, e o PATCH do perfil, que vem
    // depois, simplesmente não acontece. O sintoma é uma sequência de
    // chamadas que para no login, sem erro nenhum.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    chamadas = [];
    corpos = [];
    respostas = {
      'POST /auth/register': http.Response(
        jsonEncode({'id': 'u1', 'name': 'Juan', 'email': 'juan@email.com'}),
        201,
        headers: {'content-type': 'application/json'},
      ),
      'POST /auth/login': http.Response(
        jsonEncode({'access_token': 'tok'}),
        200,
        headers: {'content-type': 'application/json'},
      ),
      'PATCH /me/profile': http.Response(
        jsonEncode(_perfil),
        200,
        headers: {'content-type': 'application/json'},
      ),
    };
    Api.instance.debugSetToken(null);
    original = Api.instance.swapClient(MockClient((req) async {
      final chave = '${req.method} ${req.url.path}';
      chamadas.add(chave);
      if (req.body.isNotEmpty) {
        final decodificado = jsonDecode(req.body);
        if (decodificado is Map<String, dynamic>) corpos.add(decodificado);
      }
      return respostas[chave] ??
          http.Response(jsonEncode({'detail': 'rota não prevista: $chave'}), 404,
              headers: {'content-type': 'application/json'});
    }));
  });

  tearDown(() {
    Api.instance.swapClient(original);
    Api.instance.debugSetToken(null);
  });

  /// Abre o livro como o app abre: rota translúcida, empilhada sobre a tela de
  /// baixo, devolvendo o e-mail ao fechar.
  Future<List<Object?>> abrir(WidgetTester tester, {required Size tela}) async {
    // A janela do teste decide a encenação: >= 720 de largura abre folha
    // dupla, abaixo disso o livro mostra uma página por vez. A altura é
    // generosa para que as páginas caibam sem rolagem — o que este arquivo
    // guarda é o envio e a virada, não a barra de rolagem.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = tela;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final devolvido = <Object?>[];
    await tester.pumpWidget(MaterialApp(
      onGenerateRoute: (settings) {
        if (settings.name == '/register') {
          return PageRouteBuilder<String?>(
            settings: settings,
            opaque: false,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => const RegisterScreen(),
          );
        }
        return MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  devolvido.add(
                    await Navigator.of(context).pushNamed<Object?>('/register'),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        );
      },
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return devolvido;
  }

  /// Toca um rótulo, trazendo-o para dentro da página antes.
  ///
  /// O livro tem proporção fixa (uma folha dupla é mais larga que alta), então
  /// a página rola por dentro e o botão do rodapé fica abaixo da dobra com
  /// frequência — e um `tap` que erra o alvo não falha, só avisa.
  ///
  /// `ensureVisible` aqui também é um teste em si: ele é o MESMO caminho que o
  /// foco do teclado dispara sozinho ao entrar num campo. Enquanto a folha em
  /// repouso carregava matriz de perspectiva, esta chamada não convergia e o
  /// teste travava — era o sintoma de a página congelar no aparelho.
  Future<void> tocar(WidgetTester tester, String rotulo) async {
    await tester.ensureVisible(find.text(rotulo));
    await tester.pumpAndSettle();
    await tester.tap(find.text(rotulo));
    await tester.pumpAndSettle();
  }

  /// Assina o livro e espera o envio inteiro.
  ///
  /// Aqui NÃO cabe `pumpAndSettle`: enquanto envia, o `SJButton` troca o
  /// rótulo por um `SJSpinner`, que gira para sempre — assentar nunca
  /// aconteceria, e o teste morreria de timeout em vez de falhar por mérito.
  /// Então o tempo passa em fatias, com folga para os três passos da rede e
  /// para o livro fechar (`SJMotion.ceremony`).
  Future<void> assinar(WidgetTester tester) async {
    await tester.ensureVisible(find.text('CRIAR CONTA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CRIAR CONTA'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> preencher(
    WidgetTester tester, {
    String nome = 'Juan',
    String email = 'juan@email.com',
    String username = 'juan_r',
    String senha = 'uma senha longa',
    String? confirmacao,
  }) async {
    // `SJTextField` embrulha um `CupertinoTextField`, então quem existe na
    // árvore é o `EditableText` — e cada campo é achado pela sua overline, que
    // o componente sobe para CAIXA ALTA.
    Future<void> escrever(String label, String valor) async {
      final campo = find.descendant(
        of: find.ancestor(
          of: find.text(label.toUpperCase()),
          matching: find.byType(Column),
        ).first,
        matching: find.byType(EditableText),
      );
      await tester.enterText(campo.first, valor);
      await tester.pump();
    }

    await escrever('Nome', nome);
    await escrever('E-mail', email);
    await escrever('Nome de usuário', username);
    await escrever('Senha', senha);
    await escrever('Confirmar senha', confirmacao ?? senha);
  }

  // Uma tela de notebook: as duas páginas lado a lado.
  const telaLarga = Size(1100, 1000);
  // 390x844 — um iPhone em pé, abaixo do limite de folha dupla.
  const telaEstreita = Size(390, 844);

  group('folha dupla (tela larga)', () {
    testWidgets('o livro abre com as duas páginas à vista', (tester) async {
      await abrir(tester, tela: telaLarga);
      expect(find.text('O essencial'), findsOneWidget);
      expect(find.text('Como aparecer'), findsOneWidget);
      // A promessa da página direita precisa estar ESCRITA nela: é o que faz
      // alguém topar preencher.
      expect(
        find.text('Nada aqui é obrigatório — dá para fazer depois, no Perfil.'),
        findsOneWidget,
      );
    });

    testWidgets('nada é enviado enquanto falta um obrigatório', (tester) async {
      await abrir(tester, tela: telaLarga);
      await preencher(tester, email: '');
      await tocar(tester, 'CRIAR CONTA');

      expect(chamadas, isEmpty, reason: 'o servidor não deveria ter sido tocado');
      expect(find.text('Esse e-mail não parece completo.'), findsNothing);
      expect(find.text('Informe um e-mail.'), findsOneWidget);
    });

    testWidgets('o caminho feliz: cadastra, entra, aplica o perfil e sai',
        (tester) async {
      final devolvido = await abrir(tester, tela: telaLarga);
      await preencher(tester);
      await assinar(tester);

      // A ordem É o contrato: sem o login no meio, o PATCH volta 401.
      expect(chamadas, [
        'POST /auth/register',
        'POST /auth/login',
        'PATCH /me/profile',
      ]);
      // Sem foto escolhida, nenhuma viagem para o avatar.
      expect(chamadas, isNot(contains('POST /me/avatar')));

      // O cadastro manda só o que a rota aceita; o @ vai no PATCH.
      expect(corpos.first.keys.toSet(), {'name', 'email', 'password'});
      expect(corpos.last['username'], 'juan_r');
      // Bio em branco não vira string vazia no corpo — não mexer e limpar são
      // coisas diferentes para o backend.
      expect(corpos.last.containsKey('bio'), isFalse);

      // O livro fecha e devolve à porta: a sessão é de quem entrar por ela.
      expect(Api.instance.hasToken, isFalse);
      expect(devolvido, ['juan@email.com']);
      expect(find.text('O essencial'), findsNothing);
    });

    testWidgets('sair pelo lado depois de criar a conta não deixa sessão viva',
        (tester) async {
      // A falha acontece DEPOIS do cadastro, então existe token em memória. Se
      // a pessoa desistir e sair pelo "Já tenho conta", ela veria a tela de
      // login estando autenticada — e o próximo boot a jogaria para dentro do
      // app sem ela ter entrado. Fechar o livro apaga a sessão, sempre.
      respostas['PATCH /me/profile'] = http.Response(
        jsonEncode({'detail': 'Esse nome de usuário já está em uso.'}),
        409,
        headers: {'content-type': 'application/json'},
      );

      await abrir(tester, tela: telaLarga);
      await preencher(tester);
      await assinar(tester);
      expect(Api.instance.hasToken, isTrue, reason: 'o envio chegou a entrar');

      await tester.tap(find.text('Já tenho conta'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(Api.instance.hasToken, isFalse);
    });

    testWidgets('o @ já em uso não cadastra a conta duas vezes', (tester) async {
      respostas['PATCH /me/profile'] = http.Response(
        jsonEncode({'detail': 'Esse nome de usuário já está em uso.'}),
        409,
        headers: {'content-type': 'application/json'},
      );

      await abrir(tester, tela: telaLarga);
      await preencher(tester);
      await assinar(tester);

      expect(find.text('A conta já foi criada — falta só acertar o @.'), findsOneWidget);

      // Segunda tentativa: o passo irreversível NÃO se repete.
      chamadas.clear();
      respostas['PATCH /me/profile'] = http.Response(
        jsonEncode(_perfil),
        200,
        headers: {'content-type': 'application/json'},
      );
      await tocar(tester, 'CRIAR CONTA');

      expect(chamadas, isNot(contains('POST /auth/register')));
      expect(chamadas, ['POST /auth/login', 'PATCH /me/profile']);
    });
  });

  group('folha única (celular em pé)', () {
    testWidgets('uma página por vez, e a virada troca qual está à vista',
        (tester) async {
      final handle = tester.ensureSemantics();
      await abrir(tester, tela: telaEstreita);

      // A página de baixo está montada o tempo todo — é justamente o que a de
      // cima cobre. Quem responde "qual está à vista" é a semântica: um livro
      // que mostra uma página por vez não pode anunciar duas.
      expect(find.text('O essencial'), findsOneWidget);
      expect(find.bySemanticsLabel('Como aparecer'), findsNothing);

      await tocar(tester, 'VIRAR A PÁGINA');

      expect(find.text('Como aparecer'), findsOneWidget);
      expect(find.text('O essencial'), findsNothing);
      expect(find.bySemanticsLabel('Como aparecer'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('o recado do @ recusado vai junto com o livro de volta',
        (tester) async {
      // Mostrar o erro e mostrá-lo ONDE a pessoa está olhando são coisas
      // diferentes num livro de uma página por vez. O @ só o servidor julga
      // (reservado, em uso), e o campo dele está na esquerda — então o recado
      // precisa viajar com a virada, senão fica na página que acabou de sair.
      respostas['PATCH /me/profile'] = http.Response(
        jsonEncode({'detail': 'Esse nome de usuário já está em uso.'}),
        409,
        headers: {'content-type': 'application/json'},
      );

      await abrir(tester, tela: telaEstreita);
      await preencher(tester);
      await tocar(tester, 'VIRAR A PÁGINA');
      await assinar(tester);

      expect(find.text('O essencial'), findsOneWidget);
      expect(find.text('A conta já foi criada — falta só acertar o @.'), findsOneWidget);
      expect(find.text('Esse nome de usuário já está em uso.'), findsOneWidget);
    });

    testWidgets('o erro na página virada traz o livro de volta', (tester) async {
      // O defeito que isto impede: o erro aparece, está correto, e está de
      // costas para quem precisa lê-lo.
      await abrir(tester, tela: telaEstreita);
      await preencher(tester, email: '');
      await tocar(tester, 'VIRAR A PÁGINA');
      expect(find.text('O essencial'), findsNothing);

      await tocar(tester, 'CRIAR CONTA');

      expect(chamadas, isEmpty);
      expect(find.text('O essencial'), findsOneWidget);
      expect(find.text('Informe um e-mail.'), findsOneWidget);
    });
  });
}
