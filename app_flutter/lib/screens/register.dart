import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import '../features/signup/signup_domain.dart';

/// # Criar conta — o primeiro capítulo, em forma de livro.
///
/// **Por que existe:** para começar a registrar a própria vida é preciso um
/// lugar só seu. O produto inteiro se chama "caderno de viagens elegante, não
/// um CRUD" — o cadastro é a primeira chance de provar isso, e era justamente
/// onde parecia um formulário qualquer.
///
/// **O que o usuário sente:** que abriu um livro. A capa se levanta sobre a
/// tela de login (que continua ali atrás, escurecida), e as duas páginas
/// dividem o trabalho de um jeito que se entende sem ler: **à esquerda o que a
/// conta exige, à direita o que é seu gosto**. Fechar o livro no fim devolve à
/// porta de entrada.
///
/// **Ação principal:** criar conta — assinada no fim do livro, como se assina
/// um documento.
///
/// **Atrito:** nada da página direita é obrigatório, e isso está escrito nela.
/// Erro volta inline e o livro VIRA sozinho para a página onde ele está — num
/// celular, metade dos campos está literalmente virada para baixo, e um erro
/// invisível seria pior que nenhum.
///
/// ## O caminho dos dados (e por que ele tem três passos)
///
/// `POST /auth/register` só aceita nome, e-mail e senha. O @username, a bio e o
/// avatar vivem no Perfil, atrás de autenticação. Então o envio é: cadastra →
/// entra (para ter token) → aplica o que a pessoa escolheu → **sai**. O logout
/// no fim não é desperdício: é o que torna verdadeira a promessa de que o livro
/// fecha e devolve ao login. Entrar com a conta recém-criada é o primeiro ato
/// dela, e tem que ser dela.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  /// Abaixo disto, duas páginas lado a lado dariam ~170pt cada — e cinco campos
  /// não cabem em 170pt sem virar letra miúda. O livro então mostra uma página
  /// por vez, com a mesma folha girando.
  static const double larguraParaFolhaDupla = 720;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  /// A cerimônia: 0 = livro fechado, 1 = aberto.
  late final AnimationController _livro = AnimationController(
    vsync: this,
    duration: SJMotion.ceremony,
  );

  /// A virada de página (só tem efeito em folha única): 0 = obrigatórios,
  /// 1 = opcionais.
  late final AnimationController _folha = AnimationController(
    vsync: this,
    duration: SJMotion.page,
  );

  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _senha = TextEditingController();
  final _confirmacao = TextEditingController();
  final _bio = TextEditingController();

  final _emailFoco = FocusNode();
  final _usernameFoco = FocusNode();
  final _senhaFoco = FocusNode();
  final _confirmacaoFoco = FocusNode();

  Uint8List? _fotoBytes;
  String _fotoNome = '';
  String _fotoMime = '';

  Map<SignupField, String> _erros = const {};
  String _erroGeral = '';

  /// Em qual página o recado geral é desenhado.
  ///
  /// Num livro de uma página por vez, "mostrar o erro" e "mostrar o erro ONDE
  /// a pessoa está olhando" são coisas diferentes — e a segunda é a única que
  /// conta. O recado do @ recusado acompanha o campo do @, na esquerda; o
  /// resto fica junto do botão, na direita.
  SignupPage _paginaDoRecado = SignupPage.opcionais;

  bool _enviando = false;

  /// A conta já existe no servidor.
  ///
  /// Importa porque o envio tem três passos e o primeiro é IRREVERSÍVEL: se o
  /// @username for recusado depois do cadastro já ter ido (reservado, ou de
  /// outra pessoa — coisas que só o servidor sabe), tentar de novo não pode
  /// cadastrar duas vezes. A partir daqui o retorno retoma do passo que falhou,
  /// e os campos já comprometidos ficam travados: editar o e-mail agora só
  /// serviria para o login seguinte falhar com a senha "certa".
  bool _contaCriada = false;

  @override
  void initState() {
    super.initState();
    _livro.forward();
  }

  @override
  void dispose() {
    _livro.dispose();
    _folha.dispose();
    _nome.dispose();
    _email.dispose();
    _username.dispose();
    _senha.dispose();
    _confirmacao.dispose();
    _bio.dispose();
    _emailFoco.dispose();
    _usernameFoco.dispose();
    _senhaFoco.dispose();
    _confirmacaoFoco.dispose();
    super.dispose();
  }

  SignupDraft get _rascunho => SignupDraft(
        nome: _nome.text,
        email: _email.text,
        username: _username.text,
        senha: _senha.text,
        confirmacao: _confirmacao.text,
        bio: _bio.text,
        temFoto: _fotoBytes != null,
      );

  bool get _folhaDupla =>
      MediaQuery.sizeOf(context).width >= RegisterScreen.larguraParaFolhaDupla;

  /// Leva o livro à página pedida. Em folha dupla não há o que virar — as duas
  /// já estão à vista.
  void _irPara(SignupPage pagina) {
    if (_folhaDupla) return;
    if (pagina == SignupPage.obrigatorios) {
      _folha.reverse();
    } else {
      _folha.forward();
    }
  }

  Future<void> _escolherFoto() async {
    final escolhida = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Mesmo pré-corte da edição de perfil: avatar não precisa de 12 MP e o
      // teto do backend é 5 MB.
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (escolhida == null) return;
    final bytes = await escolhida.readAsBytes();
    if (!mounted) return;
    setState(() {
      _fotoBytes = bytes;
      _fotoNome = escolhida.name;
      _fotoMime = escolhida.mimeType ?? 'image/jpeg';
    });
  }

  Future<void> _enviar() async {
    final rascunho = _rascunho;
    final erros = rascunho.validate();
    if (erros.isNotEmpty) {
      setState(() {
        _erros = erros;
        _erroGeral = '';
      });
      final pagina = pageComPrimeiroErro(erros);
      if (pagina != null) _irPara(pagina);
      return;
    }

    setState(() {
      _erros = const {};
      _erroGeral = '';
      _enviando = true;
    });

    // Em que passo a falha aconteceu decide o que dizer: depois do cadastro a
    // conta EXISTE, e um "não foi possível criar a conta" ali seria mentira —
    // mentira que leva a pessoa a tentar de novo com outro e-mail.
    var passo = _Passo.cadastro;
    try {
      if (!_contaCriada) {
        await Api.instance.register(rascunho.nome, rascunho.email, rascunho.senha);
        _contaCriada = true;
      }
      // O token só existe para aplicar o que vem a seguir — @username, bio e
      // foto moram atrás de autenticação.
      passo = _Passo.entrada;
      await Api.instance.login(rascunho.email, rascunho.senha);
      passo = _Passo.perfil;
      await Api.instance.updateProfile(
        username: rascunho.username,
        bio: rascunho.bio.isEmpty ? null : rascunho.bio,
      );
      final bytes = _fotoBytes;
      if (bytes != null) {
        passo = _Passo.foto;
        await Api.instance.setAvatar(bytes, _fotoNome, _fotoMime);
      }
      await _fechar(rascunho.email);
    } on ApiError catch (e) {
      _falhou(passo, e.message);
    } catch (_) {
      _falhou(passo, 'Não foi possível concluir agora.');
    }
  }

  void _falhou(_Passo passo, String mensagem) {
    if (!mounted) return;
    setState(() {
      _enviando = false;
      switch (passo) {
        // O @ é o único campo que só o servidor sabe julgar (reservado, em uso).
        // A mensagem dele já vem pronta em pt-BR; o que falta é APONTAR o campo,
        // senão a frase fica órfã num rodapé de outra página.
        case _Passo.perfil:
          _erros = {SignupField.username: mensagem};
          _erroGeral = 'A conta já foi criada — falta só acertar o @.';
          _paginaDoRecado = SignupPage.obrigatorios;
        case _Passo.entrada:
        case _Passo.foto:
          _erroGeral = 'A conta já foi criada, mas não deu para terminar: '
              '$mensagem Entre e ajuste no Perfil.';
          _paginaDoRecado = SignupPage.opcionais;
        case _Passo.cadastro:
          _erroGeral = mensagem;
          _paginaDoRecado = SignupPage.opcionais;
      }
    });
    _irPara(_paginaDoRecado);
  }

  /// Fecha o livro e volta ao login, entregando o e-mail para a porta já
  /// estar com o nome certo quando a pessoa chegar nela.
  ///
  /// **Fechar o livro apaga a sessão, SEMPRE.** O token que o envio cria
  /// existe só para aplicar @username, bio e foto — ele é ferramenta do
  /// cadastro, não a sessão de ninguém. Deixar essa invariante aqui, e não no
  /// caminho feliz, é o que garante que ela também valha nas saídas pelo lado:
  /// o "Já tenho conta" depois de uma falha no meio do envio sairia com um
  /// token vivo, e a pessoa veria a tela de login estando logada — até o
  /// próximo boot, que a jogaria direto para dentro do app.
  Future<void> _fechar([String? email]) async {
    FocusScope.of(context).unfocus();
    await Api.instance.logout();
    await _livro.reverse();
    if (!mounted) return;
    Navigator.of(context).pop(email);
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final dupla = _folhaDupla;

    return AnimatedBuilder(
      animation: Listenable.merge([_livro, _folha]),
      builder: (context, _) {
        final t = SJMotion.standard.transform(_livro.value);
        return Scaffold(
          backgroundColor: const Color(0x00000000),
          body: ColoredBox(
            // A tela de login continua pintada atrás (a rota é translúcida);
            // este véu é o que a manda para o segundo plano sem apagá-la.
            //
            // O véu é `shadow`, não `bgDeep`: no modo claro o `bgDeep` é creme,
            // e creme sobre creme não escurece nada — a primeira versão disto
            // deixava o login tão aceso quanto o livro, e a página inteira
            // virava um borrão de dois formulários empilhados. Sombra escurece
            // nos dois modos, que é o que um véu precisa fazer.
            color: s.shadow.withValues(alpha: 0.55 * t),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  SJSpace.x4,
                  SJSpace.x4,
                  SJSpace.x4,
                  SJSpace.x4 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SJBook(
                  openness: t,
                  turn: SJMotion.standard.transform(_folha.value),
                  spread: dupla,
                  coverSubtitle: 'Criar conta',
                  left: _paginaObrigatorios(s, dupla),
                  right: _paginaOpcionais(s, dupla),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- Página esquerda: o que a conta exige ---------------------------------

  Widget _paginaObrigatorios(SJScheme s, bool dupla) {
    final travado = _contaCriada;
    return _Pagina(
      numero: '01',
      titulo: 'O essencial',
      epigrafe: 'Sem isto, a conta não existe.',
      children: [
        SJTextField(
          label: 'Nome',
          controller: _nome,
          hint: 'Como quer ser chamado',
          enabled: !travado && !_enviando,
          errorText: _erros[SignupField.nome],
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _emailFoco.requestFocus(),
        ),
        SJTextField(
          label: 'E-mail',
          controller: _email,
          focusNode: _emailFoco,
          hint: 'voce@email.com',
          enabled: !travado && !_enviando,
          errorText: _erros[SignupField.email],
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _usernameFoco.requestFocus(),
        ),
        SJTextField(
          label: 'Nome de usuário',
          controller: _username,
          focusNode: _usernameFoco,
          hint: 'seu_arroba',
          enabled: !_enviando,
          errorText: _erros[SignupField.username],
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _senhaFoco.requestFocus(),
        ),
        Text(
          'Letras, números e _ , começando por letra. É assim que te encontram.',
          style: SJText.caption(color: s.inkFaint),
        ),
        SJTextField(
          label: 'Senha',
          controller: _senha,
          focusNode: _senhaFoco,
          hint: 'ao menos $senhaMinima caracteres',
          enabled: !travado && !_enviando,
          errorText: _erros[SignupField.senha],
          obscureText: true,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _confirmacaoFoco.requestFocus(),
        ),
        SJTextField(
          label: 'Confirmar senha',
          controller: _confirmacao,
          focusNode: _confirmacaoFoco,
          hint: 'a mesma de novo',
          enabled: !travado && !_enviando,
          errorText: _erros[SignupField.confirmacao],
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => dupla ? _enviar() : _irPara(SignupPage.opcionais),
        ),
        ...?_recado(s, SignupPage.obrigatorios),
        if (!dupla) ...[
          SJButton(
            label: 'Virar a página',
            variant: SJButtonVariant.secondary,
            expand: true,
            onPressed: _enviando ? null : () => _irPara(SignupPage.opcionais),
          ),
        ],
      ],
    );
  }

  /// O recado geral, desenhado só na página a que ele pertence.
  ///
  /// Devolve `null` em vez de um `SizedBox.shrink()` porque `_Pagina` separa
  /// cada filho com um respiro: um filho invisível deixaria um buraco de 12pt
  /// no meio da página toda vez que NÃO houvesse recado — que é quase sempre.
  List<Widget>? _recado(SJScheme s, SignupPage pagina) {
    if (_erroGeral.isEmpty || _paginaDoRecado != pagina) return null;
    return [
      Text(
        _erroGeral,
        textAlign: TextAlign.center,
        style: SJText.caption(color: s.danger),
      ),
    ];
  }

  // --- Página direita: o que é seu gosto ------------------------------------

  Widget _paginaOpcionais(SJScheme s, bool dupla) {
    return _Pagina(
      numero: '02',
      titulo: 'Como aparecer',
      epigrafe: 'Nada aqui é obrigatório — dá para fazer depois, no Perfil.',
      // O herbário no pé da página direita: ela é a mais arejada do livro, e
      // uma folha dupla com um lado cheio e o outro vazio desequilibra. É o
      // mesmo ramo do cartão de login — o cadastro e a porta de entrada são a
      // mesma papelaria.
      ornamento: const SJSprig(size: 170, flip: true, opacity: 0.22),
      children: [
        Center(child: _Retrato(bytes: _fotoBytes, onTap: _enviando ? null : _escolherFoto)),
        Center(
          child: SJButton(
            label: _fotoBytes == null ? 'Escolher foto' : 'Trocar foto',
            variant: SJButtonVariant.text,
            onPressed: _enviando ? null : _escolherFoto,
          ),
        ),
        SJTextField(
          label: 'Uma frase sua',
          controller: _bio,
          hint: 'o que te move',
          enabled: !_enviando,
          errorText: _erros[SignupField.bio],
          maxLines: 3,
          minLines: 2,
          onChanged: (_) => setState(() {}),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${_bio.text.trim().length}/$bioMaxima',
            style: SJText.caption(
              color: _bio.text.trim().length > bioMaxima ? s.danger : s.inkFaint,
            ),
          ),
        ),
        ...?_recado(s, SignupPage.opcionais),
        SJButton(
          label: 'Criar conta',
          loading: _enviando,
          expand: true,
          onPressed: _enviando ? null : _enviar,
        ),
        if (!dupla)
          SJButton(
            label: 'Voltar ao essencial',
            variant: SJButtonVariant.text,
            onPressed: _enviando ? null : () => _irPara(SignupPage.obrigatorios),
          ),
        Center(
          child: SJButton(
            label: 'Já tenho conta',
            variant: SJButtonVariant.text,
            onPressed: _enviando ? null : () => _fechar(),
          ),
        ),
      ],
    );
  }
}

/// Os passos do envio, em ordem. O primeiro é irreversível — depois dele a
/// conta existe, e toda mensagem precisa partir disso.
enum _Passo { cadastro, entrada, perfil, foto }

/// Uma página do livro: numeral mono, título serifado, epígrafe em itálico e o
/// conteúdo — com rolagem própria, porque o teclado não negocia.
class _Pagina extends StatelessWidget {
  const _Pagina({
    required this.numero,
    required this.titulo,
    required this.epigrafe,
    required this.children,
    this.ornamento,
  });

  final String numero;
  final String titulo;
  final String epigrafe;
  final List<Widget> children;

  /// Marca d'água no pé da página, atrás do conteúdo e sangrando para fora.
  final Widget? ornamento;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final conteudo = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SJOverline(titulo, numeral: numero),
          const SizedBox(height: SJSpace.x2),
          Text(titulo, style: SJText.h2(color: s.ink)),
          const SizedBox(height: SJSpace.x1),
          Text(
            epigrafe,
            style: SJText.bodySm(color: s.inkSoft).copyWith(
              fontFamily: SJType.serif,
              fontFamilyFallback: SJType.serifFallback,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: SJSpace.x5),
          for (final filho in children) ...[
            filho,
            const SizedBox(height: SJSpace.x3),
          ],
        ],
      ),
    );

    // O texto some na dobra do papel.
    //
    // A página tem proporção fixa e rola por dentro, então o último campo fica
    // cortado em seco na borda de baixo — e corte em seco lê como defeito de
    // layout, não como "tem mais abaixo". O esmaecido diz as duas coisas de
    // uma vez: que continua, e que é papel. Numa página que não transborda ele
    // não aparece, porque não há nada no pé para esmaecer.
    final comDobra = ShaderMask(
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.90, 1.0],
        colors: [
          const Color(0xFF000000),
          const Color(0xFF000000),
          const Color(0x00000000),
        ],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: conteudo,
    );

    if (ornamento == null) return comDobra;
    return Stack(
      children: [
        // Encostado no canto de baixo e para fora da margem: ornamento que
        // respeita a margem deixa de ser marca d'água e vira ilustração.
        Positioned(bottom: -44, right: -40, child: ornamento!),
        Positioned.fill(child: comDobra),
      ],
    );
  }
}

/// O porta-retrato da página direita: moldura de couro vazia ou a foto
/// escolhida, sempre redonda.
class _Retrato extends StatelessWidget {
  const _Retrato({required this.bytes, required this.onTap});

  final Uint8List? bytes;
  final VoidCallback? onTap;

  static const double _lado = 104;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final foto = bytes;
    return Semantics(
      button: true,
      label: foto == null ? 'Escolher foto de perfil' : 'Trocar a foto de perfil',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: _lado,
          height: _lado,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: s.surfaceAlt,
            border: Border.all(color: s.frame, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: foto == null
              ? Icon(Icons.person_outline, size: 40, color: s.inkFaint)
              : Image.memory(foto, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
