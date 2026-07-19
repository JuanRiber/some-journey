import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/atlas_map.dart';

/// Atlas (aba padrão pós-login): o mapa vivo do usuário — pins soltos (ciano),
/// pins de jornada (vinho) e os rastros. Tocar num pin abre a memória.
class AtlasScreen extends StatefulWidget {
  const AtlasScreen({super.key});

  @override
  State<AtlasScreen> createState() => _AtlasScreenState();
}

class _AtlasScreenState extends State<AtlasScreen> {
  MapResponse? _map;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = '');
    try {
      final data = await Api.instance.getMap();
      if (mounted) setState(() => _map = data);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
        return;
      }
      setState(() => _error = e.message);
    }
  }

  Future<void> _logout() async {
    await Api.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final count = _map?.totalPoints ?? 0;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: SJColors.cyan,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SOME JOURNEY', style: monoLabel(11, color: SJColors.gold)),
                      const SizedBox(height: 6),
                      Text('Seu atlas', style: serif(32)),
                      const SizedBox(height: 4),
                      Text(
                        '$count ${count == 1 ? 'memória registrada' : 'memórias registradas'}',
                        style: const TextStyle(color: SJColors.inkSoft, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _link('Alterar senha', () => Navigator.of(context).pushNamed('/change-password')),
                    const SizedBox(height: 6),
                    _link('Sair', _logout),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            InkWell(
              onTap: () => Navigator.of(context).pushNamed('/journeys'),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: SJColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SJColors.line),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Minhas jornadas', style: serif(17)),
                    const Text('→',
                        style: TextStyle(color: SJColors.cyan, fontSize: 18, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Text(_error,
                    textAlign: TextAlign.center, style: const TextStyle(color: SJColors.danger)),
              )
            else if (_map == null)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              AtlasMap(
                data: _map,
                onSelect: (id) => Navigator.of(context).pushNamed('/memory', arguments: id),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _legendDot(SJColors.cyan, 'PONTOS SOLTOS'),
                  const SizedBox(width: 18),
                  _legendDot(SJColors.wine, 'JORNADAS + RASTROS'),
                ],
              ),
              if (count == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: Column(
                    children: [
                      Text('Seu atlas está em branco.', style: serif(18), textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      const Text(
                        'Toque no botão central para registrar a primeira memória.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: SJColors.inkSoft, fontSize: 14, height: 1.45),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _link(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Text(label,
            style: const TextStyle(color: SJColors.cyan, fontSize: 14, fontWeight: FontWeight.w600)),
      );

  Widget _legendDot(Color color, String label) => Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: monoLabel(11, color: SJColors.inkSoft)),
        ],
      );
}
