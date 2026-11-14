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
