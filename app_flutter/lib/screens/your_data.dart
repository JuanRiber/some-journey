import 'package:flutter/material.dart';

import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';

/// # O que guardamos — dito em português, por quem sabe.
///
/// **Por que existe:** o app guarda o que há de mais pessoal — onde a pessoa
/// esteve, com quem, o que sentiu. Quem confia isso a alguém tem o direito de
/// saber, sem ler contrato, o que fica guardado, onde, quem mais participa e
/// como apagar.
///
/// **O que NÃO é:** uma política de privacidade com valor jurídico. É a
/// descrição do que o código faz, escrita para ser lida. Cada frase daqui
/// corresponde a um comportamento real do app ou do servidor — e
/// `test/your_data_test.dart` cobra que todo serviço de terceiros que o app
/// chama esteja nomeado nesta tela.
///
/// **Regra para quem mexer:** mudou o que o app guarda ou a quem ele chama,
/// muda este texto NO MESMO commit. Uma tela destas desatualizada é pior do
/// que tela nenhuma: ela afirma.
class YourDataScreen extends StatelessWidget {
  const YourDataScreen({super.key});

  /// Os serviços que participam, e o que cada um chega a ver. É uma lista
  /// (e não prosa solta) para o teste conseguir conferi-la contra a política
  /// de segurança do site, que nomeia cada endereço que o app pode chamar.
  static const servicos = <({String nome, String papel})>[
    (
      nome: 'Supabase',
      papel: 'guarda o banco de dados e as suas fotos. As fotos ficam num '
          'armazenamento fechado: só abrem por um link temporário, que vale '
          'uma hora e é gerado para você.',
    ),
    (
      nome: 'Render',
      papel: 'roda o servidor do Some Journey. Tudo o que o app envia passa '
          'por ele.',
    ),
    (
      nome: 'Cloudflare',
      papel: 'entrega a versão web do app e fica na frente do servidor. Vê o '
          'seu endereço de internet, como qualquer site que você abre.',
    ),
    (
      nome: 'OpenStreetMap',
      papel: 'desenha o mapa e dá nome aos lugares. O seu aparelho pede a ele '
          'as imagens da região que você está olhando; quando você busca um '
          'lugar ou salva uma memória, a busca ou as coordenadas vão a ele '
          'para descobrir a cidade e o país.',
    ),
    (
      nome: 'iTunes',
      papel: 'é o catálogo da Apple onde a música é buscada. Vai a ele o que '
          'você digita na busca — não a sua memória. Guardamos só o nome da '
          'faixa, do artista e a capa.',
    ),
    (
      nome: 'Google',
      papel: 'só participa se você entrar com a conta Google, e para '
          'confirmar que é você. O app também pode baixar dele uma letra ou '
          'um símbolo que as fontes do aparelho não tenham.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            SJSpace.screenX, SJSpace.x2, SJSpace.screenX, SJSpace.x12,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                label: 'Voltar',
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back, color: s.ink, size: 22),
                ),
              ),
            ),
            const SizedBox(height: SJSpace.x4),
            const SJOverline('Privacidade'),
            const SizedBox(height: SJSpace.x2),
            Text('O que guardamos sobre você', style: SJText.h1(color: s.ink)),
            const SizedBox(height: SJSpace.x3),
            Text(
              'Só você vê o que guarda aqui. Nada é público, nada é '
              'compartilhado, e não há anúncio nem rastreador no app.',
              style: SJText.body(color: s.ink),
            ),
            const SizedBox(height: SJSpace.x8),
            _Bloco(
              titulo: 'O que você escreve',
              itens: const [
                'As memórias: o texto, o título, a data e o lugar que você '
                    'escolheu no mapa.',
                'As jornadas, as fases da vida e a ordem que você deu a elas.',
                'O seu perfil: nome, @username, a frase e a foto.',
              ],
            ),
            _Bloco(
              titulo: 'As fotos',
              itens: const [
                'Ficam guardadas sem o que o celular anota dentro do arquivo: '
                    'coordenadas, modelo do aparelho, data e miniatura saem '
                    'antes de a foto ser guardada.',
                'O lugar de uma memória é o que você marcou no mapa — nunca o '
                    'que a foto dizia.',
              ],
            ),
            _Bloco(
              titulo: 'Por onde você andou',
              itens: const [
                'O app só usa a sua localização quando você pede: para marcar '
                    'onde está, ou enquanto grava um percurso com a tela '
                    'aberta. Ele não acompanha você em segundo plano.',
                'Os pontos de um percurso ficam no aparelho até serem '
                    'enviados, e saem dele quando o envio é confirmado.',
              ],
            ),
            _Bloco(
              titulo: 'A sua conta',
              itens: const [
                'O e-mail e o nome. A senha não é guardada: fica só uma '
                    'versão embaralhada dela, que nem nós conseguimos ler.',
                'A sessão fica no cofre do celular; no navegador, no '
                    'armazenamento do próprio site.',
              ],
            ),
            _Bloco(
              titulo: 'Quem mais participa',
              itens: [
                for (final servico in servicos)
                  '${servico.nome} ${servico.papel}',
              ],
            ),
            _Bloco(
              titulo: 'Apagar',
              itens: const [
                'O que você apaga some da tela na hora e é apagado de vez, '
                    'com as fotos, depois de 30 dias.',
                'Excluir a conta apaga tudo na hora: memórias, fotos, '
                    'jornadas, percursos, fases e perfil. Não fica cópia.',
              ],
            ),
            const SizedBox(height: SJSpace.x2),
            SJButton(
              label: 'Excluir minha conta',
              variant: SJButtonVariant.text,
              expand: true,
              onPressed: () =>
                  Navigator.of(context).pushNamed('/delete-account'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bloco extends StatelessWidget {
  const _Bloco({required this.titulo, required this.itens});

  final String titulo;
  final List<String> itens;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SJSpace.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SJOverline(titulo),
          const SizedBox(height: SJSpace.x3),
          SJCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, item) in itens.indexed) ...[
                  if (i > 0) const SizedBox(height: SJSpace.x3),
                  Text(item, style: SJText.bodySm(color: s.ink)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
