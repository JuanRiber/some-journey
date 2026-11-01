import 'package:flutter/material.dart';

import '../api.dart';
import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';

/// # Entrar — a porta do próprio atlas.
///
/// **Por que existe:** as memórias são privadas; esta é a única entrada.
///
/// **O que o usuário sente:** que chegou num lugar com cuidado. A arte de
/// marca sangra na tela inteira e o formulário pousa sobre ela como uma folha
/// de papel carimbada — a mesma folha que o cadastro vai abrir como livro.
///
/// **Ação principal:** entrar. Secundárias: recuperar senha e criar conta.
///
/// **Atrito:** dois campos, teclado encadeado (e-mail → senha → enviar), olho
/// para conferir a senha digitada, rolagem que respeita o teclado e erro
/// inline (nunca um diálogo que interrompe).
///
/// ## Duas composições
///
/// Acima de [_larguraParaDuasColunas] a tela é um **pôster**: foto sangrando,
/// a promessa da marca à esquerda e o cartão de papel à direita. Abaixo disso
/// a foto vira uma faixa no topo e o formulário desce em coluna única — num
/// celular, texto branco sobre foto com um formulário em cima seria ilegível
/// nos dois.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  /// Onde o pôster deixa de caber. Abaixo disto, coluna única.
  static const double _larguraParaDuasColunas = 900;

  /// Largura do cartão no pôster. Fixa de propósito: um formulário que estica
  /// com a janela vira uma linha de 900pt, e ninguém lê um campo desses.
  static const double _larguraDoCartao = 430;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  bool _senhaVisivel = false;
  String _error = '';

  /// Recado de boas-vindas depois que o livro do cadastro fecha. Não é erro
  /// nem sucesso de login — é a confirmação de que a conta nasceu, dita no
  /// lugar onde ela vai ser usada pela primeira vez.
  String _aviso = '';

  /// Abre o cadastro em livro.
  ///
  /// A rota é translúcida (ver `main.dart`), então ESTA tela continua pintada
  /// atrás enquanto a capa se levanta — e com a foto sangrando, é o pôster
  /// inteiro que escurece. Ao fechar, o livro devolve o e-mail recém-criado, e
  /// a porta já está com o nome certo quando a pessoa chega nela.
  Future<void> _abrirLivro() async {
    final criado = await Navigator.of(context).pushNamed<Object?>('/register');
    if (!mounted || criado is! String) return;
    setState(() {
      _email.text = criado;
      _error = '';
      _aviso = 'Conta criada. Agora é só entrar.';
    });
    _passwordFocus.requestFocus();
  }

  Future<void> _onLogin() async {
    setState(() {
      _error = '';
      _aviso = '';
      _loading = true;
    });
    try {
      await Api.instance.login(_email.text.trim(), _password.text);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/tabs', (_) => false);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Erro inesperado.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, c) {
            final poster = c.maxWidth >= LoginScreen._larguraParaDuasColunas;
            return Column(
              children: [
                _BarraDaMarca(
                  compacta: !poster,
                  onCriarConta: _loading ? null : _abrirLivro,
                ),
                Expanded(child: poster ? _poster(s) : _coluna(s)),
              ],
            );
          },
        ),
      ),
    );
  }

  // --- Composição larga: pôster ---------------------------------------------

  Widget _poster(SJScheme s) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const _Foto(),
        // Véu que desce da esquerda: é o que deixa o texto claro legível sobre
        // uma foto que tem céu, neve e vidro iluminado. Morre antes do cartão
        // para não sujar o papel.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: const [0.0, 0.70],
              colors: [
                s.shadow.withValues(alpha: 0.88),
                s.shadow.withValues(alpha: 0.10),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(SJSpace.x6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: _Promessa()),
              const SizedBox(width: SJSpace.x8),
              SizedBox(
                width: LoginScreen._larguraDoCartao,
                child: _cartao(s, emPapel: true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Composição estreita: coluna ------------------------------------------

  Widget _coluna(SJScheme s) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            height: 210,
            child: Stack(
              fit: StackFit.expand,
              children: [_Foto(), _TituloSobreAFoto()],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SJSpace.screenX,
              SJSpace.x6,
              SJSpace.screenX,
              SJSpace.x10,
            ),
            child: _cartao(s, emPapel: false),
          ),
        ],
      ),
    );
  }

  // --- O formulário ---------------------------------------------------------

  /// `emPapel`: no pôster o formulário é um cartão de verdade (superfície,
  /// raio, elevação); na coluna única ele já ESTÁ no papel da página, e
  /// desenhar um cartão dentro de outro só duplicaria a borda.
  Widget _cartao(SJScheme s, {required bool emPapel}) {
    final campos = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SJOverline('Bem-vindo(a)'),
          const SizedBox(height: SJSpace.x3),
          Text('Que bom\nte ver por aqui.', style: SJText.display(color: s.ink)),
          const SizedBox(height: SJSpace.x3),
          Text(
            'Faça login para continuar sua jornada.',
            style: SJText.body(color: s.inkSoft),
          ),
          const SizedBox(height: SJSpace.x6),
          SJTextField(
            label: 'E-mail',
            controller: _email,
            hint: 'voce@email.com',
            enabled: !_loading,
            leading: const Icon(Icons.mail_outline),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: SJSpace.x4),
          SJTextField(
            label: 'Senha',
            controller: _password,
            focusNode: _passwordFocus,
            hint: 'Sua senha',
            enabled: !_loading,
            leading: const Icon(Icons.lock_outline),
            trailing: _OlhoDaSenha(
              visivel: _senhaVisivel,
              onTap: () => setState(() => _senhaVisivel = !_senhaVisivel),
            ),
            obscureText: !_senhaVisivel,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _onLogin(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: SJButton(
              label: 'Esqueci minha senha',
              variant: SJButtonVariant.text,
              onPressed: _loading
                  ? null
                  : () => Navigator.of(context).pushNamed('/forgot'),
            ),
          ),
          if (_aviso.isNotEmpty) ...[
            const SizedBox(height: SJSpace.x2),
            Text(
              _aviso,
              textAlign: TextAlign.center,
              style: SJText.caption(color: s.moss),
            ),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: SJSpace.x2),
            Text(
              _error,
              textAlign: TextAlign.center,
              style: SJText.caption(color: s.danger),
            ),
          ],
          const SizedBox(height: SJSpace.x4),
          SJButton(
            label: 'Entrar',
            loading: _loading,
            expand: true,
            trailingIcon: Icons.arrow_forward,
            onPressed: _loading ? null : _onLogin,
          ),
          const SizedBox(height: SJSpace.x5),
          const _Ou(),
          const SizedBox(height: SJSpace.x5),
          const _ContinuarComGoogle(),
          const SizedBox(height: SJSpace.x5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  'Não tem uma conta?',
                  style: SJText.bodySm(color: s.inkSoft),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: SJSpace.x1),
              SJButton(
                label: 'Criar conta',
                variant: SJButtonVariant.text,
                trailingIcon: Icons.arrow_forward,
                onPressed: _loading ? null : _abrirLivro,
              ),
            ],
          ),
        ],
      );

    // No pôster o cartão tem altura fixa e rola por dentro. Na coluna única
    // quem rola é a PÁGINA — empilhar um scroll vertical dentro do outro dá
    // "viewport was given unbounded height" e a tela não monta.
    final conteudo = emPapel
        ? SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: campos,
          )
        : campos;

    // O carimbo é marca d'água: fica POR TRÁS do conteúdo, encostado no canto,
    // e sangra para fora do papel como num passaporte de verdade.
    final comCarimbo = Stack(
      children: [
        // O carimbo sangra para fora do papel, como num passaporte. No cartão
        // largo cabe inteiro no canto; na coluna única ele encolhe e recua
        // mais — em 390pt o tamanho do pôster atravessava as ondas por cima do
        // "Que bom", e marca d'água que disputa com o título deixou de ser
        // marca d'água.
        Positioned(
          top: emPapel ? -18 : -24,
          right: emPapel ? -34 : -62,
          child: SJSeal(size: emPapel ? 118 : 84, opacity: emPapel ? 0.42 : 0.3),
        ),
        // O par do carimbo: herbário no canto de baixo. Sangra para fora do
        // papel e fica atrás do conteúdo — é o que transforma uma superfície
        // lisa numa página guardada.
        if (emPapel)
          Positioned(bottom: -34, left: -26, child: const SJSprig(size: 190)),
        Padding(
          padding: EdgeInsets.all(emPapel ? SJSpace.x8 : 0),
          child: conteudo,
        ),
      ],
    );

    if (!emPapel) return comCarimbo;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(SJRadius.xl),
        boxShadow: SJElevation.e2(s),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SJRadius.xl),
        child: comCarimbo,
      ),
    );
  }
}

/// A foto de marca, sangrando. Um só ponto de verdade para as duas composições.
class _Foto extends StatelessWidget {
  const _Foto();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/first-class-art.jpg',
      fit: BoxFit.cover,
      semanticLabel:
          'Ilustração: viajante lendo o atlas num vagão de primeira classe',
    );
  }
}

/// Barra da marca: bússola, nome e a porta do cadastro.
///
/// Sem links de navegação de propósito. O desenho de referência traz
/// "Início · Diário · Memórias · Atlas · Sobre", mas nada disso existe fora da
/// sessão: Memórias e Atlas pedem conta, e Diário e Sobre não existem no
/// produto. Link morto numa primeira tela é promessa quebrada no primeiro
/// toque — então a barra carrega o que é real, a identidade e a ação.
class _BarraDaMarca extends StatelessWidget {
  const _BarraDaMarca({required this.compacta, required this.onCriarConta});

  /// Num celular a barra carrega SÓ a identidade. A ação some daqui porque o
  /// formulário logo abaixo já tem "Criar conta" — repetir custaria a metade
  /// da largura de uma barra de 390pt para dizer de novo o que está a um
  /// polegar de distância.
  final bool compacta;

  final VoidCallback? onCriarConta;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Container(
      color: s.bg,
      padding: EdgeInsets.symmetric(
        horizontal: compacta ? SJSpace.x4 : SJSpace.x6,
        vertical: SJSpace.x3,
      ),
      child: Row(
        children: [
          SJSeal(size: 32, legend: '', opacity: 0.85),
          const SizedBox(width: SJSpace.x2),
          // `Expanded`, não `Flexible` + `Spacer`: os dois têm flex 1 e
          // RACHAM a sobra pela metade, então o botão parava no meio da barra
          // em vez de ir para a borda. Com `Expanded` o texto fica com toda a
          // folga (alinhado à esquerda) e empurra o botão até o fim.
          Expanded(
            child: Text(
              'Some Journey',
              style: SJText.title(color: s.ink),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!compacta) ...[
            const SizedBox(width: SJSpace.x4),
            SJButton(
              label: 'Criar conta',
              variant: SJButtonVariant.secondary,
              onPressed: onCriarConta,
            ),
          ],
        ],
      ),
    );
  }
}

/// A promessa da marca sobre a foto: o nome em display, a tagline, o que o
/// produto é, os três pilares e a frase que resume tudo.
class _Promessa extends StatelessWidget {
  const _Promessa();

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    // Sobre foto, a tinta é sempre a clara do tema noturno — o papel quente
    // some contra o céu da ilustração. É o único lugar do app onde a cor não
    // vem do esquema ATIVO, e vem assim de propósito.
    final tinta = sjDark.ink;
    final suave = sjDark.ink.withValues(alpha: 0.82);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: SJSpace.x6),
          Text('Some\nJourney',
              style: SJText.display(color: tinta).copyWith(
                fontSize: 64,
                height: 1.02,
              )),
          const SizedBox(height: SJSpace.x2),
          Text(
            'A vida deixa rastros.',
            style: SJText.h2(color: s.accent).copyWith(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: SJSpace.x5),
          SizedBox(
            width: 380,
            child: Text(
              'Mais que um diário, um lugar para registrar memórias, planejar '
              'jornadas e construir o seu próprio atlas de vida.',
              style: SJText.body(color: suave),
            ),
          ),
          const SizedBox(height: SJSpace.x6),
          _Fio(color: tinta),
          const SizedBox(height: SJSpace.x6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _Pilar(
                icone: Icons.menu_book_outlined,
                titulo: 'Memórias',
                corpo: 'Registre momentos que importam.',
              ),
              SizedBox(width: SJSpace.x6),
              _Pilar(
                icone: Icons.map_outlined,
                titulo: 'Jornadas',
                corpo: 'Planeje e acompanhe seus caminhos.',
              ),
              SizedBox(width: SJSpace.x6),
              _Pilar(
                icone: Icons.explore_outlined,
                titulo: 'Atlas pessoal',
                corpo: 'Construa o mapa da sua própria história.',
              ),
            ],
          ),
          const SizedBox(height: SJSpace.x6),
          _Fio(color: tinta),
          const SizedBox(height: SJSpace.x6),
          SizedBox(
            width: 420,
            child: Text(
              '“Não são os destinos que definem uma vida, mas os rastros que '
              'ela deixa pelo caminho.”',
              style: SJText.body(color: tinta).copyWith(
                fontFamily: SJType.serif,
                fontFamilyFallback: SJType.serifFallback,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: SJSpace.x6),
        ],
      ),
    );
  }
}

/// Um dos três pilares: disco vazado com o ícone, título e uma linha.
class _Pilar extends StatelessWidget {
  const _Pilar({required this.icone, required this.titulo, required this.corpo});

  final IconData icone;
  final String titulo;
  final String corpo;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final tinta = sjDark.ink;
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: s.accent.withValues(alpha: 0.75)),
            ),
            child: Icon(icone, size: 21, color: s.accent),
          ),
          const SizedBox(height: SJSpace.x3),
          Text(titulo, style: SJText.title(color: tinta)),
          const SizedBox(height: SJSpace.x1),
          Text(
            corpo,
            style: SJText.bodySm(color: tinta.withValues(alpha: 0.78)),
          ),
        ],
      ),
    );
  }
}

/// Fio curto de separação sobre a foto — a régua do caderno, não um divisor.
class _Fio extends StatelessWidget {
  const _Fio({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 56,
        height: 1,
        color: color.withValues(alpha: 0.45),
      );
}

/// Na coluna única a foto é uma faixa, e o nome da marca mora sobre ela.
class _TituloSobreAFoto extends StatelessWidget {
  const _TituloSobreAFoto();

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: const [0.0, 0.75],
          colors: [
            s.shadow.withValues(alpha: 0.80),
            s.shadow.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SJSpace.x5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Some Journey',
              style: SJText.h1(color: sjDark.ink),
            ),
            Text(
              'A vida deixa rastros.',
              style: SJText.bodySm(color: s.accent).copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// O olho de conferir a senha. Alvo de 44pt mesmo com ícone de 18.
class _OlhoDaSenha extends StatelessWidget {
  const _OlhoDaSenha({required this.visivel, required this.onTap});

  final bool visivel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Semantics(
      button: true,
      label: visivel ? 'Ocultar a senha' : 'Mostrar a senha',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            visivel ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 19,
            color: s.inkFaint,
          ),
        ),
      ),
    );
  }
}

/// Fio — "ou" — fio.
class _Ou extends StatelessWidget {
  const _Ou();

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final fio = Expanded(child: Container(height: 1, color: s.line));
    return Row(
      children: [
        fio,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SJSpace.x3),
          child: Text('ou', style: SJText.bodySm(color: s.inkFaint)),
        ),
        fio,
      ],
    );
  }
}

/// Entrar com Google — desenhado, desligado, e dizendo que está desligado.
///
/// O backend não tem OAuth: `POST /auth/login` só conhece e-mail e senha. Um
/// botão bonito que não faz nada é pior que um botão ausente, e um botão
/// ausente estragaria a composição que o desenho pede. A saída honesta é a
/// mesma que Configurações já usa no app inteiro: aparece, com "em breve"
/// escrito, e não aceita toque.
class _ContinuarComGoogle extends StatelessWidget {
  const _ContinuarComGoogle();

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Opacity(
      opacity: 0.55,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: s.surface,
          border: Border.all(color: s.line),
          borderRadius: BorderRadius.circular(SJRadius.md),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                'Continuar com Google',
                style: SJText.bodySm(color: s.ink),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: SJSpace.x2),
            SJBadge('em breve', color: s.inkFaint),
          ],
        ),
      ),
    );
  }
}
