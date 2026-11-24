# Changelog

Registro das mudanças de **documentação** (`/docs`). Mudanças de código ficam no histórico do Git.

## 2026-06-28

### Documentação
- Criada a estrutura inicial da pasta `/docs`.
- Registrada a visão do produto Some Journey.
- Registradas as regras de negócio iniciais.
- Registrada a modelagem inicial de usuários, memórias, jornadas e pontos de jornada.
- Registrada a decisão de armazenar imagens no Supabase Storage.
- Registrada a decisão de manter apenas a referência da imagem no PostgreSQL/PostGIS.
- Registrada a regra de que memórias podem existir sem jornada.
- Registrada a regra de que jornadas conectam memórias em sequência.
- Registrada a possibilidade de conectar pontos soltos a jornadas posteriormente.
- Registrados os fluxos principais de usuário.
- Registrado o roadmap inicial do produto.

> Nota: a documentação foi escrita **alinhada ao código atual**, marcando o que já está
> implementado e o que é planejado. Divergências conhecidas frente à especificação original:
> a tabela de vínculo se chama `journey_memories` (conceito "journey_points"); existe o status
> `draft` e a transição `resume`; o mapa usa Leaflet/OSM hoje (Mapbox planejado); `PATCH /journeys/{id}`
> e `DELETE /memories/{id}/image` ainda não existem; o título da memória hoje é obrigatório.

## 2026-07-08

### Documentação
- Registrada a distinção entre **linha simbólica** (liga memórias na ordem) e
  **percurso real por GPS** (`Real Journey Track`).
- Documentados os endpoints de percurso (`/journeys/{id}/tracks/...`) e o mapa da
  jornada em GeoJSON (`GET /journeys/{id}/map`) no README.
- Roadmap: percurso real por GPS marcado como feito no MVP; tracking em segundo
  plano registrado como evolução (exige `expo-task-manager` + dev build).

## 2026-08-25

### Documentação
- **Reconciliação geral com o código.** A documentação tinha ficado para trás do
  HEAD; o levantamento foi feito contra o schema real do banco e o OpenAPI da API
  em execução, não por leitura de código.
- README: passou a descrever os **dois clientes** (`app_flutter/`, onde a evolução
  acontece, e `mobile/`), além de `docs/`, `e2e/` e `render.yaml`, que não
  apareciam na árvore do projeto.
- README: removida a afirmação de que as tabelas são criadas no startup — o
  `create_all` saiu na adoção do Alembic e o próprio README já dizia o contrário
  mais abaixo.
- README: seção de API completada com recuperação de senha, `/me/profile`,
  `/me/avatar`, `PATCH /journeys/{id}`, capa da jornada, fotos no plural,
  `GET /journeys/{id}/memories`, `/health/ready` e o contrato de paginação.
- README: "Status atual" corrigido — upload de imagens, recuperação de senha e o
  mapa do atlas estavam marcados como pendentes, mas já existem.
- README: nova seção **Divergências conhecidas**, registrando o que ainda não bate
  entre código, documentação e intenção de produto.
- [`02-modelagem.md`](02-modelagem.md): acrescentadas as tabelas que faltavam
  (`memory_images`, `journey_tracks`, `journey_track_points`,
  `password_reset_tokens`), os campos de lugar em `memories`, `mood`/`is_private`
  em `journeys` e `username`/`avatar_path`/`bio`/`password_changed_at` em `users`.
- [`03-api-planejada.md`](03-api-planejada.md): `PATCH /journeys/{id}` e o delete
  de imagem deixaram de ser 🔜 (existem); documentados perfil, avatar, capa,
  paginação (cursor no header `X-Next-Cursor`) e saúde.
- [`01-regras-negocio.md`](01-regras-negocio.md): registrada a divergência de que
  **`text` virou opcional** na API, o inverso da regra "texto é o núcleo".
- [`06-roadmap.md`](06-roadmap.md): "múltiplas fotos por memória" (V2) foi
  entregue no MVP com teto de 5; mapa interativo marcado como feito.
- [`10-localizacao.md`](10-localizacao.md): registrado que o `timezone` passou a
  ser resolvido por `geocoding.resolve_timezone` com `tzfpy` (4,5 MB), preferido
  ao `timezonefinder` (53 MB) pelo peso da imagem no free tier.

### Código
- O `timezone` da memória **deixou de nascer nulo**: o `timezone_resolver` já era
  injetável e testado, mas nenhum resolvedor era ligado na composição. Agora
  `get_provider()` entrega o resolvedor offline, e o mesmo vale para o backfill.
  Guarda de regressão incluída — inclusive contra inverter latitude e longitude,
  já que a biblioteca recebe `(lng, lat)` e o contrato interno é `(lat, lng)`.

> Divergência que **permanece** (registrada de propósito, não resolvida): o título
> da memória continua obrigatório enquanto o texto é opcional, ao contrário do que
> o produto pede. Inverter isso muda o contrato da API e afeta os dois clientes —
> é decisão de produto, não limpeza de documentação.

## 2026-08-29

### Documentação
- README: nova seção **Integração contínua** e badge do workflow; `.github/` na
  árvore do projeto; contagem de testes corrigida (218 no backend, 86 no app).

### Código
- Integração contínua no GitHub Actions (`.github/workflows/ci.yml`): 218 testes
  de backend contra `postgis/postgis:16-3.4` e 86 do app com
  `flutter analyze --fatal-infos` + `flutter test`, em paralelo.
- O trabalho de backend também roda `upgrade head` → `downgrade base` →
  `upgrade head` em banco limpo. Isso fecha o **critério 1** de
  [`10-localizacao.md`](10-localizacao.md), que exigia o downgrade validado em
  banco limpo e nunca tinha sido conferido: o ciclo passa e as 8 tabelas voltam.
- Paginação por keyset adotada pelo cliente Flutter, percurso real por GPS
  (gravação, listagem e remoção) e edição de jornada — o `PATCH /journeys/{id}`
  existia desde julho sem nenhum chamador.

> Regra do backend registrada ao implementar a edição: `null` **não** limpa um
> campo no `PATCH` — o repositório guarda cada atribuição com `is not None`, e
> apagar um texto exige enviar string vazia. Mandar `null` falha em silêncio.

### Código (música)
- Migração `0011_memory_music` e a fatia vertical completa: a memória passa a
  guardar **a canção que estava tocando**. O app já sabia buscar faixas desde
  julho — o `MusicProvider` e o adapter do iTunes existiam — e não tinha onde
  salvá-las.
- Guardamos o **snapshot** da faixa, não uma referência ao catálogo. Catálogos
  mudam de política, tiram faixas do ar e reorganizam ids; a lembrança de qual
  música tocava não pode depender de um terceiro continuar existindo.
- A API **não consulta provedor nenhum**: recebe o que o app obteve. Buscar
  exige rede e é do provedor; guardar é nosso. Assim o app troca de catálogo
  (Apple Music, Spotify) sem que a API precise saber.
- A mesma faixa não entra duas vezes na mesma memória — regra que o `MusicTrack`
  do app já expressava no `operator ==` e que agora o banco garante, por índice
  único parcial. Parcial de propósito: remover e reanexar continua permitido.
- `GET /me/profile` ganhou `stats.tracks`, fechando o "56 músicas" do cartão do
  viajante previsto na [`09-perfil.md`](09-perfil.md).

- A tela veio junto: busca no catálogo pela folha inferior, a trilha no detalhe
  da lembrança e a remoção. O seam que existia desde julho fecha aqui — o app
  deixa de ter um provedor de música que não leva a lugar nenhum.
- A busca **espera a digitação pausar** (350ms). Sem isso, escrever "caetano"
  dispararia sete requisições a um catálogo público para uma única intenção.

## 2026-10-10

### Regras de negócio
- O **título da memória passou a ser opcional**, resolvendo a divergência aberta
  desde 28/06. A intenção de produto sempre foi essa; a API é que exigia
  `title` não vazio. Exigir um rótulo para poder guardar uma lembrança trocava o
  conteúdo pelo índice: a pessoa era obrigada a inventar "Praia" e podia deixar
  em branco justamente o que aconteceu.
- Ausente é `""`, não nulo — a mesma convenção do texto. Dois jeitos de dizer
  "não tem" viram dois caminhos em cada tela, e a coluna é `NOT NULL`, então
  nenhuma migration foi necessária.
- No `PATCH`, string vazia **apaga** o título e `null` não mexe nele, como já
  valia para os demais campos.
- A mudança é **retrocompatível**: a API passou a aceitar mais, não a exigir
  mais. Nenhum cliente existente quebra.
- Continua em aberto a outra metade da divergência: o **texto** deveria ser o
  núcleo da memória e segue opcional. Torná-lo obrigatório quebraria os dois
  clientes e invalidaria o acervo já gravado com `text = ""` — decisão que
  precisa vir antes do código.

### Documentação
- [`01-regras-negocio.md`](01-regras-negocio.md): título registrado como
  opcional; a entrada do texto passou a explicar o que falta decidir.
- [`03-api-planejada.md`](03-api-planejada.md): o exemplo de criar memória agora
  diz que obrigatórios mesmo são o local e o `occurred_at`.
- README: a linha do título saiu de **Divergencias conhecidas**; a do texto
  ficou, reescrita.

## 2026-10-11

### Documentação
- Criado [`11-convencoes.md`](11-convencoes.md), o primeiro documento voltado a
  quem vai **contribuir** com o código e não a quem vai entender o produto.
  Reúne as convenções que o `flutter analyze` aprova e o `pytest` deixa passar —
  as que falham em silêncio. Até aqui elas só existiam em docstring de arquivo,
  em corpo de commit e em teste escrito **depois** de a armadilha morder.
- O critério de entrada está escrito no próprio documento, para a lista não virar
  depósito de preferência de estilo: o analisador e a suíte não veem a regra,
  errar não produz erro, e alguém já errou.
- Cobertas: `null` que não limpa no `PATCH` · longitude primeiro no PostGIS e a
  inversão na fronteira com o `flutter_map` · `occurred_at` como dia em UTC ·
  design system sobre `package:flutter/widgets` · `EditableText` nos testes de
  widget · caixa alta do `SJButton` · o contrato de listagem · as duas costuras
  manuais do `conftest.py` · `auth_headers` como fábrica · README sem acento ·
  português no comentário e inglês no identificador · ausência de formatador ·
  domínio puro fora do Flutter · a versão do Flutter presa de propósito.

> Três coisas foram encontradas ao conferir cada regra contra o código, e ficam
> registradas aqui porque **não** foram corrigidas (nenhuma é mudança de
> documentação):
>
> - `_TABLES`, no `backend/tests/conftest.py`, nomeia sete das nove tabelas.
>   `memory_music` e `password_reset_tokens` só são limpas entre os testes
>   porque o `TRUNCATE ... CASCADE` alcança quem tem FK para as listadas. Uma
>   tabela nova sem esse vínculo vazaria linhas de um teste para o outro, em
>   silêncio.
> - O docstring de `app/core/pagination.py` diz que o contrato de cursor é
>   "idêntico em todas as rotas de lista". Hoje só `GET /memories` e
>   `GET /journeys` paginam; `GET /journeys/{id}/memories` e
>   `GET /journeys/{id}/tracks` devolvem a lista inteira. É a intenção, não o
>   estado.
> - O README diz que o app principal pede Dart >= 3.12.2; o `pubspec.yaml` pede
>   `^3.10.9` desde o commit que baixou a restrição para a versão realmente
>   necessária. A contagem de testes do backend no README (214) também ficou
>   para trás.

## 2026-10-11 (2)

### Decisão de produto
- **O app Expo foi removido.** `mobile/`, o smoke Playwright em `e2e/` e o
  harness do Playwright na raiz saíram do repositório — 89 arquivos, cerca de
  14.700 linhas.
- O motivo não foi abandono, foi redundância verificada: o Flutter tem **todas**
  as telas que o Expo tinha e mais quatro que ele nunca teve (Perfil, Edição de
  perfil, Configurações e Edição de jornada). Não havia uma única tela só no
  Expo. E `app_flutter/web/` já está configurado, então o último argumento a
  favor dele — ser o caminho web — também não valia mais.
- O que ele cobrava: 6.052 linhas sem nenhum teste, oito endpoints atrás
  (incluindo Perfil e Música inteiros) e trabalho dobrado a cada mudança de
  contrato da API. Só em outubro isso custou duas vezes — o título opcional e a
  paginação por cursor.
- Removido inteiro em vez de marcado como não mantido. Código deprecado continua
  aparecendo em busca, continua confundindo quem lê, e continua convidando o
  próximo a "só atualizar aquela telinha". O histórico do git guarda o que foi.
- O smoke do Playwright saiu junto porque existia para verificar que o Expo Web
  subia; sem o Expo ele não testa nada. O harness pode voltar apontado para o
  build web do Flutter se um dia houver E2E de verdade.

### Consequência inesperada, e boa
- Tirar o Expo fez a verificação de paridade acusar cinco rotas sem cliente.
  Quatro eram **falso positivo**: o ciclo de vida da jornada é chamado por um
  ajudante que monta o caminho em tempo de execução, então a string nunca
  aparece inteira no arquivo — o Expo mascarava isso porque escrevia os caminhos
  literais. O check passou a declarar esses caminhos montados, com dois testes
  que cobram a declaração nas duas pontas.
- A quinta era **real**: `GET /journeys/{id}/memories` não tem cliente nenhum.
  Parecia alcançada porque o Expo declarava um wrapper que nenhuma tela chamava.
  Entrou em `KNOWN_GAPS` com o motivo: o detalhe da jornada já devolve `points`
  com as memórias, e é por ali que o app lê.

### Documentação
- README, [`01-regras-negocio.md`](01-regras-negocio.md),
  [`04-decisoes-tecnicas.md`](04-decisoes-tecnicas.md),
  [`06-roadmap.md`](06-roadmap.md), [`08-design-system.md`](08-design-system.md)
  e [`11-convencoes.md`](11-convencoes.md) deixaram de falar em dois clientes.
- O roadmap perdeu o item de V2 "Paridade do app Expo com o Flutter".

## 2026-10-12

### Design system
- [`08-design-system.md`](08-design-system.md) ganhou o **livro** (`SJBook`) na
  anatomia dos componentes: capa de couro, duas páginas e a **folha** como
  primitiva única — a mesma peça que serve à capa que abre e à página que vira.
- Registrado o limite de **720pt**: acima disso o livro abre em folha dupla,
  abaixo mostra uma página por vez. Duas páginas num celular dariam ~170pt cada,
  e campo de formulário nenhum cabe ali.
- Registrada também a regra que não é estética: **em repouso a folha não carrega
  matriz nenhuma**. Perspectiva é transformação não afim, e sob ela o
  `ensureVisible` que o foco do teclado dispara sozinho não converge — a página
  trava rolando. O estado em que se digita precisa ser livre de transformação.

### Movimento
- A escala de durações ganhou um degrau acima de `page`: **cerimônia (900ms)**,
  com regra própria escrita no doc. As outras durações são de transição — o
  tempo é custo e o alvo é não ser notado. Cerimônia é o oposto: a animação que
  o usuário DEVE ver acontecer. Hoje tem um só dono, a abertura do cadastro, e o
  doc diz explicitamente que ela não serve para navegar.

## 2026-10-12 (2)

### A porta
- [`08-design-system.md`](08-design-system.md) ganhou a seção **"A porta
  (login)"** com a composição de referência: pôster acima de 900pt (arte
  sangrando, promessa sobre a foto, cartão de papel à direita) e coluna única
  abaixo disso.
- Registrada a regra do véu sobre foto: ele é `shadow`, nunca `bgDeep` — no modo
  claro o `bgDeep` é creme, e creme sobre creme não escurece nada.
- Registrada a exceção de cor do app: sobre a foto, a tinta é sempre a clara
  (`sjDark.ink`), independente do modo ativo. O papel quente some contra o céu
  da ilustração.
- Registrada a política para o que o desenho pede e o produto não tem:
  **desenhado e desligado, com "em breve" escrito** (hoje, entrar com Google).
  O que não existe de verdade — rota inventada na barra — simplesmente não
  aparece.

### Ornamentos
- **Carimbo** (`SJSeal`) e **herbário** (`SJSprig`) entraram na anatomia dos
  componentes. Os dois sangram para fora da borda de propósito: ornamento que
  respeita a margem vira ilustração, e deixa de ser marca d'água.

### Livro
- Registrado o teto de proporção: **1,35:1** aberto, **0,70:1** por página. Sem
  teto, numa janela alta o livro ocupava tudo e ficava quase quadrado — e um
  quadrado lê como dois painéis, não como livro aberto.

## 2026-10-12 (3)

### Aparência
- O **modo escuro foi ligado**. Os dois esquemas existiam desde sempre, a
  galeria desenhava os dois e o controlador já sabia salvar a preferência — só
  que `main.dart` fixava `ThemeMode.light`. Metade do design system estava
  escrita e fora do produto.
- Registrado em [`08-design-system.md`](08-design-system.md) o detalhe que faz
  a diferença entre ligar e PARECER ligar: trocar só o `themeMode` mudaria o
  Material por baixo e deixaria as telas cremes, porque `SJTheme.of(context)`
  cai num fallback claro quando ninguém provê o esquema. Quem provê é o
  `builder` do `MaterialApp`.
- Configurações › Aparência deixou de ser mostrador e virou escolha: os três
  modos (papel, atlas, automático) como grupo de rádio, persistido. O selo
  "Em uso" saiu — selo diz o que É, rádio diz o que se PODE escolher.
- O automático mostra em qual dos dois está ("Agora: atlas (escuro)"): é a
  única escolha cujo nome não revela o resultado.

## 2026-10-25

### Performance
- **O CanvasKit vinha do CDN do Google a cada carga.** O `flutter build web`
  copia uma versão local de 7MB para dentro do build e, por padrão, a ignora:
  o bootstrap aponta para `www.gstatic.com`. Medido no navegador, mesmo
  recurso: `canvaskit.wasm` caiu de **3.088ms para 232ms**, e o `load` da
  página, de **3.136ms para 144ms**. O `main.dart.js`, com 3MB, sempre baixou
  em 54ms — bytes nunca foram o gargalo. De brinde, o app passou a abrir sem
  internet.
- A correção é um flag no comando de build (`--no-web-resources-cdn`), e isso
  a torna frágil por natureza: quem rodar o build sem ele traz os três
  segundos de volta, em silêncio. Por isso o comando passou a estar escrito no
  README, e não só na memória de quem fez.
- **Um filtro de cor por telha do mapa.** A base cartográfica era tingida pelo
  `tileBuilder`, ou seja, um `ColorFiltered` para CADA telha — vinte a quarenta
  `saveLayer` por quadro enquanto o mapa é arrastado, que é exatamente quando
  não há quadro sobrando. O motivo alegado era não tingir pins e rastros, e ele
  não se sustentava: essas camadas são IRMÃS da camada de telhas na lista de
  filhos do `FlutterMap`, nunca filhas dela. Agora o filtro é um só, por fora
  da camada inteira, com dois testes prendendo a forma da árvore.

## 2026-11-01

### Correção
- **A foto de memória não cabia no próprio teto.** O backend corta o upload em
  5MB e devolve 413; o avatar e a capa de jornada sempre encolheram antes de
  enviar, mas a foto da memória ia em resolução cheia — nas duas telas que a
  escolhem. Na prática o caminho mais percorrido do produto falhava para a
  foto comum de celular (3 a 12MB) e só funcionava para captura de tela.
- Os limites passaram a morar num ponto único (2048px no maior lado,
  qualidade 85 — tipicamente 400KB a 1,2MB), porque duas cópias de um limite é
  um limite que será corrigido pela metade.
- O defeito era invisível porque ninguém observa os ARGUMENTOS de um seletor
  de imagem: a tela compila, a galeria abre e devolve arquivos do mesmo jeito.
  Agora cinco testes observam, inclusive o corte para a galeria que ignora o
  limite que recebeu.

## 2026-11-02

### Entrar com o Google (backend)
- A rota `POST /auth/google` existe e funciona. O cliente faz o fluxo com o
  Google, recebe um `id_token` e manda só isso: **nada do que ele afirma sobre
  si é aceito**, porque o token é um JWT assinado pelo Google e é a assinatura
  que vale.
- São conferidos a assinatura (contra as chaves públicas do Google), o `aud`,
  o `iss`, o `exp` e o `email_verified`. O `aud` é o que impede um token
  emitido para OUTRO aplicativo de ser aceito aqui — sem essa checagem,
  qualquer desenvolvedor entraria como qualquer pessoa.
- `GOOGLE_CLIENT_ID` aceita **vários separados por vírgula**: o Google emite um
  client id por plataforma e o `aud` é o de quem pediu. Com um valor só, a web
  entraria e o celular seria recusado como "token inválido" — mandando a pessoa
  depurar o lugar errado.
- Sem a variável configurada a rota responde **503**, não 401. O recurso não
  existe naquele ambiente, e dizer "token inválido" seria mentira útil para
  ninguém.

### O vínculo, que é a regra que importa
- Três caminhos, nesta ordem: `sub` conhecido → entra; e-mail já cadastrado →
  **vincula**; nenhum dos dois → cria. O segundo é o que impede a segunda
  conta: quem usava e-mail e senha e um dia toca em "entrar com Google" cai no
  próprio cadastro, com as próprias memórias, e não num perfil vazio de mesmo
  nome.
- O vínculo é pelo `sub` do Google, **nunca pelo e-mail** — o e-mail de uma
  conta Google pode mudar de dono dentro de um domínio; o `sub` não.
- A corrida entre dois logins simultâneos é resolvida pelo banco: `google_sub`
  e `email` são UNIQUE, e o perdedor relê a linha do vencedor em vez de
  devolver erro a quem só tocou no botão duas vezes.

### Schema
- Migration `0012_google_identity`: `users.google_sub` (único, nulo) e
  `users.password_hash` passa a aceitar NULL.
- Senha nula é deliberado. Guardar um hash inventado para quem entrou pelo
  Google manteria o NOT NULL ao custo de uma linha que MENTE — pareceria ter
  senha, e o próximo a ler a tabela trataria como se tivesse. O login por senha
  recusa essas contas com a **mesma mensagem genérica** de credencial inválida:
  responder "esta conta usa Google" confirmaria que o e-mail existe.

### Paridade
- A rota entrou em `KNOWN_GAPS` com o motivo escrito: o backend ficou pronto
  antes do cliente de propósito, porque é a parte que dá para construir e
  testar sem credencial do Google Cloud e sem build assinado de aparelho. O
  botão no app segue desenhado e desligado até existir um client id.

## 2026-11-08

### Entrar com o Google (app)
- O botão deixou de ser desenho e virou botão — **quando há client id**. Sem
  `--dart-define=GOOGLE_CLIENT_ID` ele continua desenhado e desligado, com "em
  breve" escrito, que é o estado honesto de quem ainda não criou a credencial.
  Ligar antes seria um botão que não faz nada.
- A web usa o botão renderizado pelo **próprio Google**: eles não autorizam o
  fluxo a sair de um botão de terceiro, e a resposta chega por evento em vez de
  pelo retorno da chamada. Fora da web o fluxo é direto e o botão é o nosso, no
  design system. A diferença fica isolada num import condicional; a tela de
  login não sabe em qual dos dois está.
- Cancelar **não é erro**. Fechar a janela do Google é decisão de quem estava
  entrando, e virar mensagem vermelha diria que ela errou quando só mudou de
  ideia.
- O token vai direto para `POST /auth/google` e quem decide qualquer coisa é o
  backend — inclusive se a conta é nova ou se é um vínculo com um cadastro
  antigo. A tela não precisa saber a diferença.

### Testabilidade
- O SDK do Google entrou atrás de uma interface, pelo mesmo motivo do
  `MusicProvider`: o fluxo real não roda em teste. Sem a fronteira, nada do que
  a tela faz com o token — sucesso, cancelamento, falha, plataforma sem suporte
  — seria observável, e o botão seria o pedaço do app que ninguém exercita até
  alguém tocar nele em produção. São oito testes.

## 2026-11-10

### Fases da vida — a fundação
- Nova tabela `life_phases` e vínculo **opcional** com memórias e jornadas.
  Uma fase é um capítulo que a pessoa reconhece na própria história: infância,
  recomeços, novos caminhos.
- CRUD completo em `/life-phases`, isolado por usuário — id de outra pessoa e
  id inexistente respondem igual (404), para quem sonda ids não descobrir
  quais existem.
- Detalhe de contrato que foge ao padrão da casa: no `PATCH` daqui, `null`
  **limpa** o campo. No PATCH de jornada, `null` é no-op silencioso. A
  diferença é deliberada: uma fase que ganhou data de fim por engano precisa
  poder voltar a ser a fase em curso, e para data não existe o truque da
  string vazia.

### O que o schema se recusa a impor
- **Sem lista predefinida.** O banco nasce vazio de fases. Os exemplos vivem
  no texto do produto, nunca como linhas semeadas.
- **Sem restrição de sobreposição.** "Vida adulta" e "recomeços" convivem;
  exigir períodos disjuntos transformaria memória em planilha.
- **Período aberto dos dois lados.** Nem toda pessoa sabe quando a infância
  virou outra coisa, e pedir data de fim para salvar seria pedir que ela
  decretasse o próprio presente no passado.
- **Cor da paleta, não hexadecimal.** Cor livre quebraria o contraste em um
  dos dois modos — o que é legível no papel quente some no atlas noturno.

### E a regra que vale o arquivo de teste
- Apagar uma fase **solta** o que apontava para ela. A etiqueta é descartável;
  a lembrança não. Perder uma memória por causa da categoria seria a ordem
  errada de importância.

### Paridade
- As cinco rotas entraram em `KNOWN_GAPS` com o motivo: a fase só faz sentido
  quando houver tela para criar e FILTRAR por ela, e essa é a próxima fatia.

## 2026-11-10

### Deploy para testers
- Criado `12-deploy.md`: o passo a passo, na ordem, para pôr o app no ar de graça — API no
  Render, banco e fotos no Supabase, app web no Cloudflare Pages, ping no UptimeRobot — e as
  contas dos testers pelo script de seed.
- Registrado por que o ping vai no `/health/ready` e não no `/health`: um só monitor impede o
  Render de dormir **e** o Supabase de pausar, porque o `/health/ready` consulta o banco.
- Registradas as armadilhas da `DATABASE_URL` do Supabase: prefixo `postgresql+psycopg://`,
  Session pooler (a conexão direta é só IPv6) e senha sem caractere especial.
- Registrado que nenhum dos dois deploys publica commit com CI vermelho: o Render usa
  `autoDeployTrigger: checksPass` e o app web só é publicado depois do CI na `main`.
- Registrado que API e banco ficam na **mesma região** (Render em Virginia, Supabase em East US):
  o Render não tem região no Brasil, e com o banco em São Paulo cada consulta cruzaria o
  continente. A região não muda depois de criado o serviço, por isso o guia a fixa na criação.
- Registrado o limite de conexões do pooler do Supabase grátis e o pool pequeno que o
  `render.yaml` define (`DB_POOL_SIZE`, `DB_MAX_OVERFLOW`).
- As credenciais de produção usadas pelos scripts locais passaram a ficar em
  `backend/production.env` (fora do git), lidas por `scripts/with_production_env.sh`, em vez de
  coladas na linha de comando. O guia ganhou a checagem do banco (`scripts.check_database`) como
  critério de "pronto" do passo do Supabase.
- Corrigida a resposta esperada do `/health/ready` no guia: é `{"status":"ready"}`.

## 2026-11-12

### Fases da vida — o vínculo e a lente
- A metade que faltava. O backend tinha a tabela e o CRUD, mas nenhuma rota de memória ou
  jornada aceitava `life_phase_id`: a coluna existia e não havia como preenchê-la. Agora
  `POST`/`PATCH` de memória e de jornada aceitam o campo e a leitura o devolve.
- O vínculo passa por uma porta só, `life_phase_service.owned_phase_id`: a fase precisa ser
  ativa e da mesma pessoa. A FK sozinha aceitaria a fase de outra pessoa, porque ela existe.
  Fase alheia, apagada ou inexistente no corpo responde **422** — o recurso da URL existe, quem
  não serve é um valor do corpo.
- No PATCH de memória e de jornada, `life_phase_id: null` **solta** a fase. É a única exceção
  ao "null não mexe" desses dois PATCHes, pelo mesmo motivo do PATCH de fases: um id não tem
  string vazia que o substitua.

### A regra da lente
- `?life_phase_id=` em `/memories`, `/journeys` e `/map`. A memória está na fase quando foi
  marcada nela **ou** quando está numa jornada marcada nela; a jornada, quando foi marcada ou
  quando alguma memória dela foi. Quem marca "Intercâmbio" na jornada não deveria ter de marcar
  foto por foto para encontrá-las.
- A herança desce da jornada para a memória e para aí — uma memória marcada não puxa as irmãs.
  E ela é calculada na consulta, nunca gravada: tirar a memória da jornada a tira da fase sem
  nenhuma escrita a mais, e a leitura da memória continua dizendo só onde ela foi marcada.
- No mapa a jornada vem inteira, rastro e todos os pins, pela mesma razão do `bbox`: um rastro
  cortado no meio contaria um caminho que não aconteceu.
- A fase não é deduzida das datas. O período é contexto que a pessoa escreve; usá-lo para
  recortar sozinho poria na fase o que ela não pôs.
- Fase alheia ou apagada no filtro responde **404**, como o `?journey_id=` do mapa. Uma lista
  vazia seria uma resposta plausível e esconderia o id errado.

### No app
- **Perfil → Fases da vida**: criar, editar e apagar. Só o nome é obrigatório; a cor é um dos
  cinco papéis da paleta; as datas ficam em aberto e cada uma tem como voltar a ficar em branco
  — esvaziar o fim reabre a fase (manda `null`). Apagar pede confirmação e diz o que não
  acontece: as memórias ficam.
- O seletor de fase nos formulários de memória e de jornada, e a etiqueta da fase nos detalhes.
  Na memória criada dentro de uma jornada o seletor não aparece: ela já entra na fase da
  jornada pela regra da lente.
- A lente na timeline e no atlas. Vazio com lente tem texto próprio ("nada guardado nesta fase
  ainda") e a saída de volta para a vida toda; tocar de novo na fase escolhida também volta.
- Quem nunca criou uma fase não vê lente nem seletor: a timeline, o atlas e os formulários
  ficam exatamente como eram.
- As fases vivem num `PhaseStore` compartilhado. A timeline e o atlas são abas e não recarregam
  ao voltar; sem o notificador, a fase criada não apareceria na lente, e a fase apagada
  continuaria filtrando por um id que devolve 404. A lista é esquecida ao sair da conta.

### Paridade
- Saíram de `KNOWN_GAPS` as rotas que o app passou a chamar. Fica `GET /life-phases/{id}`,
  com o motivo escrito: a lista já traz cada fase inteira e o formulário abre com ela na mão.

## 2026-11-14

### Revisão geral do backend
Uma leitura de ponta a ponta atrás de defeitos reais — não de estilo. Cada achado foi
confirmado no código, corrigido e ganhou um teste que falha sem a correção.

**Segurança**
- **Teto por e-mail no rate limit** (`AUTH_RATE_LIMIT_EMAIL_ATTEMPTS`, padrão 20 por janela)
  no login e na recuperação de senha. Com `--forwarded-allow-ips='*'` o uvicorn usa a entrada
  mais à esquerda do `X-Forwarded-For`, que o cliente escreve: trocando o IP a cada tentativa,
  os baldes por conta e por IP nunca enchiam. O balde por e-mail não lê IP nenhum. Acertar a
  leitura do IP fica para quando der para ver o `X-Forwarded-For` real do Render.
- **STARTTLS confere o certificado.** Sem contexto, o `smtplib` aceitava qualquer um: quem
  estivesse no meio do caminho leria a senha do SMTP e os links de recuperação.
- **Google: e-mail já ligado não troca de dono.** O passo de vínculo por e-mail sobrescrevia o
  `google_sub` de quem já tinha um. Um e-mail de domínio reatribuído a outra pessoa (outro
  `sub`) entregaria a ela as memórias da anterior. Agora responde **409**.

**Correção**
- Mudar uma memória de lugar deixava o lugar antigo para sempre ("Fortaleza" depois de ir para
  Lisboa), e o `geocoded_at` preenchido a mantinha fora do backfill.
- `POST /journeys/{id}/memories` não geocodificava e ainda exigia título — a cópia do contrato
  tinha ficado para trás quando o título virou opcional; memória sem título criada dentro de
  uma jornada voltava 422.
- Datas sem fuso: nas fases da vida, misturar uma data com fuso e outra sem dava **500**
  (TypeError ao comparar o período). No PATCH de jornada, eram lidas no fuso da sessão do
  banco. Agora as duas viram UTC, como no resto da API.
- O PATCH de jornada aceitava fim antes do início, que o create e o finish recusam. Agora
  confere contra o que já está gravado e responde **422**.
- Trocar a senha numa conta que só entra pelo Google dava **500**. Agora **409** com o caminho:
  "Esqueci minha senha".
- A distância percorrida do perfil somava trechos e jornadas apagados, e procurava os pontos
  numa coluna sem índice. Agora parte dos trechos ativos.
- A foto do perfil morria em 1 MB (o teto de JSON) em vez dos 5 MB das outras fotos.
- O intervalo mínimo do Nominatim nunca valia (um provedor novo a cada chamada). Agora é um
  por processo, com a vaga reservada sob trava.
- Toque duplo em "anexar música" dava **500** no segundo POST. Agora **409**, como o caminho
  sem corrida.

**Limpeza**
- As constantes HTTP deprecadas no Starlette 1.6 (`HTTP_422_UNPROCESSABLE_ENTITY`,
  `HTTP_413_REQUEST_ENTITY_TOO_LARGE`) trocadas pelos nomes novos; os códigos não mudam.
- Imports e variável sem uso nos testes; um teste de imutabilidade que aceitava qualquer
  exceção passou a exigir a do dataclass congelado.

### Ataque simulado
Um ataque contra uma cópia local da API em modo produção (mesmo `start.sh` do Render, 2
workers, banco descartável, geocoding, storage e SMTP desligados): 112 golpes em acesso a
dados alheios, tokens forjados, força bruta com IP forjado, injeção, corpos absurdos, corridas
e inundação. Na primeira rodada, 96 resistiram e 5 defeitos apareceram; na segunda, depois das
correções abaixo, 107 resistiram, nenhum quebrou, e o servidor não deu um único 500.

- **Data fora do intervalo envenenava a conta.** Uma memória do ano 1 era gravada e depois não
  voltava: lida no fuso da sessão do banco, caía antes do ano 1. A criação respondia 500 com a
  memória já gravada, e a timeline e o mapa da dona davam 500 para sempre. As datas de entrada
  agora ficam entre os anos 1000 e 2999 (`AwareUtcDatetime`), conferidas antes e depois da
  conversão para UTC.
- **`NaN`, `Infinity` e `1e400` davam 500.** A validação recusava, mas o 422 repete o valor
  recebido e ele não cabe em JSON. O tratador de erro de validação devolve esses valores como
  texto, no mesmo formato de sempre (`app/core/error_handlers.py`).
- **Caractere NUL no texto dava 500.** O Postgres não o guarda. O `DataError` vira 422, a
  transação é desfeita e o log registra só o tipo do erro, nunca o valor.
- **Token antigo sobrevivia à troca de senha no mesmo segundo.** O `pcat` é em segundos
  inteiros; trocar a senha no mesmo segundo em que ela foi definida empatava os dois valores. A
  troca agora sempre avança pelo menos um segundo inteiro (`GREATEST(now(), segundo anterior +
  1s)`).
- **Corpo em pedaços acima do teto dava 400.** O FastAPI engole a exceção levantada durante a
  leitura do corpo e responde 400; o middleware agora troca essa resposta pelo 413.

Ficaram como observação, sem correção: o limite de tentativas é por processo (com 2 workers,
quem abre conexões novas pode chegar a ~40 por janela), faltam cabeçalhos de segurança
(`nosniff`, `X-Frame-Options`, `Referrer-Policy`, HSTS) e o servidor se identifica como
`uvicorn`.

## 2026-11-14 (2)

### Regras de negócio: o documento cobre o produto inteiro
- [`01-regras-negocio.md`](01-regras-negocio.md) falava de usuários, memórias, jornadas,
  pontos soltos, imagens e mapa. Ganhou o que já era regra no código e não estava escrito:
  conta e acesso (senha, revogação, Google, limites de tentativa), perfil (`@username`, foto,
  contagens), música, percurso GPS e fases da vida — cada item com **(impl.)** só depois de
  conferido no código e coberto por teste.

### Regras novas
- **Memória não pode ser de um dia que ainda não chegou.** O seletor do app já não deixava
  escolher amanhã; o backend aceitava de qualquer outro cliente. A folga de 36 h cobre o fuso
  — o "hoje" de UTC+14 está ~26 h à frente do relógio do servidor. A regra é só da memória:
  jornada pode estar planejada, fase pode ter fim marcado, e a data de um ponto de GPS não é
  conferida contra o relógio do servidor (um celular adiantado não pode custar um trecho).
- **Um nome de fase por pessoa**, sem diferenciar maiúsculas, entre as ativas: duas
  "Faculdade" eram duas etiquetas iguais na lente. **409** com o nome; o de uma fase apagada
  fica livre. Garantido também por índice único (migration 0015), que renomeia com sufixo
  " (2)" os repetidos que já existirem.

### Divergência fechada
- **`memories.image_path` saiu** (migration 0014). A 0003 já tinha copiado as fotos dela para
  `memory_images`, e nada mais a escrevia. A migration copia de novo o que tiver sobrado
  antes de soltar a coluna — nenhuma foto se perde.

### Testes
- O banco de teste agora é **recriado do zero a cada sessão**. `create_all` só cria o que
  falta: num banco de teste antigo, índice ou coluna nova nunca chegava, e a suíte local
  testava um schema velho — foi assim que o índice único de fase "passou" num teste sem
  existir. A suíte se recusa a derrubar tabelas num banco cujo nome não termine em `_test`.

### Segurança e infraestrutura: o que o ataque deixou como observação
- **Cabeçalhos de segurança em toda resposta** (`app/core/security_headers.py`): `nosniff`,
  `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`; em produção também HSTS e
  `Content-Security-Policy: default-src 'none'`. Fora de produção ficam de fora — o HSTS
  prenderia o navegador num HTTPS que o localhost não tem, e a CSP apagaria o `/docs`.
- **O servidor não se anuncia** (`--no-server-header`).
- **Um processo** por padrão (`WEB_CONCURRENCY` sobrepõe). No plano grátis do Render o
  segundo processo não trazia CPU, só RAM — e partia ao meio o que mora em memória: o teto de
  tentativas de login era ~40 por janela em vez de 20, e o intervalo do Nominatim virava ~2 por
  segundo. O pool passou a 5 + 5, mantendo o teto de 10 conexões no pooler do Supabase.
- **Contêiner sem root** (usuário `app`, uid 10001) e sem gravar `.pyc`.
- **Apagar uma fase enquanto alguém marca uma memória nela.** O DELETE soltava os vínculos
  antes de a outra transação gravar o dela, e a memória terminava apontando para uma fase
  apagada. Agora quem marca trava a fase em modo compartilhado e quem apaga em modo exclusivo:
  um espera o outro, e o resultado é sempre coerente (a memória solta, ou um 422).
- **Models e migrations dizem o mesmo.** O índice de leitura dos pontos de GPS ganhou o `id`
  que o model sempre declarou (migration 0016), e o índice de `@username` sem caixa, que
  existia só na 0010, entrou no model. O CI agora roda `alembic check` depois das migrations,
  com a tabela do PostGIS fora da comparação.
- **`httpx2`** no `requirements-dev.txt`: é o cliente que o `TestClient` do Starlette 1.6 pede.
  A suíte roda sem nenhum aviso de deprecação.

### App: a lente chega à estante de jornadas
- **Jornadas** ganham a mesma lente da timeline e do atlas: entram as marcadas na fase e as
  que têm alguma memória dela. Vazio com lente tem texto próprio e a saída de volta para a vida
  toda; a fase apagada noutra tela devolve a estante inteira.
- **Criar com a lente ligada já marca a fase.** Uma jornada aberta pela estante filtrada, ou
  uma memória registrada pela timeline filtrada, nasce na fase que a pessoa estava lendo — antes
  ela criava o momento e ele sumia da lista que ela acabou de deixar. O seletor continua
  ali para trocar ou tirar.

## 2026-11-14 (3)

### App: menos travado, mais vivo
- **Trocar de aba recriava as duas abas.** O shell envolvia o `IndexedStack` num
  `AnimatedSwitcher` com uma chave que mudava a cada toque — e chave nova é árvore nova: a
  timeline e o atlas eram destruídos e recriados, relendo tudo da rede, voltando ao esqueleto
  e redesenhando o mapa do zero (com dois mapas na tela durante o fade). Medido num teste: em
  quatro trocas, a timeline era lida 5 vezes; agora, uma. A pilha é sempre a mesma, só a aba
  que entra faz o fade, e a escondida tem as animações pausadas (`TickerMode`).
- **As telas se atualizam sozinhas quando algo muda.** Com as abas guardando o estado, a
  memória criada pelo botão central precisava aparecer por baixo: o cliente da API avisa a
  cada escrita bem-sucedida (`Api.changes`), e timeline, atlas, jornadas e perfil releem em
  silêncio — o conteúdo antigo fica até o novo chegar. Voltar de uma tela sem gravar nada não
  custa mais uma ida à rede.
- **Fotos que não pesam** (`widgets/sj_image.dart`). As URLs vêm assinadas, com um token novo
  a cada resposta, e o cache de imagens usava a URL inteira como chave: cada recarga baixava e
  decodificava de novo todas as fotos. Agora a chave é o arquivo. E cada foto é decodificada
  no tamanho em que aparece — uma miniatura de 84 pt não decodifica mais a foto de 2048 px
  inteira. O visualizador de tela cheia continua em resolução completa.
- **Perfil e estante de jornadas abrem preenchidos**, com a última versão vista nesta sessão,
  e trocam pela nova quando ela chega. O cache some ao sair ou trocar de conta.
- **Trocar de lente não vira esqueleto**: a lista anterior esmaece até a nova chegar.
- **A timeline mede menos.** Cada entrada usava `IntrinsicHeight` (o layout medido duas vezes
  por entrada, a cada quadro de rolagem); a espinha agora é desenhada por trás do conteúdo. E
  a contagem de memórias por ano era um laço dentro do laço — 10 mil leituras de data por
  reconstrução com 100 memórias.
- **Surgimento**: memória ou capítulo que chega de novo aparece com um fade curto; o que já
  estava na tela não repete a animação, e "reduzir movimento" no aparelho a desliga.

### CI: o `alembic check` comparava as extensões do PostGIS
- O check entrou no CI e falhou na primeira rodada: a imagem `postgis/postgis` instala também
  o geocodificador TIGER e a topologia, com dezenas de tabelas (`county`, `addr`, `faces`,
  `topology`…) nos schemas do `search_path`, e o check as via como "a mais". O Postgres local,
  sem essas extensões, passava. Agora o `alembic/env.py` pergunta ao catálogo
  (`pg_depend`, `deptype = 'e'`) quais tabelas pertencem a extensões e as deixa fora da
  comparação — com os índices delas. Diferença de verdade nas tabelas da app continua
  reprovando.
- A consulta ao catálogo roda numa conexão só dela: na mesma conexão das migrations ela abria
  uma transação implícita, e o Alembic não fazia o commit — as migrations eram desfeitas em
  silêncio. Visto localmente, antes de sair daqui.

### Deploy: a API vai para Ohio, e o app para `some-journey-atlas.pages.dev`
- O projeto do Supabase nasceu em **East US (Ohio)**, `us-east-2`. Em vez de recriá-lo, a API
  acompanhou: `render.yaml` passa a `region: ohio`. API e banco continuam lado a lado, que é o
  que importa — cada consulta custa ~1 ms. O guia agora pede Ohio na criação do Supabase e
  avisa que, se o projeto nascer noutra região, a `region` do `render.yaml` tem de mudar ANTES
  de criar o serviço no Render.
- O endereço `some-journey.pages.dev` já é de outro site no Cloudflare Pages. O padrão do
  workflow de deploy web passa a `some-journey-atlas` (a variável `CF_PAGES_PROJECT` só é
  preciso se esse também estiver tomado), e o guia e o `render.yaml` usam
  `https://some-journey-atlas.pages.dev` no `CORS_ALLOWED_ORIGINS`.

## 2026-11-15

### Deploy: o link de recuperação de senha aponta para o app certo
- O padrão de `PASSWORD_RESET_URL_BASE` ainda era `https://some-journey.pages.dev/reset-password`
  — o endereço que já é de outro site no Cloudflare Pages. O link do e-mail leva o token na
  querystring: com o SMTP ligado, o token de redefinição iria para um site de terceiro. Estava
  inerte só porque o e-mail ainda não sai em produção.
- O padrão passa a `https://some-journey-atlas.pages.dev/reset-password`, o `render.yaml` define
  a variável às claras, ao lado das outras, e o guia avisa que ela muda junto com o
  `CORS_ALLOWED_ORIGINS` se o projeto do Pages trocar de nome. Um teste compara o host do
  padrão com o projeto que o workflow de deploy publica.

### Recuperação de senha: o link do e-mail abre a tela de nova senha
- O app não tinha a rota do link: ele abria no login, e a pessoa tinha de copiar o token de
  dentro da URL e colá-lo no campo "Código do e-mail". Agora `#/reset-password?token=…` abre
  direto a etapa de escolher a senha, com um campo só. O caminho de quem pede o link e cola o
  código na mesma tela continua igual.
- O padrão de `PASSWORD_RESET_URL_BASE` passa a
  `https://some-journey-atlas.pages.dev/#/reset-password`. A rota fica depois do `#` porque é
  onde o app web guarda as rotas — e porque o navegador não envia a servidor nenhum o que vem
  depois do `#`: o token não aparece em log de hospedagem. Depois de lido, ele também sai da
  barra de endereço.
- Com sessão aberta o link funciona igual, e a troca encerra a sessão local: a senha nova
  invalida os tokens antigos no servidor.

## 2026-11-20

### App: Configurações › Conta abre a edição de perfil
- "Alterar nome" e "Alterar foto" estavam marcados "em breve" enquanto a tela que faz as duas
  coisas já existia, aberta só pelo botão do Perfil. Viraram **uma linha** — "Nome, foto e
  @username" — que abre essa mesma tela: duas linhas seriam duas portas para o mesmo lugar.
- Configurações não tem o perfil na mão, então busca o atual antes de abrir. Se ele não vier, a
  pessoa continua onde está, com um aviso, e a linha volta a responder.
- O Perfil por baixo se atualiza pelo aviso de escrita do cliente da API (`Api.changes`), não
  pelo retorno da rota.

### Documentação: o que tinha ficado para trás do código
- README: Dart `>= 3.10.9` (dizia 3.12.2, contra o `pubspec.yaml` e o CI), migrations
  `0001..0016` (dizia `..0010`), `life_phases` na lista de rotas, contagem de testes (418 no
  backend, 519 no app) e a divergência do texto da memória sem "os dois clientes".
- [`09-perfil.md`](09-perfil.md): a tabela de dados dizia que avatar, cidades, países e
  continentes **faltavam** — o segundo como bloqueador. Estão entregues desde a migration de
  lugar e o `GET /me/profile`. A tabela agora diz de onde cada dado vem e o que de fato falta:
  atividade recente, dias consecutivos, conquistas e coleções.
- [`04-decisoes-tecnicas.md`](04-decisoes-tecnicas.md) e
  [`05-fluxos-usuario.md`](05-fluxos-usuario.md): o mapa era descrito como Leaflet na web e
  busca/lista no nativo, que era o app Expo. É `flutter_map`, o mesmo nos dois.
- [`11-convencoes.md`](11-convencoes.md): uma menção a "os dois clientes" que sobrou.

### Código: dois comentários que diziam o que já não é
- `app/services/geocoding.py` falava nos "2 workers do start.sh"; o padrão é um processo desde
  14/11.
- `app/core/pagination.py` dizia que o contrato de cursor é idêntico em todas as rotas de
  lista. Agora diz quais paginam e quais devolvem a lista inteira — a pendência registrada em
  11/10.

## 2026-11-20 (2)

Quatro fragilidades do levantamento de 20/11, fechadas juntas porque três delas se
encostam: sessão que dura pede um segredo de vida longa, e segredo de vida longa pede um
lugar melhor para ficar.

### A sessão se renova sozinha
- O access token vale 60 minutos e não havia como renová-lo: passada a hora, a primeira tela
  que pedisse dados tomava 401 e mandava a pessoa para o login, no meio do que estivesse
  fazendo. Agora o login devolve também um **refresh token** (30 dias), e o app o troca por
  um par novo em `POST /auth/refresh` quando o access vence — e repete a MESMA requisição.
  Quem chamou nem fica sabendo.
- **Rotação.** Cada refresh token vale uma troca; a resposta traz o sucessor, com validade
  nova. No banco fica só o SHA-256 dele (`refresh_tokens`, migration 0018), como já era com
  o token de recuperação de senha.
- **Reuso é cópia.** Um token já trocado que reaparece revoga a sessão inteira daquele
  aparelho: quem copiou perde o acesso, e a dona volta ao login — que é o aviso que ela pode
  receber. A exceção é uma folga de 20 s para os dois casos honestos: duas abas renovando
  juntas com o mesmo token guardado, e a resposta da renovação que se perdeu no caminho.
- **Sair agora sai no servidor** (`POST /auth/logout`): antes o app só esquecia o token, e
  ele seguia valendo. O aparelho esquece primeiro e avisa depois, sem esperar — sair não
  pode depender de rede.
- **Trocar ou redefinir a senha encerra as sessões abertas**, no mesmo commit do hash novo.
  Sem isso o access token antigo morria e o refresh antigo emitia outro.
- No app, o que se cuidou para a renovação não virar problema novo:
  - várias requisições vencem juntas (uma tela abre e dispara três) e a renovação acontece
    **uma vez** — três trocas com o mesmo token seriam duas recusas;
  - sem rede, servidor fora ou 429 na renovação **não deslogam**: a sessão pode estar inteira,
    e mandar para o login quem só passou por um túnel seria o defeito antigo de volta;
  - o 401 de "senha atual incorreta" **não** dispara renovação. Só o 401 de sessão traz
    `WWW-Authenticate`, que passou a ser exposto no CORS para o app web conseguir lê-lo;
  - duas abas: antes de trocar, a aba relê o que está guardado. Se a outra já renovou, adota
    o par novo em vez de reusar o velho;
  - renovar não é trocar de sessão: os caches de tela (Perfil, estante) não se esvaziam a
    cada hora.
- Compatível nos dois sentidos, porque API e app são publicados separados: o app novo contra
  a API antiga só não renova; o app antigo contra a API nova ignora o campo a mais.

### Os tokens saem do arquivo de texto, no celular
- A sessão ficava no `shared_preferences`, que no celular é um arquivo de texto na pasta do
  app. Para um token de uma hora era um risco pequeno; para um refresh token de 30 dias não
  é. No celular os dois vão para o cofre do sistema — **Keychain** no iOS, **Keystore** no
  Android (`flutter_secure_storage`).
- **Na web continuam no `localStorage`**, e não é descuido: o navegador não tem cofre. O que
  o plugin oferece ali é cifrar o valor com uma chave guardada no mesmo `localStorage`, que
  não protege de nada do que já alcança um.
- Quem já estava logado é **mudado** para o cofre na primeira abertura — copiado e, só
  depois de gravado, apagado do arquivo. Atualizar o app não desloga ninguém.
- Se o cofre recusar a gravação, a sessão vale em memória até o app fechar. Ela **não** cai
  de volta para o arquivo de texto.
- Cada ida ao cofre tem teto de 4 s: um keychain que não responde não segura o login.
- Android: `allowBackup="false"`. O backup automático levaria o valor cifrado para outro
  aparelho sem a chave que o abre.
- Não conferido em aparelho: as três plataformas nativas só rodaram nos testes, com o cofre
  simulado.

### Os pontos de GPS sobrevivem ao app
- Entre um lote e outro — e durante todo o tempo em que a rede falhava — os pontos do
  percurso existiam só em memória. Se o app morresse ali, o fim do percurso sumia e o traço
  simplesmente terminava antes, sem erro nenhum.
- Cada ponto aceito é escrito no aparelho assim que entra, com o trecho a que pertence, e
  sai quando o servidor confirma. O lote que está no ar também fica guardado: é justamente o
  que se perderia.
- Na volta, a jornada **diz** quantos pontos ficaram e oferece enviá-los; e a saída que já
  existia para o trecho que ficou aberto ("Encerrar a gravação anterior") leva os pontos
  junto, antes de fechar.
- Sem rede, o trecho não é fechado nem os pontos apagados — fechar sem eles jogaria fora o
  fim do percurso. Pontos que o servidor **recusa** (o trecho fechou por outro caminho) são
  deixados para trás: senão a jornada ficaria presa num envio que nunca vai ser aceito.
- Duas mudanças de comportamento no mesmo sentido: sair da tela gravando agora sobe o que
  faltava antes de fechar o trecho (antes fechava sem eles), e encerrar sem rede mantém os
  pontos para a próxima tentativa (antes eram descartados).
- Sair da conta apaga do aparelho o que não subiu: é de quem saiu, não do próximo a entrar.
- Limite conhecido: se o app morrer entre o servidor confirmar um lote e o aparelho
  registrar isso, o lote sobe de novo na recuperação e os pontos ficam duplicados no trecho.
  A janela é de milissegundos; o servidor não deduplica.

### O limite de tentativas mora no banco
- Era um dicionário na memória do processo. Um reinício da API — deploy, queda, o contêiner
  do plano grátis acordando — zerava os baldes e devolvia a quem estava adivinhando uma
  senha uma janela nova; e com mais de um processo cada um contava o seu.
- Cada balde é uma linha em `auth_rate_limits` (migration 0017) e a contagem é **um**
  comando: `INSERT ... ON CONFLICT DO UPDATE`, que abre a janela, reinicia a vencida ou
  soma, e devolve o total. O Postgres trava a linha, então duas tentativas simultâneas nunca
  leem o mesmo número; e o relógio é o do banco, o mesmo para todo processo.
- A chave é o SHA-256 das partes: a tabela não guarda e-mail nem IP.
- A contagem roda numa transação própria — a tentativa tem de ficar contada mesmo quando o
  request termina em 401, que é o caso que o limite existe para contar.
- A API continua subindo com um processo só, agora por um motivo a menos: o intervalo do
  Nominatim ainda é por processo.

### Testes
- Backend: 450 (eram 418). App: 574 (eram 519).
- Os testes do app ganharam um cofre de mentira para todos (`test/flutter_test_config.dart`).
  Num teste não há plataforma do outro lado do plugin, e a chamada não falha — ela nunca
  responde, e o login "não termina" longe da causa.

## 2026-11-20 (3)

### Deploy: a API ficou cinco dias sem publicar, e nada avisou
- O push das mudanças de sessão passou no CI, o app web foi publicado, e a API continuou
  respondendo com o código de 15/11 — `/auth/refresh` em 404, e as mensagens em português do
  commit anterior também fora do ar. O Render não tinha feito deploy nenhum.
- O `render.yaml` pede `autoDeployTrigger: checksPass`, e "checks" são todos os do commit. Um
  projeto do Cloudflare Pages chamado `some-journey`, ligado ao repositório pelo Git, tenta
  compilar a cada push, falha (o Pages não tem Flutter) e deixa um check vermelho em todo
  commit desde pelo menos 15/11. O app nunca dependeu dele: quem publica é o workflow, no
  projeto `some-journey-atlas`.
- O que mascarou o problema: os três deploys anteriores eram de commits que mexiam no
  `render.yaml`, e saíram segundos depois do push, antes de o CI terminar. Pareciam o gatilho
  funcionando. A leitura de que foram publicados pela sincronização do blueprint, e não pelo
  `checksPass`, é dedução a partir dos horários — o painel do Render não foi consultado para
  confirmá-la.
- Resolvido na hora com **Manual Deploy** do commit `af25198`: as migrations 0017 e 0018
  rodaram e a API nova respondeu. O check do Cloudflare ainda precisa ser desligado; até lá,
  cada push de backend pede deploy manual.
- [`12-deploy.md`](12-deploy.md) ganhou o aviso nos dois lugares em que alguém tropeçaria — o
  fim do passo do Render e o passo do Pages —, os dois comandos que mostram os checks de um
  commit e o último deploy registrado, e a linha correspondente em "Problemas comuns".

## 2026-11-21

### App web: cabeçalhos de segurança
- A API já respondia com CSP, HSTS e proteção contra ser embutida; o **app** no Cloudflare
  Pages saía só com `nosniff` e `Referrer-Policy`. E é do lado do app que isso pesa: na web a
  sessão mora no `localStorage`, que qualquer script rodando na página lê.
- `app_flutter/web/_headers` passa a acompanhar o build. A CSP é uma lista fechada:
  - **script** só do próprio app, mais o WebAssembly do CanvasKit (`wasm-unsafe-eval`) e o
    botão do Google. Sem `unsafe-inline` e sem `unsafe-eval` — é o que impede um script
    injetado de rodar;
  - **conexões** só para a API, a busca de lugar (Nominatim), a busca de música (iTunes), as
    fontes de reserva do Flutter e os hosts de imagem;
  - **imagens** só das telhas do mapa, dos links assinados do Supabase e das capas de música;
  - `frame-ancestors 'none'`: o app não abre dentro da página de ninguém.
- Junto vão HSTS, `X-Frame-Options`, `Permissions-Policy` (localização só para o próprio app)
  e `Cross-Origin-Opener-Policy`.
- O estilo continua com `unsafe-inline`: o motor do Flutter escreve estilos inline e não há
  como evitar.
- **A origem da API não fica escrita no arquivo.** Ela entra por um marcador que o workflow de
  deploy troca pelo valor de `API_URL` — a mesma variável do build — e confere antes de
  publicar. Publicar com o marcador no lugar deixaria o app no ar e toda chamada bloqueada.
- Lista fechada quebra de um jeito próprio: serviço novo no app funciona em localhost, onde o
  arquivo não é aplicado, e falha em produção em silêncio. `test/web_headers_test.dart` cobra
  que todo host escrito no código esteja na política, e que ela não seja afrouxada.

### Como foi conferido
- Com o build servido localmente por um servidor que aplica o `_headers` como o Pages faz: o
  app abriu, entrou, desenhou o atlas com as telhas e falou com a API sem nenhuma violação.
  Chamadas de dentro da página aos hosts permitidos passaram; `eval`, script inline, script de
  outro site e imagem de fora da lista foram bloqueados.
- **Não conferido:** o botão do Google (não há client id configurado) e uma foto de verdade
  vinda do Supabase — os dois estão na política pelo padrão do endereço, não por teste.

## 2026-11-21 (2)

### Excluir conta
- Não havia como ir embora. A linha "Excluir conta" estava em Configurações marcada "em
  breve", e do lado do servidor não existia rota: os dados de quem desistisse do app ficavam
  conosco para sempre.
- `POST /auth/delete-account` apaga a conta e tudo o que é dela, **na hora**: memórias,
  fotos, músicas, jornadas, percursos, fases, perfil e tokens. É uma linha apagada em `users`;
  o `ON DELETE CASCADE` que as chaves estrangeiras já tinham leva o resto. Não fica cópia, e o
  e-mail volta a estar livre.
- **Duas confirmações, e nenhuma é a sessão.** O e-mail da conta, digitado — a trava contra o
  toque errado — e a senha atual, quando a conta tem uma. Um token de sessão copiado não
  apaga a conta de ninguém. Conta que só entra pelo Google não tem senha a conferir: para ela
  vale o e-mail e a sessão. O perfil passou a dizer se a conta tem senha
  (`identity.has_password`), para o app saber o que pedir antes de pedir.
- A senha errada responde 401 **sem** `WWW-Authenticate`, como na troca de senha: a sessão
  está boa, e o app não deve renová-la para repetir a mesma senha.
- No app, a tela diz o que some e que não tem volta, e não tenta convencer ninguém a ficar.
  O botão em destaque é o que não destrói nada ("Manter minha conta"); o de excluir é o
  discreto, e só acende com as confirmações preenchidas. Deu certo, o aparelho esquece a
  sessão, as fases em memória e os pontos de GPS que esperavam envio.

### Expurgo do que foi apagado
- Apagar, aqui, é marcar `deleted_at`. Protege do toque errado — e, sozinho, significava que
  nada jamais saía: a memória apagada há um ano seguia no banco, com as fotos no Storage.
- O que está apagado há mais de **30 dias** (`PURGE_DELETED_AFTER_DAYS`) agora sai de vez:
  memória (com fotos, músicas e vínculos), jornada (com capa, vínculos, trechos e pontos),
  trecho de GPS, fase, e a foto ou a música tirada de uma memória que continua. De carona
  saem os tokens vencidos. Expurgar uma jornada não toca nas memórias dela.
- Roda dentro da própria API, a cada 6 h **em produção** — o plano grátis do Render não tem
  cron. Fora de produção não roda sozinho: o `.env` de desenvolvimento alcança o bucket com
  credenciais de verdade, e uma API de dev deixada de pé não deve apagar nada por conta
  própria. À mão: `python -m scripts.purge_deleted`, com `--dry-run` para ver o que sairia.
- É idempotente: duas passadas seguidas, ou dois processos ao mesmo tempo, apagam as mesmas
  linhas uma vez só.

### Os arquivos: nenhum fica sem registro
- Banco e Storage não cabem numa transação só. A ordem ingênua — apaga a linha, depois o
  arquivo — tem uma falha que não deixa rastro: se o Storage não responder, o arquivo fica lá
  e ninguém mais sabe o caminho. Uma foto que a pessoa mandou apagar ficaria guardada para
  sempre.
- Nova tabela `pending_file_deletions` (migration 0019): o caminho entra na fila na **mesma**
  transação que apaga a linha, e sai quando o Storage confirma a remoção. O que falhar é
  tentado de novo na passada seguinte, do menos tentado para o mais tentado.
- `storage.remove` diz se o arquivo saiu — o `storage.delete` que existia engole a falha, o
  que serve para o melhor-esforço de uma foto trocada e não serve para quem precisa tentar
  de novo. "Objeto não existe" conta como saiu.
- A exclusão de conta alcança também os arquivos de memórias já apagadas, e os de fotos cuja
  remoção em melhor-esforço possa ter falhado no passado.

### Testes
- Backend: 495 (eram 450). App: 597 (eram 585).
- Um teste lista toda tabela como "de alguém" ou "sem dono" e para a suíte se uma tabela nova
  nascer sem ser classificada: é o que impede a próxima tabela com dado de pessoa de ficar de
  fora da exclusão de conta sem ninguém notar.
- **Não conferido contra o Supabase de verdade:** a remoção de arquivos foi testada com um
  Storage simulado. O formato da resposta de "objeto não existe" (400 com `not_found` no
  corpo) vem da leitura da API, não de uma chamada real.

## 2026-11-21 (3)

### As fotos sobem sem metadados
- Uma foto de celular carrega muito além da imagem: as coordenadas de onde foi tirada, o
  modelo e às vezes o número de série do aparelho, a data e a hora, uma miniatura (que pode
  mostrar o enquadramento de **antes** de um corte) e, em alguns aparelhos, um vídeo inteiro
  colado depois do fim do arquivo. Nada disso aparece na tela, e tudo isso ia para o Storage.
- O lugar da memória é o que a pessoa escolheu no mapa, e está no banco. O que o sensor
  anotou por conta própria não foi escolha de ninguém.
- Toda imagem — foto de memória, capa de jornada, avatar — passa agora por `images.prepare`
  antes de subir. **Sai:** EXIF (GPS, aparelho, data, miniatura), XMP, IPTC, comentários,
  miniatura JFXX, imagens extras (MPF) e tudo o que vier depois do fim da imagem. **Fica:** o
  perfil de cor e a orientação.
- **A orientação é o detalhe que não pode se perder.** O celular grava a foto "deitada" e
  anota "gire ao mostrar"; a anotação mora no EXIF, ao lado do GPS. O EXIF sai inteiro e
  entra no lugar um EXIF mínimo com esse único número — senão toda foto em pé apareceria de
  lado.

### Sem recodificar
- A imagem não é aberta nem regravada. JPEG, PNG e WebP são caixas com compartimentos; a
  limpeza percorre a caixa e copia byte a byte os que desenham a imagem. **Nenhum pixel
  muda**, não há perda de qualidade a cada envio, o servidor não ganha biblioteca de imagem
  e não decodifica nada que um arquivo hostil pudesse explorar.
- O app não era lugar para isso: ele redimensiona antes de enviar, e isso às vezes tira o
  EXIF, às vezes o copia de volta, e na web depende do tamanho da foto. O servidor é a única
  ponta que vê todos os clientes.
- **Na dúvida, recusa.** Arquivo cuja estrutura não dá para percorrer responde 400 e não vai
  para o Storage. Guardar "como veio" deixaria passar justamente o que não conseguimos
  limpar. Efeito colateral honesto: os primeiros bytes de um JPEG seguidos de lixo deixaram
  de ser aceitos como imagem — era o que os testes antigos enviavam.

### As fotos que já estavam guardadas
- `python -m scripts.strip_photo_metadata` passa pelos arquivos que o banco conhece, baixa,
  limpa e grava de volta no mesmo caminho. **Por padrão só conta**; gravar pede `--apply`,
  porque gravar por cima não tem volta — que é o objetivo.
- Antes de gravar, o resultado é limpo de novo e tem de dar no mesmo arquivo, e não pode ser
  maior que o original. Se falhar, o arquivo fica como está.

### Como foi conferido
- 77 testes novos com imagens de verdade (geradas pelo Pillow, que entrou **só** nas
  dependências de teste): cada um decodifica o antes e o depois e compara os pixels, em JPEG
  (progressivo, com marcadores de reinício, em cinza, em CMYK, com perfil de cor em vários
  segmentos), PNG (com transparência e paleta) e WebP (com e sem perda, animado).
- Fora da suíte, a limpeza passou por 505 imagens reais do sistema, de outros codificadores:
  505 com os mesmos pixels, nenhuma recusada.
- Backend: 573 testes (eram 496). O app não mudou.
- **Não conferido contra o Supabase de verdade:** o download usado pela faxina das fotos
  antigas (mesma URL do upload e do delete, com `GET`) foi testado com um Storage simulado.

## 2026-11-21 (4)

### A arte do login passa a andar
- `08-design-system.md` §7: a ilustração do vagão virou uma cena (`HeroScene`) —
  paisagem passando atrás do vidro, túnel, a luz do vagão acompanhando a trilha
  que já existia, o viajante respirando, bolhas de sabão saindo do cachimbo.
  Ficam registradas as quatro regras que a seguram (é tudo a mesma pintura, não
  há quadros, a luz é uma só, é ambiente e não cerimônia) e o limite do
  personagem: ele só respira.
- `11-convencoes.md` §13: `features/hero/scene_domain.dart` entra na lista dos
  domínios em Dart puro.
- **A paisagem não é desenhada: é recortada da ilustração.** Serra, vale, prado
  e nuvens saem da arte de marca por `tool/hero_landscape.py` e viram um atlas
  de tiras sem fim (334 kB). O céu teve de ser refeito — é nele que o logo está
  pintado —, com o azul e o creme medidos na própria pintura e as nuvens
  recortadas dos trechos limpos.
- **O que foi inventado, e onde.** A ilustração tem uma janela só de paisagem;
  para ela não acabar, a serra foi estendida para os dois lados (a encosta que
  a moldura cortava continua, espelhada e inclinada) e o vale vai e volta. As
  emendas foram disfarçadas, não eliminadas: quem procurar o mesmo rio duas
  vezes por volta vai achar.
- **O véu do pôster encolheu.** Ia até 70% da largura da tela e escurecia a
  janela do vagão; agora tem largura fixa, a da coluna da promessa, e some antes
  do vidro. Sobre o texto ele continua tão escuro quanto era.
- **Não conferido:** desempenho e aparência fora do navegador de mesa. A malha
  da respiração e o banho de cor usam operações que o motor do celular trata de
  outro jeito, e a cena não foi vista num aparelho. Quadros por segundo também
  não foram medidos: a cena foi vista rodando, não cronometrada.

## 2026-11-21 (5)

### App: abrir sem esperar
- **O detalhe abre com o que a lista já mostrou.** A timeline traz cada memória inteira;
  tocar numa delas abria o detalhe em branco e buscava na rede exatamente o que a lista
  acabara de mostrar. Agora o cliente da API guarda a última versão vista de cada memória e
  de cada jornada (`features/sync/seen.dart`), a tela nasce com ela e relê por baixo. É
  "mostre o que tem, confira depois": toda abertura ainda vai ao servidor, e o que mudou
  chega à tela. Vale só para a sessão — sair, ou entrar com outra conta, não deixa nada.
- O mesmo nas telas de **editar**. A releitura chega meio segundo depois de a tela abrir, e
  por isso ela só atualiza o campo que a pessoa ainda não mexeu.
- **Uma releitura que falha não tira da tela o que a pessoa está lendo.** Só vira erro
  quando não há nada a mostrar — ou quando o servidor diz que aquilo foi apagado.
- **A jornada busca tudo de uma vez.** A jornada, o mapa do percurso e a lista de trechos
  eram três pedidos em fila, cada um esperando o anterior voltar dos EUA. Saem juntos.
- **Perfil e estante são buscados antes de alguém pedir**, quando as abas sobem: o primeiro
  toque no avatar já abre preenchido.
- **Web: a página não nasce branca.** Enquanto o motor do Flutter e o app (uns 10 MB)
  baixam, aparece o papel creme com o nome do app — só CSS, porque a política de segurança
  não deixa script inline rodar, e nem precisa.

### App: as fotos sobem depois de a memória estar salva
- Salvar uma memória com cinco fotos deixava a pessoa parada no formulário enquanto as
  cinco subiam em fila — por uma memória que já estava gravada desde o primeiro pedido.
  Agora a tela fecha quando a **memória** está salva, e as fotos vão para uma fila
  (`features/photos/photo_uploads.dart`): sobem uma de cada vez, na ordem em que foram
  escolhidas (a primeira é a capa), e cada uma aparece nas listas ao chegar.
- O envio nunca é silencioso: uma faixa por cima de qualquer tela diz "Enviando fotos… 2 de
  5", e a foto que falha fica à vista, com "Tentar de novo", em vez de sumir.
- **O que isto custa:** as fotos na fila existem só na memória do app. Se ele for fechado
  antes de a fila esvaziar, as que faltavam não sobem — a memória fica salva sem elas, e dá
  para anexá-las de novo editando. Sair da conta abandona a fila.

### Dependências: 27 vulnerabilidades conhecidas, e ninguém avisava
- Uma auditoria (`pip-audit`) achou 27 vulnerabilidades publicadas em duas bibliotecas do
  backend: `pyjwt` 2.13.0 (15), que assina e confere as sessões, e `python-multipart` 0.0.20
  (12), que lê os uploads. As correções existiam; as versões é que estavam fixadas à mão e
  ficavam onde estavam. Subiram para `pyjwt` 2.15.1 e `python-multipart` 0.0.34, a auditoria
  ficou limpa e a suíte inteira passou com elas.
- Para não depender de alguém lembrar: o **Dependabot** propõe as atualizações toda semana
  (backend, app e actions), e um workflow próprio (`audit.yml`) roda a auditoria toda
  segunda-feira e a cada mudança no `requirements.txt`. Fica fora do CI de propósito — uma
  vulnerabilidade nova aparece sem que nada mude no repositório, e não deve segurar o
  deploy de um commit que não tem nada a ver com ela.

### CI
- **Lint do backend** (`ruff`, só o que acusa defeito: erro de sintaxe, nome que não existe,
  import sem uso). Nenhuma regra de estilo — o projeto continua sem formatador. O código
  passou sem nenhuma correção.
- **Token do GitHub só de leitura** nos três workflows. O padrão depende da configuração da
  conta e costuma incluir escrita; nenhum passo precisa dela.

### Teto de uso para quem já está logado
- O limite de tentativas cobria só a porta de entrada. Quem já estava dentro podia gravar
  sem teto: um laço — por defeito num cliente, ou de propósito — encheria os 500 MB do banco
  e o 1 GB do Storage do plano grátis, e o serviço pararia para todo mundo.
- Agora cada pessoa tem dois baldes, contados no banco pelo limitador que já existia: **600
  escritas** e **60 uploads** a cada 5 minutos. Muito acima de qualquer uso do app; leitura
  nunca conta; a chave é o id da pessoa, não o IP. Entra como dependência dos routers, então
  cobre também as rotas que nascerem depois.

### "O que guardamos sobre você"
- Configurações › Privacidade ganhou uma tela que diz, em texto corrido, o que fica
  guardado, o que sai das fotos, quando a localização é usada, quem mais participa e como
  apagar. Não é política de privacidade com valor jurídico: é a descrição do que o código
  faz.
- Tela de texto fica para trás do código. Por isso um teste confere a lista de serviços da
  tela contra a política de segurança do site, que nomeia cada endereço que o app pode
  chamar: endereço novo lá, sem o dono nomeado aqui, para a suíte.

### Documentação: uma leitura de ponta a ponta contra o código
- Todos os documentos foram conferidos com o código e 24 divergências foram corrigidas. As
  que mais pesavam:
  - `03-api-planejada.md` e o README não listavam `POST /auth/google`, `GET /me/places`,
    `GET /me/days` nem os filtros de `GET /memories`, e diziam que o perfil traz "atividade
    recente", que não existe;
  - `02-modelagem.md` parava na migration 0010, dava `password_hash` como obrigatório e não
    tinha `google_sub` nem as fases no diagrama;
  - `11-convencoes.md` ainda descrevia a lista `_TABLES` escrita à mão e a suíte sem trava de
    banco — as duas coisas mudaram em 14/11;
  - o README mandava esperar **201** ao anexar uma foto (é 200), citava "dev build" (do
    Expo) e descrevia o CI sem a paridade nem o `alembic check`;
  - `08-design-system.md` dizia que "o backend não tem OAuth" e tinha uma frase cortada no
    meio; `10-localizacao.md` ainda falava em "2 workers";
  - `app_flutter/README.md` era o modelo do `flutter create`, que não dizia nada verdadeiro
    sobre o app.

### Testes e o que não foi conferido
- Backend: 587 testes (eram 573). App: 627 (eram 597), sem contar os da cena do login, que
  é trabalho de outra frente e ainda não entrou.
- Um teste do gravador de percurso falhava de vez em quando: o encerramento em segundo
  plano de um gravador descartado escapava para o servidor de mentira do teste seguinte. O
  `tearDown` agora espera assentar.
- **Não conferido no navegador:** a tela de espera da web, a abertura instantânea e a fila
  de fotos foram verificadas só pelos testes. Um build web para conferir foi interrompido e
  não foi refeito.
- **Não conferido em uso real:** o envio de fotos em segundo plano num celular que suspende
  o app.

## 2026-11-24

### Os primeiros pull requests do Dependabot, lidos um a um
Seis PRs abertos na primeira rodada. O CI de quatro passou — e CI verde não era a
resposta inteira em dois deles.

- **Bibliotecas do backend (14, entre elas `pwdlib` 0.3 → 0.4.2).** A suíte passa, e ainda
  assim a atualização mudaria o comportamento do login: até a 0.3 um hash argon2 truncado
  devolvia `False`; a partir da 0.4.1 ele levanta uma exceção nova
  (`HashVerificationError`). O nosso `verify_password` pegava só a antiga
  (`UnknownHashError`), então uma conta com o hash corrompido passaria a responder **500**
  no login em vez de "e-mail ou senha incorretos". Nenhum teste cobria. O `except` agora
  pega a classe-base da biblioteca — qualquer recusa ao conferir é, para quem está
  entrando, a mesma coisa — e 12 testes novos seguram os casos nas duas versões.
- **`flutter_map` 7 → 8.** Passa no analyze e nos testes e **quebra o mapa**: visto no
  navegador, o atlas desenha pinos e rastros sobre um fundo vazio, sem telha nenhuma, com um
  erro não tratado no console. A versão 7, no mesmo ambiente, mostra o mapa. Fica de fora
  até alguém fazer a migração de propósito.
- **`image_picker` 1.2.4 e `cupertino_icons` 2.0** pedem Dart 3.11 e 3.12; o projeto fixa o
  3.10.9. O Dependabot resolve as versões com o Dart mais novo e propõe o que o CI não
  instala — e um pacote assim dentro do grupo derruba as atualizações boas que vinham junto.
- `.github/dependabot.yml` ganhou a lista do que fica de fora, com o motivo de cada linha.
- A lista não bastou. Na rodada seguinte o grupo do app voltou com outro pacote que pede
  Dart 3.11 (`shared_preferences` 2.5.6) e falhou de novo: excluir pacote por pacote é
  correr atrás. As atualizações de versão do **app ficam pausadas** até o Flutter fixado
  subir; as do backend e das actions seguem, e as correções de segurança também.

### Como foi conferido
- As 14 bibliotecas do backend mais o `tzfpy` 2.1.2, juntas, num ambiente separado e com a
  correção do `verify_password`: a suíte inteira passou e a auditoria ficou limpa. O `tzfpy`
  2 mantém a API e os resultados, e usa menos memória.
- O `flutter_map` 8 foi construído a partir do próprio PR e aberto no navegador contra a API
  local.
- **Não conferido:** as actions novas no workflow de deploy web (`checkout` v7,
  `wrangler-action` v4) — o CI do PR não exercita esse workflow. Pelas notas de versão, o
  bloqueio novo do `checkout` v7 vale para PR de fork, que não é o nosso caso.
- Backend: 599 testes (eram 587).
