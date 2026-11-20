# Perfil — identidade do viajante

> O Perfil **não é** uma tela de configurações. É a identidade da pessoa dentro do
> Some Journey: metade perfil de viajante, metade passaporte, metade painel
> pessoal. Em poucos segundos ele deve CONTAR a história de quem usa o app.
> Configurações vivem atrás de uma engrenagem discreta, em outra tela.

## Acesso e fluxo

```
Home
 └── avatar (canto superior direito) → Perfil
                                        └── ⚙ → Configurações
```

Padrão de Airbnb/Notion/GitHub: o avatar no topo direito é a porta. A engrenagem
aparece só DENTRO do Perfil.

## Seções (na ordem)

1. **Cabeçalho** — avatar grande, nome, `@username`, frase pessoal
   ("Colecionando lugares desde 2026."), data de entrada, nível (futuro).
2. **Cartão de identidade do viajante** — o resumo humano, logo abaixo do
   cabeçalho. Não é uma grade de números, é uma frase de vida:
   *Explorador desde 2026 · 37 cidades · 18 jornadas concluídas ·
   142 memórias · 56 músicas · última aventura: Fortaleza → Guaramiranga.*
3. **Estatísticas** — memórias, jornadas, países, cidades; depois km registrados,
   dias de uso, fotos, músicas.
4. **Passaporte** — continentes com carimbo (✓ visitados / ⬜ por explorar),
   último país e última cidade.
5. **Mapa pessoal** — mini atlas (memórias, jornadas, regiões exploradas); toque
   abre o Atlas.
6. **Jornada atual** — "Continue sua jornada", título, progresso, nº de memórias,
   botão *Continuar*.
7. **Atividade recente** — linha do tempo curta ("Hoje: criou uma memória";
   "Ontem: concluiu uma jornada").
8. **Conquistas** — visíveis mesmo vazias (primeira memória, 100 memórias,
   primeira jornada, 1000 km, 10 cidades).
9. **Coleções** (futuro) — fotos, vídeos, músicas, pessoas, favoritos.
10. **Atalhos** — editar perfil, compartilhar, exportar dados.
11. **Rodapé** — versão, "entrou em julho de 2026", tipo de conta.

## O que NÃO fazer

E-mail em destaque · botão gigante de logout · lista enorme de opções ·
informações técnicas · qualquer aparência de painel administrativo.

## Análise de dados: o que já existe e o que falta

**Regra de performance:** o Perfil consome **UM** endpoint agregado
(`GET /me/profile`), com as contagens feitas em SQL. Baixar todas as memórias só
para contá-las no cliente violaria a paginação.

| Dado | Situação | De onde vem |
| --- | --- | --- |
| Nome, e-mail, entrou em | ✅ existe | `identity` em `GET /me/profile` |
| `@username`, frase pessoal | ✅ existe | `identity.username` / `identity.bio`; edição por `PATCH /me/profile` |
| Avatar | ✅ existe | `POST`/`DELETE /me/avatar`, no Storage privado; volta como URL assinada |
| Nº de memórias / jornadas | ✅ existe | `stats.memories`, `stats.journeys` |
| Jornadas concluídas | ✅ existe | `stats.journeys_finished` |
| Fotos | ✅ existe | `stats.photos` |
| Músicas salvas | ✅ existe | `stats.tracks` (tabela `memory_music`) |
| Km registrados | ✅ existe | `stats.tracked_meters`, somado no PostGIS a partir dos trechos ativos |
| Cidades / países / continentes | ✅ existe | `stats.cities`, `stats.countries`, `stats.continents` e `passport`; as listas em `GET /me/places` |
| Última aventura | ✅ existe | `last_adventure` |
| Jornada atual + progresso | ✅ existe | `current_journey` (a `active` + contagem de pontos) |
| Dias no app | ✅ existe | `stats.active_days` e a lista em `GET /me/days` — dias distintos com registro, pela data de criação |
| Atividade recente | ⛔ **falta** | derivável de `created_at` de memórias/jornadas; não há campo no endpoint nem seção na tela |
| Dias **consecutivos** de uso | ⛔ **falta** | `active_days` conta dias distintos, não sequência |
| Conquistas / nível | ⛔ **falta** | precisa de definição + persistência; a tela mostra a seção vazia, marcada "Em breve" |
| Coleções | ⛔ **falta** | ainda sem definição |

### O bloqueador que já foi resolvido

No início guardávamos apenas coordenadas, e passaporte, "cidades",
"países" e "última aventura" não podiam ser calculados. A saída adotada foi
**persistir no momento da escrita**: `memories` ganhou os campos de lugar,
preenchidos por reverse geocode quando a memória é criada ou muda de lugar, com
script de backfill para o acervo antigo (ver
[`10-localizacao.md`](10-localizacao.md)). O Perfil lê tudo em SQL, sem voltar
ao provedor. `stats.pending_geocode` diz quantas memórias ainda esperam o lugar.

## Ordem de implementação

1. ✅ Migração + campos de lugar (`city`/`country`) e reverse geocode na escrita.
2. ✅ `GET /me/profile` agregado (SQL) + testes.
3. 🟡 Tela de Perfil: cabeçalho, cartão do viajante, estatísticas, passaporte e
   jornada atual estão prontos, com skeleton e estados de erro/vazio. Faltam o
   mapa pessoal embutido (hoje é o botão "Ver meu atlas") e a atividade recente.
4. ✅ Avatar (upload no Storage privado) e `@username`. A edição abre pelo
   Perfil e por Configurações › Conta.
5. ⬜ Conquistas (definição + persistência) e Coleções.
