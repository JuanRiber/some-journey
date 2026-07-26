import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/components.dart';
import '../design/sj_theme.dart';
import '../design/tokens.dart';
import 'atlas.dart';
import 'timeline.dart';

/// # Shell de abas: Tempo (álbum) · Criar · Atlas (mapa).
///
/// **Por que existe:** as duas leituras da mesma vida — pelo TEMPO e pelo
/// ESPAÇO — precisam estar a um toque uma da outra, e registrar precisa ser a
/// coisa mais fácil do app.
///
/// **O que o usuário sente:** algo feito à mão, não uma barra de framework: chão
/// de papel, um fio de tinta no topo, rótulos em mono caixa alta e um único
/// gesto proeminente no centro.
///
/// **Ação principal:** "Criar" — deliberadamente o ÚNICO elemento preenchido da
/// barra, elevado sobre o fio. Não é uma aba: empilha a tela de nova memória e
/// devolve a pessoa de onde ela veio.
///
/// **Atrito/surpresa:** toque com haptic, transição suave entre as abas (a troca
/// é explicada por um fade curto, não por um corte), e o estado das duas abas é
/// preservado (IndexedStack) para voltar exatamente ao ponto de leitura.
class TabsScreen extends StatefulWidget {
  const TabsScreen({super.key});

  @override
  State<TabsScreen> createState() => _TabsScreenState();
}

class _TabsScreenState extends State<TabsScreen> {
  int _index = 1; // Atlas é a aba padrão pós-login: o mapa é a espinha dorsal.

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Scaffold(
      backgroundColor: s.bg,
      body: AnimatedSwitcher(
        duration: SJMotion.base,
        // Fade curto: informa que a leitura mudou sem "piscar" a tela.
        child: IndexedStack(
          key: ValueKey<int>(_index),
          index: _index,
          children: const [TimelineScreen(), AtlasScreen()],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: s.surface,
          border: Border(top: BorderSide(color: s.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(
              top: SJSpace.x2,
              bottom: SJSpace.x3,
              left: SJSpace.screenX,
              right: SJSpace.screenX,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Tab(
                  icon: Icons.schedule,
                  label: 'Tempo',
                  selected: _index == 0,
                  onTap: () => _select(0),
                ),
                // O haptic aqui é do próprio SJPressable (não repetir).
                _CreateAction(
                  onTap: () => Navigator.of(context).pushNamed('/memory-new'),
                ),
                _Tab(
                  icon: Icons.public,
                  label: 'Atlas',
                  selected: _index == 1,
                  onTap: () => _select(1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Uma aba: ícone + rótulo mono. Selecionada ganha a cor de ação (vinho) e peso;
/// as outras ficam na tinta suave — hierarquia por COR e PESO, sem caixinha.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    final color = selected ? s.primary : s.inkSoft;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SJRadius.md),
        child: Padding(
          // Alvo de toque confortável (>=44pt de altura com o conteúdo).
          padding: const EdgeInsets.symmetric(horizontal: SJSpace.x4, vertical: SJSpace.x2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                duration: SJMotion.fast,
                scale: selected ? 1.06 : 1,
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(height: SJSpace.x1),
              Text(
                label.toUpperCase(),
                style: SJText.overline(color: color).copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// O gesto central: registrar uma memória. Único elemento preenchido da barra,
/// elevado acima do fio — a barra inteira existe para apontar para ele.
class _CreateAction extends StatelessWidget {
  const _CreateAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = SJTheme.of(context);
    return Transform.translate(
      offset: const Offset(0, -22),
      child: Semantics(
        button: true,
        label: 'Registrar memória',
        child: SJPressable(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: s.primary,
              shape: BoxShape.circle,
              // Anel do papel: separa o botão da barra sem contorno duro.
              border: Border.all(color: s.surface, width: 3),
              boxShadow: SJElevation.e2(s),
            ),
            child: Icon(Icons.add, size: 26, color: s.onPrimary),
          ),
        ),
      ),
    );
  }
}
