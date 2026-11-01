import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../sj_theme.dart';
import '../tokens.dart';
import 'type_styles.dart';

/// # Livro — `SJBook`
///
/// O caderno de viagens que o produto promete na primeira linha do design doc,
/// agora como objeto: uma capa que ABRE e duas páginas que se leem lado a lado.
/// Nasceu para o cadastro (obrigatórios à esquerda, opcionais à direita), mas
/// não sabe nada de formulário — recebe dois widgets e os encena.
///
/// ## Como a folha funciona (vale para a capa e para a virada de página)
///
/// Tudo é UMA primitiva: a folha. Ela tem uma lombada (`SJBookHinge`), uma
/// frente e um verso, e um progresso de virada `u` de 0 (deitada na própria
/// área, mostrando a FRENTE) a 1 (virada 180° sobre o lado de lá, mostrando o
/// VERSO). A perspectiva vem de uma matriz com `setEntry(3, 2, …)`, e o verso é
/// contra-espelhado — sem isso o texto da capa sairia escrito ao contrário.
///
/// A direção do giro depende da lombada, e isso NÃO é detalhe estético: com o
/// sinal trocado a folha afunda para trás do livro em vez de levantar na
/// direção de quem lê, e a abertura perde inteira a sensação de peso. Ver
/// [SJBookGeometry.turnAngle].
///
/// ## Duas encenações, uma só primitiva
///
/// - **Folha dupla** (`spread: true`, telas largas): uma folha só. Deitada, é a
///   página esquerda; virada, é a CAPA pousada sobre a página direita — ou
///   seja, o livro fechado. Abrir é levar `u` de 1 a 0.
/// - **Folha única** (`spread: false`, celular em pé): duas páginas lado a lado
///   num aparelho de 375pt dariam 170pt por página, e cinco campos não cabem em
///   170pt sem virar letra miúda. Então o livro mostra uma página por vez: a
///   capa abre para a esquerda e a página de obrigatórios VIRA para revelar a de
///   opcionais embaixo. Continua sendo um livro; só não cabe aberto na mão.
class SJBook extends StatelessWidget {
  const SJBook({
    super.key,
    required this.openness,
    required this.left,
    required this.right,
    this.turn = 0,
    this.spread = true,
    this.coverTitle = 'Some Journey',
    this.coverSubtitle,
    this.maxPageWidth = 420,
  });

  /// Proporção máxima largura:altura do livro ABERTO (folha dupla).
  ///
  /// Sem teto, numa janela alta o livro ia de borda a borda e ficava quase
  /// quadrado — e um objeto quase quadrado não é lido como livro aberto, é
  /// lido como dois painéis. 1,35 é a proporção de uma folha dupla de caderno
  /// de viagem; o que sobra de altura vira respiro em volta, que é o que faz o
  /// objeto POUSAR na tela em vez de preenchê-la.
  static const double _proporcaoAberto = 1.35;

  /// E a de UMA página: mais alta que larga, como qualquer página.
  static const double _proporcaoPagina = 0.70;

  /// 0 = fechado, 1 = aberto. É a cerimônia de abrir/fechar.
  final double openness;

  /// 0 = na página esquerda, 1 = na direita. Só tem efeito em folha única —
  /// com as duas páginas à vista não há o que virar.
  final double turn;

  /// Conteúdo da página esquerda (na folha única, a primeira).
  final Widget left;

  /// Conteúdo da página direita (na folha única, a segunda).
  final Widget right;

  /// Se as duas páginas aparecem juntas. Quem decide é a tela, pela largura.
  final bool spread;

  final String coverTitle;
  final String? coverSubtitle;

  /// Teto da largura de UMA página. Sem isto, num monitor largo o livro viraria
  /// uma mesa de pingue-pongue com cinco campos perdidos no meio.
  final double maxPageWidth;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final t = SJBookGeometry.clamp01(openness);

    return LayoutBuilder(
      builder: (context, c) {
        final paginas = spread ? 2 : 1;
        final larguraPagina = math.min(
          maxPageWidth,
          (c.maxWidth - SJSpace.x4) / paginas,
        );
        final larguraTotal = larguraPagina * paginas;
        // `min` com a altura disponível, nunca o contrário: numa tela baixa o
        // livro encolhe junto: a proporção é um TETO, não uma exigência.
        final altura = math.min(
          c.maxHeight,
          spread
              ? larguraTotal / _proporcaoAberto
              : larguraPagina / _proporcaoPagina,
        );

        final livro = SizedBox(
          height: altura,
          child: spread
              // A folha dupla decide a PRÓPRIA largura: ela encolhe para uma
              // página quando o livro está fechado.
              ? _folhaDupla(s, larguraPagina, altura, t)
              : SizedBox(
                  width: larguraPagina,
                  child: _folhaUnica(s, larguraPagina, altura, t),
                ),
        );

        final sombra = DecoratedBox(
          decoration: BoxDecoration(boxShadow: SJElevation.e2(s)),
          child: livro,
        );

        // Livro aberto é livro parado: nenhuma matriz sobre o formulário, pela
        // mesma razão da folha em repouso (ver `_Folha`).
        if (t >= 0.999) return Center(child: sombra);

        // A cerimônia inteira: o livro cresce da mesa, endireita o tombo e
        // ganha nitidez. Tudo derivado do MESMO `t`, então não há como uma
        // parte chegar antes da outra.
        return Center(
          child: ExcludeSemantics(
            // Durante a cerimônia o conteúdo existe mas ainda não está
            // disponível: anunciar — ou aceitar o toque de — um formulário que
            // a capa cobre é prometer um campo que a pessoa não alcança.
            child: IgnorePointer(
              child: Opacity(
                opacity: SJBookGeometry.fade(t),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, SJBookGeometry.perspective)
                    ..rotateX(SJBookGeometry.tilt(t))
                    ..scaleByDouble(
                      SJBookGeometry.lift(t),
                      SJBookGeometry.lift(t),
                      1,
                      1,
                    ),
                  child: sombra,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Telas largas: a folha esquerda cobre a direita quando o livro está fechado.
  ///
  /// O recorte que cresce é o que faz o livro FECHADO ocupar uma página só —
  /// sem ele sobraria meia folha de papel em branco ao lado da capa, e a ilusão
  /// morreria antes do primeiro quadro. Ele corre numa curva à frente da folha
  /// (ver [SJBookGeometry.openWidthFactor]) porque o papel não pode ser aparado
  /// pela própria moldura no fim da abertura.
  Widget _folhaDupla(SJScheme s, double larguraPagina, double altura, double t) {
    final larguraTotal = larguraPagina * 2;
    return SizedBox(
      // A LARGURA é a moldura, e tem de ser imposta por fora: um
      // `Align(widthFactor:)` aqui seria engolido — sob constraints apertadas
      // o `RenderPositionedBox` descarta o fator e devolve a largura cheia, e
      // o livro fechado apareceria com meia página em branco ao lado da capa.
      width: larguraTotal * SJBookGeometry.openWidthFactor(t),
      child: ClipRect(
        child: OverflowBox(
          // A folha dupla mantém o tamanho inteiro por dentro e fica ancorada
          // à direita: abrir é a moldura andando para a esquerda e descobrindo
          // o que já estava lá.
          alignment: Alignment.centerRight,
          minWidth: larguraTotal,
          maxWidth: larguraTotal,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Corpo do livro: o papel das duas páginas e a sombra da
              // lombada. A página esquerda fica VAZIA aqui de propósito — o
              // conteúdo dela viaja na folha que gira, que é onde ele está num
              // livro de verdade.
              Positioned.fill(child: _corpo(s, larguraPagina, direita: right)),
              Positioned(
                left: 0,
                top: 0,
                width: larguraPagina,
                height: altura,
                child: _Folha(
                  u: 1 - t,
                  hinge: SJBookHinge.right,
                  frente: _pagina(s, left, lombadaEsquerda: false),
                  verso: _Capa(
                    titulo: coverTitle,
                    subtitulo: coverSubtitle,
                    lombadaEsquerda: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Celular em pé: uma página por vez, duas folhas empilhadas.
  Widget _folhaUnica(SJScheme s, double larguraPagina, double altura, double t) {
    final u = SJBookGeometry.clamp01(turn);
    return ClipRect(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Embaixo de tudo, os opcionais: é o que aparece quando a página de
          // cima vira. Enquanto a folha de cima não passou da perpendicular,
          // esta página está COBERTA — e página coberta não existe para o
          // toque nem para o leitor de tela, pelo mesmo motivo que vale para a
          // folha virada. Sem esta guarda o leitor anunciaria as duas páginas
          // de uma vez, num livro que mostra uma.
          Positioned.fill(
            child: ExcludeSemantics(
              excluding: !SJBookGeometry.showsBack(u),
              child: IgnorePointer(
                ignoring: !SJBookGeometry.showsBack(u),
                child: _corpo(s, larguraPagina, direita: right),
              ),
            ),
          ),
          Positioned.fill(
            child: _Folha(
              u: u,
              hinge: SJBookHinge.left,
              frente: _pagina(s, left, lombadaEsquerda: true),
              // O verso de uma página virada é o miolo do papel, não a próxima
              // página — essa está EMBAIXO. Pintar conteúdo aqui seria mostrar
              // a mesma coisa duas vezes no mesmo quadro.
              verso: _Papel(lombadaEsquerda: false),
            ),
          ),
          // A capa, por cima de tudo. Aqui `u` segue `t` (e não `1 - t` como na
          // folha dupla) porque esta folha é a PRÓPRIA capa: em repouso ela
          // está fechada sobre o livro, e abrir é virá-la para fora do quadro.
          // Com o sinal invertido, o livro aberto ficaria coberto pelo verso
          // da capa — papel limpo sobre o formulário inteiro.
          Positioned.fill(
            child: _Folha(
              u: t,
              hinge: SJBookHinge.left,
              frente: _Capa(
                titulo: coverTitle,
                subtitulo: coverSubtitle,
                lombadaEsquerda: true,
              ),
              verso: _Papel(lombadaEsquerda: false),
            ),
          ),
        ],
      ),
    );
  }

  /// O bloco de papel sob as folhas: página(s), vinco da lombada e a sombra que
  /// a folha de cima projeta.
  Widget _corpo(SJScheme s, double larguraPagina, {required Widget direita}) {
    return Row(
      children: [
        if (spread) SizedBox(width: larguraPagina, child: _Papel(lombadaEsquerda: false)),
        SizedBox(
          width: larguraPagina,
          child: _pagina(s, direita, lombadaEsquerda: spread),
        ),
      ],
    );
  }

  Widget _pagina(SJScheme s, Widget conteudo, {required bool lombadaEsquerda}) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        _Papel(lombadaEsquerda: lombadaEsquerda),
        Padding(
          // Respiro assimétrico: a margem junto da lombada é maior porque ali o
          // papel some na dobra. É a regra de qualquer livro impresso.
          padding: EdgeInsets.fromLTRB(
            lombadaEsquerda ? SJSpace.x8 : SJSpace.x6,
            SJSpace.x6,
            lombadaEsquerda ? SJSpace.x6 : SJSpace.x8,
            SJSpace.x6,
          ),
          child: conteudo,
        ),
      ],
    );
  }
}

/// De que lado está a lombada da folha — e, portanto, em torno de que aresta
/// ela gira.
enum SJBookHinge { left, right }

/// A matemática do livro, separada do desenho.
///
/// PORQUÊ pura: ângulo, sombreado e recorte são as três coisas que, erradas,
/// transformam a animação num papel que pisca. Erro de sinal não aparece em
/// `flutter analyze` e não aparece numa captura de tela parada — só no meio do
/// movimento. Aqui cada uma é uma função de `t` que um teste consegue perguntar
/// quadro a quadro.
abstract final class SJBookGeometry {
  /// Profundidade da projeção. Mais que isto e o papel vira origami de ficção
  /// científica; menos e a folha gira como um adesivo plano.
  static const double perspective = 0.0014;

  static double clamp01(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0);

  /// Ângulo da folha, em radianos, para o progresso de virada [u].
  ///
  /// O SINAL vem da lombada, e é o detalhe que decide se a animação tem peso:
  /// a aresta livre precisa subir na direção de quem lê (z negativo = mais
  /// perto, na convenção da matriz de perspectiva do Flutter) e só depois
  /// tombar para o outro lado. Com o sinal invertido ela mergulha para trás do
  /// livro — tecnicamente uma rotação de 180° igualzinha, visualmente uma porta
  /// se fechando ao contrário.
  ///
  /// Lombada à direita: o corpo da folha está em x < 0 relativo à dobra, então
  /// z = −x·sen(θ) fica negativo com θ negativo. Lombada à esquerda, x > 0, o
  /// sinal se inverte junto.
  static double turnAngle(double u, SJBookHinge hinge) {
    final sentido = hinge == SJBookHinge.left ? 1.0 : -1.0;
    return sentido * math.pi * clamp01(u);
  }

  /// Passada a meia-volta, quem está de frente para o leitor é o VERSO.
  ///
  /// A troca acontece exatamente em 90°, onde a folha está de perfil e ocupa
  /// zero pixel de largura — por isso ela é invisível, e não um salto.
  static bool showsBack(double u) => clamp01(u) > 0.5;

  /// Quanto a folha escurece ao girar: 0 deitada (em qualquer das duas faces),
  /// 1 de perfil. É a luz raspando o papel, e é o que dá volume ao giro.
  static double sheen(double u) => math.sin(math.pi * clamp01(u)).abs();

  /// Fração da largura total visível do livro: meia página fechado, inteira
  /// aberto.
  ///
  /// Corre à FRENTE da abertura (`easeOut`) porque no fim do movimento a folha
  /// já está quase deitada sobre a página esquerda: se a moldura ainda
  /// estivesse estreita nesse instante, ela apararia a aresta do próprio papel.
  /// Com a curva adiantada, a moldura chega inteira antes da folha pousar.
  static double openWidthFactor(double t) {
    final adiantado = 1 - math.pow(1 - clamp01(t), 3).toDouble();
    return 0.5 + 0.5 * adiantado;
  }

  /// O livro cresce ao ser levantado da mesa.
  static double lift(double t) => 0.90 + 0.10 * clamp01(t);

  /// Tombo em X: fechado o livro está deitado na mesa, aberto encara o leitor.
  static double tilt(double t) => 0.10 * (1 - clamp01(t));

  /// A primeira fração da abertura é também a entrada em cena — mas MUITO
  /// rápida, ou o livro parece um fantasma em vez de um objeto.
  ///
  /// Começou em `t * 4` e ainda dava para ver a tela de login através da capa
  /// de couro no primeiro terço do movimento. Um livro é opaco; a entrada é só
  /// para ele não aparecer de estalo.
  static double fade(double t) => math.min(1.0, clamp01(t) * 6);
}

/// Uma folha com frente, verso e dobra. A primitiva de tudo aqui.
class _Folha extends StatelessWidget {
  const _Folha({
    required this.u,
    required this.hinge,
    required this.frente,
    required this.verso,
  });

  final double u;
  final SJBookHinge hinge;
  final Widget frente;
  final Widget verso;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final progresso = SJBookGeometry.clamp01(u);
    final angulo = SJBookGeometry.turnAngle(progresso, hinge);
    final mostraVerso = SJBookGeometry.showsBack(progresso);

    final face = mostraVerso
        // Contra-espelho: a face de trás é vista pelo avesso, e sem esta
        // rotação o título da capa sairia em escrita especular.
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(math.pi),
            child: verso,
          )
        : frente;

    // Folha fora do repouso não recebe toque NEM leitura: virada, ela continua
    // na árvore, e o Flutter acerta o toque dela pela matriz inversa — o campo
    // da página de cima roubaria o toque do botão da página de baixo, e o
    // leitor de tela anunciaria uma página que está de costas.
    final emRepouso = progresso <= 0.001;

    // EM REPOUSO A FOLHA NÃO TEM MATRIZ NENHUMA — e isto não é otimização.
    //
    // A matriz de perspectiva é NÃO AFIM (o `setEntry(3, 2, …)`), e uma página
    // de livro rola por dentro. Quando um campo recebe foco, o Flutter chama
    // `Scrollable.ensureVisible` sozinho para trazê-lo acima do teclado — e
    // esse cálculo atravessa a matriz dos ancestrais. Sob uma matriz não afim
    // ele devolve um deslocamento que não converge: o viewport reagenda quadro
    // atrás de quadro e a página trava rolando. Apareceu primeiro como um
    // `pumpAndSettle` que nunca terminava no teste; no aparelho seria o
    // formulário congelando ao tocar no campo de baixo.
    //
    // Deitada, a folha é um retângulo plano: a matriz só teria efeito sobre
    // pontos com z ≠ 0, que não existem aqui. Então ela não é aplicada — e o
    // estado em que a pessoa realmente digita fica livre de transformação.
    if (emRepouso) return face;

    return ExcludeSemantics(
      child: IgnorePointer(
        child: Transform(
          alignment:
              hinge == SJBookHinge.left ? Alignment.centerLeft : Alignment.centerRight,
          transform: Matrix4.identity()
            ..setEntry(3, 2, SJBookGeometry.perspective)
            ..rotateY(angulo),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              face,
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: s.shadow.withValues(
                      alpha: 0.55 * SJBookGeometry.sheen(progresso),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// O papel: fundo da página e o vinco da lombada.
class _Papel extends StatelessWidget {
  const _Papel({required this.lombadaEsquerda});

  /// De que lado o papel mergulha na dobra (de onde vem a sombra do vinco).
  final bool lombadaEsquerda;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: s.surface),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: lombadaEsquerda ? Alignment.centerLeft : Alignment.centerRight,
            end: lombadaEsquerda ? Alignment.centerRight : Alignment.centerLeft,
            // A sombra do vinco morre em 22% da página: é dobra, não vinheta.
            //
            // No claro ela começou em 0,14 e o resultado foram duas folhas
            // lisas encostadas — sem o mergulho na dobra, uma folha dupla lê
            // como dois cartões lado a lado, e a palavra "livro" não aparece.
            // 0,24 ainda é suave perto de qualquer sombra dura, e é o que faz
            // o papel afundar.
            stops: const [0.0, 0.22],
            colors: [
              s.shadow.withValues(alpha: s.brightness == Brightness.dark ? 0.50 : 0.24),
              s.shadow.withValues(alpha: 0.0),
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// A capa: couro, filete dourado e a rosa dos ventos da marca.
class _Capa extends StatelessWidget {
  const _Capa({required this.titulo, required this.subtitulo, required this.lombadaEsquerda});

  final String titulo;
  final String? subtitulo;
  final bool lombadaEsquerda;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        // Couro: o vinho da ação, escurecido na borda oposta à lombada, como
        // encadernação iluminada de lado.
        gradient: LinearGradient(
          begin: lombadaEsquerda ? Alignment.centerLeft : Alignment.centerRight,
          end: lombadaEsquerda ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            Color.lerp(s.primary, s.shadow, 0.35)!,
            s.primary,
          ],
        ),
      ),
      child: CustomPaint(
        painter: _CapaPainter(s),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(SJSpace.x8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: SJText.h2(color: s.accent),
                ),
                if (subtitulo != null) ...[
                  const SizedBox(height: SJSpace.x2),
                  Text(
                    subtitulo!.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: SJText.overline(color: s.accent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Filete duplo e rosa dos ventos gravados na capa — mesmo traço fino das
/// ilustrações do sistema (§6 do design doc).
class _CapaPainter extends CustomPainter {
  const _CapaPainter(this.scheme);

  final SJScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final ouro = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = scheme.accent.withValues(alpha: 0.55)
      ..isAntiAlias = true;

    // Filete duplo, a assinatura de uma encadernação boa.
    for (final recuo in const [22.0, 28.0]) {
      if (size.width <= recuo * 2 || size.height <= recuo * 2) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(recuo, recuo, size.width - recuo * 2, size.height - recuo * 2),
          const Radius.circular(SJRadius.sm),
        ),
        ouro..color = scheme.accent.withValues(alpha: recuo == 22.0 ? 0.55 : 0.28),
      );
    }

    // Rosa dos ventos: oito raios e um anel, centrados acima do título.
    final centro = Offset(size.width / 2, size.height * 0.33);
    final raio = math.min(size.width, size.height) * 0.11;
    if (raio < 8) return;
    final traco = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = scheme.accent.withValues(alpha: 0.7)
      ..isAntiAlias = true;
    canvas.drawCircle(centro, raio, traco);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      // Os quatro pontos cardeais ganham raio inteiro; os colaterais, metade —
      // é o que faz a rosa parecer uma rosa e não um sol.
      final comprimento = i.isEven ? raio * 1.45 : raio * 0.62;
      canvas.drawLine(
        centro,
        centro + Offset(math.sin(a), -math.cos(a)) * comprimento,
        traco,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CapaPainter old) => old.scheme != scheme;
}
