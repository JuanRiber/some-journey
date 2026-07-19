import 'package:flutter/material.dart';

import '../theme.dart';
import 'atlas.dart';
import 'timeline.dart';

/// Shell de abas: Tempo (timeline) · Criar (ação central) · Atlas (mapa).
/// "Criar" não é aba — empilha a tela de nova memória, como no app Expo.
class TabsScreen extends StatefulWidget {
  const TabsScreen({super.key});

  @override
  State<TabsScreen> createState() => _TabsScreenState();
}

class _TabsScreenState extends State<TabsScreen> {
  int _index = 1; // Atlas é a aba padrão pós-login

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [TimelineScreen(), AtlasScreen()],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: SJColors.card,
          border: Border(top: BorderSide(color: SJColors.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 12, left: 24, right: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _tab(icon: Icons.schedule, label: 'TEMPO', selected: _index == 0, onTap: () => setState(() => _index = 0)),
                _createButton(context),
                _tab(icon: Icons.radar, label: 'ATLAS', selected: _index == 1, onTap: () => setState(() => _index = 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab({required IconData icon, required String label, required bool selected, required VoidCallback onTap}) {
    final color = selected ? SJColors.cyan : SJColors.inkSoft;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(label, style: monoLabel(10, color: color, weight: selected ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _createButton(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -22),
      child: Material(
        color: SJColors.wine,
        shape: const CircleBorder(side: BorderSide(color: SJColors.wineDeep, width: 2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).pushNamed('/memory-new'),
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Icon(Icons.add, size: 26, color: SJColors.ink),
          ),
        ),
      ),
    );
  }
}
