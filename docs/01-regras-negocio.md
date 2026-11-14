# Regras de Negócio

> Notas marcadas com **(impl.)** já estão no código; **(planejado)** ainda não. Cada regra
> implementada tem teste no backend — quando ela muda, o teste muda junto.

## Usuários e acesso
- Todo usuário tem suas próprias memórias, jornadas e fases. **(impl.)**
- Um usuário só pode ver, editar, excluir e conectar os próprios dados. **(impl.)**
- Dados de um usuário nunca são expostos a outro. IDs de terceiros e IDs inexistentes
  retornam o **mesmo 404** (anti-enumeração). **(impl.)**
- Rotas privadas são protegidas por autenticação (Bearer/JWT, 60 min). **(impl.)**
- O cadastro público fica **fechado em produção**; as contas dos testers vêm do script de
  seed. **(impl.)**
- Senha: de 10 a 128 caracteres, guardada só como hash (Argon2). **(impl.)**
- **Trocar ou redefinir a senha derruba todas as sessões abertas antes** — inclusive quando a
  troca cai no mesmo segundo da senha anterior. **(impl.)**
- Recuperação de senha por token de uso único, válido por 30 min; a resposta é a mesma
  exista a conta ou não. **(impl.)**
- Entrar com o Google **vincula** a conta que já tem o mesmo e-mail, em vez de criar outra.
  Um e-mail já ligado a outra conta Google **não troca de dono** (409). **(impl.)**
- Conta que só entra pelo Google não tem senha para trocar; o caminho é "Esqueci minha
  senha". **(impl.)**
- Tentativas de login e de recuperação têm teto por conta, por IP e **por e-mail** (este
  último vale de qualquer IP). **(impl.)**

## Perfil
- `@username` opcional, único sem diferenciar maiúsculas, de 3 a 30 caracteres, começando
  por letra (`a-z`, `0-9`, `_`), fora de uma lista de nomes reservados. **(impl.)**
- Foto de perfil até 5 MB, no mesmo bucket privado das memórias. **(impl.)**
- Todas as contagens do perfil (memórias, jornadas, cidades, países, fotos, distância) são
  feitas no banco; a distância soma só os trechos de GPS **ativos**. **(impl.)**

## Memórias
- Uma memória é **um ponto no mapa** e pertence a um usuário. **(impl.)**
- Pode existir **sozinha**, sem jornada. **(impl.)**
- Precisa de **localização** (latitude/longitude). **(impl.)**
- Precisa de **data do acontecimento** (`occurred_at`), separada de `created_at`. **(impl.)**
- **Uma memória é de algo que já aconteceu:** a data não pode ser de um dia que ainda não
  chegou. A folga de 36 h cobre o fuso (o "hoje" de UTC+14 está à frente do relógio do
  servidor). **(impl.)**
- **Datas ficam entre os anos 1000 e 2999** — vale para toda data de entrada da API. **(impl.)**
- **Texto** deveria ser o núcleo da memória; **hoje a API o trata como opcional**
  (`text` tem default `""`, máx. 5000 chars). Com o título também opcional, uma memória pode
  ser só data e lugar. Tornar o texto obrigatório segue em aberto — quebraria os clientes e o
  acervo já gravado. **(impl. — divergência, decisão de produto)**
- **Título**: **opcional**, até 120 chars. Ausente é `""`, não nulo — a mesma
  convenção do texto, para não haver dois jeitos de dizer "não tem". **(impl.)**
- **Foto** é opcional; até **5 por memória**. **(impl.)**
- **Música**: até **5 faixas por memória**, sem repetir a mesma faixa; o backend guarda o
  que o catálogo devolveu e não consulta catálogo nenhum. Links de capa, prévia e faixa só
  `http`/`https`. **(impl.)**
- O **lugar** (cidade, país, continente) é resolvido depois de gravar, sem a pessoa esperar.
  **Mudar a memória de lugar refaz o lugar**; salvar com o mesmo ponto não mexe nele. **(impl.)**
- Pode ser vinculada a uma jornada **depois** de criada. **(impl.)**
- Excluir uma jornada **não apaga** as memórias. **(impl.)**
- Exclusão é **soft delete** (`deleted_at`). **(impl.)**
- Texto com caractere que o banco não guarda (NUL) é recusado com 422. **(impl.)**

## Jornadas
- Uma jornada é uma **trajetória** que conecta vários pontos/memórias, e pertence a um usuário. **(impl.)**
- Status: `draft` (criada, não iniciada), `active`, `paused`, `finished`.
  O produto pediu `active/paused/finished`; mantivemos `draft` para "criada mas não iniciada". **(impl.)**
- Só pode haver **uma jornada `active` por usuário** por vez; pausar libera o slot. **(impl.)**
- Enquanto `active`, novos pontos entram em sequência. **(impl.)**
- Iniciar / pausar / retomar / finalizar são transições controladas; `finished` é terminal. **(impl.)**
- `finished` **não recebe pontos novos nem percurso novo**, mas ainda pode ser reordenada,
  corrigida e ter pontos desvinculados — senão uma memória posta ali por engano ficaria
  presa para sempre (ela só pode estar numa jornada). **(impl.)**
- **Período coerente:** o fim nunca antes do início — no create, no finish e no PATCH
  (contando o que já está gravado). Jornada **pode** ter data no futuro: viagem planejada. **(impl.)**
- Pontos soltos podem ser conectados depois. **(impl.)**
- O **rastro** é formado pela **ordem** dos pontos; o usuário pode **reordenar**. **(impl.)**
- A jornada **organiza** memórias — não as substitui. **(impl.)**

## Percurso real (GPS)
- Distinto do rastro simbólico: é o caminho gravado, em trechos. **(impl.)**
- **Um trecho aberto por jornada** de cada vez; pausar e retomar gera trechos novos. **(impl.)**
- Jornada `finished` não abre trecho nem recebe ponto; trecho encerrado não recebe ponto. **(impl.)**
- Pontos chegam em lotes de **até 1000**. **(impl.)**
- A data do ponto **não** é conferida contra o relógio do servidor: um celular adiantado não
  pode custar o rastro inteiro de um trecho. **(impl.)**
- Apagar a jornada apaga os trechos dela; o perfil para de contar essa distância. **(impl.)**

## Fases da vida
- Uma fase é um **capítulo** que a pessoa reconhece (a faculdade, um recomeço). Não há lista
  predefinida e ninguém precisa usar fase nenhuma. **(impl.)**
- Só o **nome** é obrigatório (até 60 chars). **Um nome por pessoa**, sem diferenciar
  maiúsculas, entre as fases ativas — duas "Faculdade" seriam duas etiquetas iguais na lente.
  O nome de uma fase apagada fica livre. **(impl.)**
- Período **aberto dos dois lados** e **fases podem se sobrepor**. **(impl.)**
- A cor é um **papel da paleta** (primary, secondary, accent, moss, highlight), nunca um
  hexadecimal. **(impl.)**
- Memórias e jornadas podem ser marcadas numa fase — **só nas fases da própria pessoa**. **(impl.)**
- **A lente:** a memória está na fase quando foi marcada nela **ou** quando está numa jornada
  marcada nela; a jornada, quando foi marcada ou quando alguma memória dela foi. No mapa, a
  jornada vem inteira. A fase **não** é deduzida das datas. **(impl.)**
- **Apagar uma fase solta** o que apontava para ela: a etiqueta é descartável, a lembrança
  não. **(impl.)**

## Pontos soltos
- O usuário pode criar pontos individuais sem iniciar jornada. **(impl.)**
- Podem permanecer soltos indefinidamente. **(impl.)**
- Podem ser conectados depois a uma jornada, **sem apagar nem recriar** a memória. **(impl.)**
- **MVP:** uma memória pertence a **no máximo uma** jornada por vez (índice único parcial). Desvincular libera a memória. **(impl.)**

## Imagens
- Opcionais, até **5 por memória**. **(impl.)**
- O **arquivo não fica no PostgreSQL**. **(impl.)**
- Armazenadas no **Supabase Storage** (bucket privado). **(impl.)**
- O banco guarda só a referência (`memory_images.image_path`); a API devolve uma
  `image_url` **assinada** e temporária. **(impl.)**
- O tipo é decidido pelos **bytes** do arquivo (JPEG, PNG, WebP), não pelo cabeçalho; até 5 MB. **(impl.)**
- Um usuário só anexa imagem às próprias memórias. **(impl.)**

## Mapa
- O mapa é o centro da experiência. **(impl.)** O app Flutter desenha o atlas com
  `flutter_map` consumindo `GET /map`, no celular e na web. **(impl.)**
- Mostra pins de memórias e rastros de jornadas. **(impl.)**
- Diferencia pontos soltos de pontos de jornada (cores distintas). **(impl.)**
- Suporta recorte por área (bbox), por jornada e por fase da vida; visão
  mundo/país/região/cidade vem do zoom. **(impl. via `GET /map`)**

## Restrições do MVP (não implementar agora)
Feed social, likes, comentários, gamificação, IA, grupos complexos, realtime avançado,
monetização, impressão física e exportação premium.
