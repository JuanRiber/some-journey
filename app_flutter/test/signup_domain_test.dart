// As regras do cadastro em livro, sem montar o livro.
//
// Todo o valor deste arquivo está em uma frase: a validação de um formulário
// de DUAS páginas tem um modo de falhar que o de uma página não tem — o erro
// pode cair numa página que não está à vista. Num celular, a página dos
// obrigatórios fica literalmente virada para baixo enquanto a dos opcionais
// está aberta; apertar "Criar conta" com o e-mail vazio, sem `pageComPrimeiroErro`,
// daria um nada visível. É o teste do fim deste arquivo.
//
// O resto cobre os limites espelhados do backend. Eles são cópia consciente —
// e cópia sem teste é cópia que envelhece calada.

import 'package:flutter_test/flutter_test.dart';
import 'package:some_journey/features/signup/signup_domain.dart';

/// Rascunho válido; cada teste estraga UM campo. Assim a falha aponta o campo,
/// não a montagem.
SignupDraft valido({
  String nome = 'Juan',
  String email = 'juan@email.com',
  String username = 'juan_r',
  String senha = 'uma senha longa',
  String? confirmacao,
  String bio = '',
}) =>
    SignupDraft(
      nome: nome,
      email: email,
      username: username,
      senha: senha,
      confirmacao: confirmacao ?? senha,
      bio: bio,
    );

void main() {
  test('um rascunho completo não acusa nada', () {
    expect(valido().validate(), isEmpty);
  });

  group('aparar', () {
    test('nome, e-mail, @ e bio perdem o espaço das pontas', () {
      final d = SignupDraft(
        nome: '  Juan  ',
        email: ' juan@email.com ',
        username: ' Juan_R ',
        bio: '  o que me move  ',
      );
      expect(d.nome, 'Juan');
      expect(d.email, 'juan@email.com');
      expect(d.bio, 'o que me move');
    });

    test('o @ também é baixado de caixa, como o backend compara', () {
      // `username.normalize` no backend: @Juan e @juan são a MESMA pessoa.
      expect(SignupDraft(username: 'Juan_R').username, 'juan_r');
    });

    test('a senha NÃO é aparada', () {
      // Espaço nas pontas é caractere válido de senha. Comê-lo aqui faria o
      // cadastro passar e o login seguinte falhar com a senha "certa" — o pior
      // tipo de bug, porque a pessoa jura que digitou direito.
      const comEspaco = '  dez caracteres  ';
      final d = SignupDraft(senha: comEspaco, confirmacao: comEspaco);
      expect(d.senha, comEspaco);
      expect(d.validate(), isNot(contains(SignupField.senha)));
    });
  });

  group('obrigatórios', () {
    test('nome vazio é cobrado', () {
      expect(valido(nome: '   ').validate(), contains(SignupField.nome));
    });

    test('nome acima de $nomeMaximo caracteres é cobrado', () {
      expect(
        valido(nome: 'a' * (nomeMaximo + 1)).validate(),
        contains(SignupField.nome),
      );
      expect(valido(nome: 'a' * nomeMaximo).validate(), isEmpty);
    });

    test('e-mail sem arroba, sem domínio ou com espaço é cobrado', () {
      for (final ruim in ['juan', 'juan@', '@email.com', 'juan@email', 'a b@c.com']) {
        expect(
          valido(email: ruim).validate(),
          contains(SignupField.email),
          reason: 'deveria reprovar: "$ruim"',
        );
      }
    });

    test('e-mails legítimos e esquisitos passam', () {
      // A checagem é grosseira DE PROPÓSITO: quem decide é o EmailStr do
      // backend. Reprovar o endereço real de alguém no cadastro é pior que
      // deixar passar um inválido que o servidor recusa na sequência.
      for (final bom in [
        'juan@email.com',
        'juan+viagem@email.com.br',
        'j.ribeiro_2026@sub.dominio.io',
      ]) {
        expect(
          valido(email: bom).validate(),
          isEmpty,
          reason: 'deveria aceitar: "$bom"',
        );
      }
    });

    test('senha com menos de $senhaMinima caracteres é cobrada', () {
      final curta = 'a' * (senhaMinima - 1);
      expect(
        valido(senha: curta, confirmacao: curta).validate(),
        contains(SignupField.senha),
      );
      final exata = 'a' * senhaMinima;
      expect(valido(senha: exata, confirmacao: exata).validate(), isEmpty);
    });

    test('confirmação diferente é cobrada', () {
      expect(
        valido(senha: 'uma senha longa', confirmacao: 'outra senha longa').validate(),
        contains(SignupField.confirmacao),
      );
    });

    test('senha curta não gera DOIS erros pelo mesmo descuido', () {
      // Senha inválida e confirmação em branco é um erro só do ponto de vista
      // de quem digitou. Cobrar os dois faz a página parecer hostil.
      final erros = valido(senha: 'curta', confirmacao: '').validate();
      expect(erros, contains(SignupField.senha));
      expect(erros, isNot(contains(SignupField.confirmacao)));
    });
  });

  group('@username', () {
    test('vazio é cobrado — este é obrigatório no livro', () {
      expect(valido(username: '').validate(), contains(SignupField.username));
    });

    test('abaixo de $usernameMinimo ou acima de $usernameMaximo é cobrado', () {
      expect(valido(username: 'ju').validate(), contains(SignupField.username));
      expect(
        valido(username: 'j${'u' * usernameMaximo}').validate(),
        contains(SignupField.username),
      );
    });

    test('precisa começar por letra e usar só letras, números e _', () {
      for (final ruim in ['1juan', '_juan', 'juan-r', 'juan.r', 'juan r', 'juãn']) {
        expect(
          valido(username: ruim).validate(),
          contains(SignupField.username),
          reason: 'deveria reprovar: "$ruim"',
        );
      }
    });

    test('a caixa alta não reprova — ela é normalizada antes', () {
      expect(valido(username: 'JuanR').validate(), isEmpty);
    });

    test('reservado NÃO é reprovado aqui, e isso é deliberado', () {
      // A lista de reservados vive em app/domain/username.py e muda com as
      // rotas do produto. Uma cópia desatualizada no cliente aprovaria aqui o
      // que o servidor recusa — com o agravante de a pessoa já ter apanhado do
      // formulário. "Reservado" e "em uso" são 422/409, com mensagem pronta.
      expect(valido(username: 'admin').validate(), isEmpty);
    });
  });

  group('opcionais', () {
    test('tudo em branco na página direita passa', () {
      expect(valido(bio: '').validate(), isEmpty);
    });

    test('bio acima de $bioMaxima caracteres é cobrada', () {
      expect(
        valido(bio: 'a' * (bioMaxima + 1)).validate(),
        contains(SignupField.bio),
      );
      expect(valido(bio: 'a' * bioMaxima).validate(), isEmpty);
    });
  });

  group('para qual página o livro vira', () {
    test('sem erro, não vira', () {
      expect(pageComPrimeiroErro(const {}), isNull);
    });

    test('erro de obrigatório leva à página esquerda', () {
      expect(
        pageComPrimeiroErro(valido(email: '').validate()),
        SignupPage.obrigatorios,
      );
    });

    test('erro só na bio leva à página direita', () {
      expect(
        pageComPrimeiroErro(valido(bio: 'a' * (bioMaxima + 1)).validate()),
        SignupPage.opcionais,
      );
    });

    test('com erro nas duas páginas, vence a ordem de leitura do livro', () {
      // Esquerda antes de direita, de cima para baixo: é a ordem em que a
      // pessoa encontraria os erros lendo o livro. Levá-la ao segundo erro
      // primeiro seria fazê-la voltar uma página depois.
      final erros = valido(email: '', bio: 'a' * (bioMaxima + 1)).validate();
      expect(erros.length, 2);
      expect(pageComPrimeiroErro(erros), SignupPage.obrigatorios);
    });

    test('a ordem do enum É a ordem de leitura', () {
      // `pageComPrimeiroErro` percorre `SignupField.values`. Se alguém
      // reordenar o enum por gosto, o livro passa a virar para a página errada
      // sem que nada mais quebre — então a ordem é contrato, e está aqui.
      expect(SignupField.values.map((f) => f.name).toList(), [
        'nome',
        'email',
        'username',
        'senha',
        'confirmacao',
        'bio',
      ]);
      expect(
        SignupField.values.where((f) => f.page == SignupPage.opcionais).toList(),
        [SignupField.bio],
      );
    });
  });
}
