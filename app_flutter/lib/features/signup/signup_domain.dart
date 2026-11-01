/// # Cadastro em livro — as regras do formulário (domínio puro)
///
/// PORQUÊ este arquivo existe separado da tela: o cadastro ficou com DOIS lados
/// (obrigatórios à esquerda, opcionais à direita) e uma animação no meio. Se a
/// validação morasse dentro do widget, cada pergunta simples — "esse campo é
/// obrigatório?", "em que página está o erro?" — só teria resposta montando a
/// árvore inteira e esperando o livro abrir. Aqui é Dart puro: sem Flutter, sem
/// relógio, sem rede.
///
/// Os limites abaixo ESPELHAM o backend de propósito, cada um com a sua fonte
/// anotada. Validar no cliente não é desconfiança do servidor — é não gastar
/// uma viagem de rede para dizer que a senha tem oito caracteres. A autoridade
/// final continua lá: o que esta camada NÃO sabe (se o e-mail já tem conta, se
/// o @ está reservado ou em uso) é deixado explicitamente para o 409/422, que
/// já volta com a mensagem pronta em pt-BR.
library;

/// Os dois lados do livro aberto.
///
/// Não é decoração: é o que o formulário promete ao usuário. À esquerda fica o
/// que a conta EXIGE para existir; à direita, só o que enfeita o perfil. A
/// separação é a razão de alguém topar preencher — dá para fechar o livro na
/// metade e ainda ter uma conta.
enum SignupPage {
  /// Página esquerda — sem isto não há conta.
  obrigatorios,

  /// Página direita — tudo aqui pode ficar em branco e ser feito depois.
  opcionais,
}

/// Cada campo do cadastro, já sabendo em que página mora.
enum SignupField {
  nome(SignupPage.obrigatorios),
  email(SignupPage.obrigatorios),
  username(SignupPage.obrigatorios),
  senha(SignupPage.obrigatorios),
  confirmacao(SignupPage.obrigatorios),
  bio(SignupPage.opcionais);

  const SignupField(this.page);

  /// Em qual lado do livro este campo é desenhado — e, portanto, para onde o
  /// livro precisa virar quando o erro é dele.
  final SignupPage page;
}

// --- Limites espelhados do backend ------------------------------------------
// Cada constante aponta para quem manda de verdade. Mudou lá, muda aqui.

/// `app/schemas/auth.py`: `password: str = Field(min_length=10, max_length=128)`.
const int senhaMinima = 10;
const int senhaMaxima = 128;

/// `app/schemas/auth.py`: `name: str = Field(min_length=1, max_length=120)`.
const int nomeMaximo = 120;

/// `app/domain/username.py`: `MIN_LENGTH`/`MAX_LENGTH`.
const int usernameMinimo = 3;
const int usernameMaximo = 30;

/// `app/schemas/profile.py`: `bio: str | None = Field(max_length=160)`.
const int bioMaxima = 160;

/// Mesmo conjunto do `_PATTERN` de `app/domain/username.py`: começa por letra,
/// segue com letras, números ou `_`. Sem ponto e sem hífen de propósito — menos
/// ambiguidade visual numa @menção.
final RegExp _formatoUsername = RegExp(r'^[a-z][a-z0-9_]{2,29}$');

/// Checagem DELIBERADAMENTE grosseira de e-mail: tem exatamente um arroba, não
/// tem espaço, e o domínio tem um ponto com algo depois.
///
/// Não tentamos reimplementar a RFC 5322 — toda regex "completa" de e-mail que
/// cabe numa linha reprova endereços válidos, e reprovar o endereço real de
/// alguém no cadastro é pior do que deixar passar um inválido que o servidor
/// recusa em seguida. Quem decide é o `EmailStr` do backend.
final RegExp _formatoEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

/// O que o usuário escreveu, já aparado. Imutável: a tela monta um novo a cada
/// validação em vez de mutar o que foi validado.
class SignupDraft {
  SignupDraft({
    String nome = '',
    String email = '',
    String username = '',
    this.senha = '',
    this.confirmacao = '',
    String bio = '',
    this.temFoto = false,
  })  : nome = nome.trim(),
        email = email.trim(),
        // O @ é guardado em caixa baixa porque é assim que o backend compara:
        // `@Juan` e `@juan` são a mesma pessoa (`username.normalize`).
        username = username.trim().toLowerCase(),
        bio = bio.trim();

  final String nome;
  final String email;
  final String username;

  /// Senhas NÃO são aparadas: espaço nas pontas é caractere válido, e comer o
  /// espaço aqui faria o login seguinte falhar com a senha "certa".
  final String senha;
  final String confirmacao;

  final String bio;

  /// Se uma foto já foi escolhida (os bytes ficam na tela; aqui só o fato).
  final bool temFoto;

  /// Erros por campo, prontos para aparecer embaixo de cada um. Mapa vazio =
  /// pode enviar.
  ///
  /// Mensagens em pt-BR e na segunda pessoa, como o resto do app: o campo
  /// conversa com quem digitou, não reporta um código.
  Map<SignupField, String> validate() {
    final erros = <SignupField, String>{};

    if (nome.isEmpty) {
      erros[SignupField.nome] = 'Como quer ser chamado?';
    } else if (nome.length > nomeMaximo) {
      erros[SignupField.nome] = 'No máximo $nomeMaximo caracteres.';
    }

    if (email.isEmpty) {
      erros[SignupField.email] = 'Informe um e-mail.';
    } else if (!_formatoEmail.hasMatch(email)) {
      erros[SignupField.email] = 'Esse e-mail não parece completo.';
    }

    final erroUsername = _validaUsername(username);
    if (erroUsername != null) erros[SignupField.username] = erroUsername;

    if (senha.isEmpty) {
      erros[SignupField.senha] = 'Escolha uma senha.';
    } else if (senha.length < senhaMinima) {
      erros[SignupField.senha] = 'Pelo menos $senhaMinima caracteres.';
    } else if (senha.length > senhaMaxima) {
      erros[SignupField.senha] = 'No máximo $senhaMaxima caracteres.';
    }

    // A confirmação só é cobrada depois que a senha em si está de pé — senão o
    // usuário leva dois erros pelo mesmo descuido.
    if (!erros.containsKey(SignupField.senha)) {
      if (confirmacao.isEmpty) {
        erros[SignupField.confirmacao] = 'Repita a senha.';
      } else if (confirmacao != senha) {
        erros[SignupField.confirmacao] = 'As duas senhas não são iguais.';
      }
    }

    if (bio.length > bioMaxima) {
      erros[SignupField.bio] = 'No máximo $bioMaxima caracteres.';
    }

    return erros;
  }

  /// Formato do @, espelhando `app/domain/username.py`.
  ///
  /// A lista de RESERVADOS não é copiada para cá de propósito: ela muda com as
  /// rotas do produto, e uma cópia desatualizada no cliente é pior que nenhuma
  /// — aprovaria aqui o que o servidor recusa, com a diferença de que o usuário
  /// já teria apanhado do formulário. "Reservado" e "em uso" são 422/409, e as
  /// duas mensagens vêm prontas de lá.
  static String? _validaUsername(String username) {
    if (username.isEmpty) return 'Escolha um nome de usuário.';
    if (username.length < usernameMinimo) {
      return 'Pelo menos $usernameMinimo caracteres.';
    }
    if (username.length > usernameMaximo) {
      return 'No máximo $usernameMaximo caracteres.';
    }
    if (!_formatoUsername.hasMatch(username)) {
      return 'Use letras, números e _ , começando por uma letra.';
    }
    return null;
  }
}

/// Em qual página o livro precisa estar para MOSTRAR o primeiro erro.
///
/// Existe porque o erro silencioso é o pior defeito de um formulário de duas
/// páginas: num livro estreito (celular), metade dos campos está literalmente
/// virada para baixo. Sem isto, apertar "Criar conta" com o e-mail vazio daria
/// um nada visível.
///
/// A ordem de `SignupField` é a ordem de leitura do livro — esquerda de cima
/// para baixo, depois direita —, então o primeiro erro nessa ordem é o primeiro
/// que a pessoa encontraria lendo.
SignupPage? pageComPrimeiroErro(Map<SignupField, String> erros) {
  if (erros.isEmpty) return null;
  for (final campo in SignupField.values) {
    if (erros.containsKey(campo)) return campo.page;
  }
  return null;
}
