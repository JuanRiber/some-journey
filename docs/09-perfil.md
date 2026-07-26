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

1. **Cabeçalho** — avatar grande, nome, `@username` (futuro), frase pessoal
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

**Regra de performance:** o Perfil deve consumir **UM** endpoint agregado
(`GET /me/profile`), com as contagens feitas em SQL. Baixar todas as memórias só
para contá-las no cliente violaria a paginação que acabamos de introduzir.

| Dado | Situação | Como obter |
| --- | --- | --- |
| Nome, e-mail, entrou em | ✅ existe | `GET /auth/me` (`UserProfile`) |
| Nº de memórias / jornadas | 🟡 derivável | `COUNT(*)` no backend (hoje só via lista paginada) |
| Jornadas concluídas | 🟡 derivável | `COUNT(*) WHERE status='finished'` |
| Fotos | 🟡 derivável | `COUNT(*)` em `memory_images` |
| Km registrados | 🟡 derivável | PostGIS nos tracks + haversine dos pontos (a lógica já existe em `features/atlas/atlas_domain.dart`) |
| Jornada atual + progresso | 🟡 derivável | jornada `active` + contagem de pontos |
| Atividade recente | 🟡 derivável | `created_at` de memórias/jornadas, ordenado |
| Músicas salvas | ⛔ **falta** | precisa da tabela `memory_music` (a entidade/adapter já existe no app) |
| **Cidades / países / continentes** | ⛔ **BLOQUEADOR** | **hoje o app NÃO guarda o lugar** — só `latitude`/`longitude`. O rótulo do LocationPicker é display-only e é descartado. |
| Dias consecutivos de uso | ⛔ **falta** | exige registro de atividade (ou derivar de `occurred_at`, o que mede a viagem, não o uso) |
| Conquistas / nível | ⛔ **falta** | precisa de definição + persistência |
| Avatar | ⛔ **falta** | nenhum campo de foto no `users`; precisa upload (o Storage privado já está pronto) |

### O bloqueador que importa

**Passaporte, "cidades", "países" e "última aventura" não podem ser calculados
hoje.** Guardamos apenas coordenadas; o nome do lugar escolhido no picker nunca é
persistido. Duas saídas:

1. **Persistir no momento da escrita (recomendado):** adicionar
   `place_label`, `city`, `country`, `country_code` em `memories`, preenchidos por
   reverse geocode (Nominatim, já usado no app) quando a memória é criada/editada.
   Barato de ler depois, e casa com a regra "importação EXIF é nativa".
2. **Reverse geocode sob demanda:** caro, dependente de rede e sujeito a limite
   de uso a cada abertura do Perfil. Não recomendado.

## Ordem de implementação sugerida

1. Migração + campos de lugar (`city`/`country`) e reverse geocode na escrita.
2. `GET /me/profile` agregado (SQL) + testes.
3. Tela de Perfil (cabeçalho, cartão do viajante, estatísticas, mapa pessoal,
   jornada atual, atividade) com skeletons e estados de erro/vazio.
4. Avatar (upload no Storage privado) e `@username`.
5. Conquistas (definição + persistência) e Coleções.
