# Glossário

Termos do domínio, para evitar ambiguidade.

- **Memória** — Registro pessoal associado a um lugar, uma data e um texto. Pode ter foto opcional.
- **Ponto** — A representação geográfica de uma memória no mapa.
- **Pin** — O elemento visual exibido no mapa para representar uma memória.
- **Jornada** — Conjunto **ordenado** de pontos/memórias que forma uma trajetória.
- **Rastro** — A linha no mapa formada pela conexão dos pontos de uma jornada, na ordem.
- **Ponto solto** — Memória que ainda não pertence a nenhuma jornada.
- **Jornada ativa** — Jornada em andamento (`status = active`), pronta para receber novos pontos. Só uma por usuário por vez.
- **Status da jornada** — `draft` (criada, não iniciada) → `active` → `paused` → `finished` (terminal).
- **`occurred_at`** — Data em que o acontecimento ocorreu.
- **`created_at`** — Data em que o registro foi criado no sistema.
- **`image_path`** — Referência (caminho) da imagem no Supabase Storage. A API expõe uma `image_url` assinada e temporária.
- **Ownership** — Regra de que um usuário só acessa e altera os próprios dados.
- **Soft delete** — Exclusão lógica via `deleted_at`, sem apagar imediatamente o registro.
- **bbox** — Caixa geográfica (`min_lng,min_lat,max_lng,max_lat`) usada para recortar o mapa pela área visível.
