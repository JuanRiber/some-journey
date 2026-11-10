"""Fases da vida — regras de domínio.

Uma fase é um CAPÍTULO que a pessoa reconhece na própria história: infância,
recomeços, novos caminhos. O produto não oferece uma lista pronta e não exige
que ninguém use fase alguma — a fase existe para ajudar a interpretar a
própria vida, não para impor uma taxonomia.

Três decisões, e as três são sobre o que NÃO fazer:

- **Fases podem se sobrepor.** "Vida adulta" e "recomeços" convivem; exigir
  que não se cruzem transformaria memória em planilha. O domínio não valida
  sobreposição de propósito.
- **O fim é opcional.** A fase em que a pessoa está agora não terminou, e
  pedir uma data de fim para salvar seria pedir que ela decrete o próprio
  presente no passado.
- **A cor vem da paleta, não do seletor de cor livre.** Um hexadecimal
  qualquer quebraria o design system nos dois modos — o que é legível no papel
  quente some no atlas noturno. A escolha é entre papéis semânticos que já
  existem e já têm contraste conferido.
"""

from datetime import datetime

NOME_MAX = 60
DESCRICAO_MAX = 280

# Papéis da paleta que uma fase pode vestir. São os MESMOS nomes dos tokens do
# app (`SJScheme`), então o cliente mapeia sem tabela de tradução — e cada um
# já tem contraste conferido nos dois modos.
CORES: frozenset[str] = frozenset(
    {"primary", "secondary", "accent", "moss", "highlight"}
)
COR_PADRAO = "accent"


class InvalidPhaseError(ValueError):
    """Fase fora das regras — a rota traduz em 422 com a mensagem daqui."""


def validate_name(raw: str) -> str:
    """Apara e confere o nome; devolve o nome limpo ou levanta."""
    nome = raw.strip()
    if not nome:
        raise InvalidPhaseError("Dê um nome a esta fase.")
    if len(nome) > NOME_MAX:
        raise InvalidPhaseError(f"O nome pode ter no máximo {NOME_MAX} caracteres.")
    return nome


def validate_color(raw: str | None) -> str:
    """Devolve a cor escolhida, ou a padrão quando não vier nenhuma."""
    if raw is None or not raw.strip():
        return COR_PADRAO
    cor = raw.strip().lower()
    if cor not in CORES:
        disponiveis = ", ".join(sorted(CORES))
        raise InvalidPhaseError(f"Cor inválida. Use uma destas: {disponiveis}.")
    return cor


def validate_period(started_at: datetime | None, ended_at: datetime | None) -> None:
    """Confere a coerência do período.

    A única regra é a que não pode ser verdade de jeito nenhum: terminar antes
    de começar. Uma fase sem início é aceita (nem toda pessoa sabe quando a
    infância virou outra coisa) e uma sem fim também — essa é a fase em curso.
    """
    if started_at is not None and ended_at is not None and ended_at < started_at:
        raise InvalidPhaseError("Uma fase não pode terminar antes de começar.")
