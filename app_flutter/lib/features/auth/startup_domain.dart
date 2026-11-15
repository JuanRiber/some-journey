/// Com que telas o app abre — decidido DEPOIS de saber se há sessão.
///
/// **Por que existe:** no build web a rota mora no hash, e recarregar a página
/// em `#/profile` entrega `/profile` ao app como rota inicial. Montar essa tela
/// direto, no primeiro quadro, é montá-la antes de o token salvo ser lido: ela
/// pede seus dados sem `Authorization`, recebe 401 e manda para o login uma
/// pessoa que estava logada. Por isso o app abre SEMPRE só no bootstrap, e o
/// que vem depois sai daqui, já com a resposta sobre a sessão em mãos.
///
/// Dart puro de propósito: a regra é testável sem montar tela nenhuma.
library;

/// Rotas que existem para quem ainda NÃO entrou. Com sessão, pedir uma delas
/// não faz sentido — o destino é o atlas.
const rotasPublicas = {'/login', '/forgot', '/register'};

/// A pilha de rotas inicial, de baixo para cima. Nunca vazia.
///
/// [requested] é a rota que a plataforma pediu (o hash, na web); [hasToken]
/// diz se a sessão foi restaurada; [buildable] são os nomes que o app sabe
/// montar SEM argumento.
///
/// - Sem sessão: só o login, seja qual for a rota pedida. Tela protegida não
///   nasce sem token — nasceria só para tomar 401.
/// - Com sessão: o atlas e, por cima, a rota pedida — desde que ela se monte
///   sem argumento. O atlas fica por baixo para "voltar" ter para onde ir.
/// - Detalhe e edição (`/memory`, `/journey`…) levam um id que o hash não
///   guarda: não há o que reconstruir, e abrem no atlas.
List<String> startupStack({
  required String? requested,
  required bool hasToken,
  required Set<String> buildable,
}) {
  if (!hasToken) return const ['/login'];
  // Só o caminho: um `?x=1` pendurado no hash não muda de que tela se trata.
  final rota = requested == null ? null : Uri.tryParse(requested)?.path;
  if (rota == null ||
      rota == '/tabs' ||
      rotasPublicas.contains(rota) ||
      !buildable.contains(rota)) {
    return const ['/tabs'];
  }
  return ['/tabs', rota];
}
