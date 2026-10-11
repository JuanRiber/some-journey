import type { JourneyPoint, MapPoint, Memory } from "./api";

// O título de uma memória é opcional: exigir um rótulo para guardar uma
// lembrança trocava o conteúdo pelo índice — a pessoa era obrigada a inventar
// "Praia" e podia deixar em branco justamente o que aconteceu. Ausente é "" e
// não null, igual ao texto: dois jeitos de dizer "não tem" virariam dois
// caminhos em cada tela que desenha o título.
//
// Só de espaços também não conta — o que importa é se há algo para desenhar.
// Sem perguntar isto antes, um <Text>{""}</Text> não quebra nada, não derruba
// build nenhum e chega ao usuário como uma linha em branco que parece defeito.
export function hasTitle(m: Memory | JourneyPoint | MapPoint): boolean {
  return m.title.trim().length > 0;
}
