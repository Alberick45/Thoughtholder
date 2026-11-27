import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../thought_provider.dart';
import '../services/economy_config.dart';
import 'sort_game_service.dart';

class SortGameScreen extends StatefulWidget {
  const SortGameScreen({super.key});
  @override
  State<SortGameScreen> createState() => _SortGameScreenState();
}

class _SortGameScreenState extends State<SortGameScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  int _index = 0;
  final List<String> _sortedIds = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final batch = await SortGameService.instance.pickBatch();
    await SortGameService.instance.markShown(batch.map((e)=>e['id'].toString()).toList());
    if (!mounted) return;
    setState(() { _items = batch; _index = 0; _sortedIds.clear(); _loading = false; });
  }

  Future<void> _assign(String bucket) async {
    if (_index >= _items.length) return;
    final t = _items[_index];
    final id = t['id'].toString();
    await context.read<ThoughtProvider>().fileThought(id, bucket);
    _sortedIds.add(id);
    if (!mounted) return;
    setState(() => _index++);
    if (_index >= _items.length) {
      final res = await SortGameService.instance.completeBatch(sortedIds: _sortedIds);
      if (!mounted) return;
      await showDialog(context: context, builder: (ctx)=>AlertDialog(
        title: const Text('Batch complete'),
        content: Text('Sorted ${res.sortedCount} items. +${res.awardedCoins} coins${res.capReached ? ' (daily cap reached)' : ''}. Balance: ${res.newBalance}.'),
        actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('OK'))],
      ));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThoughtProvider>();
    final colors = AppColors.of(Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light');
    final buckets = provider.buckets.map((b)=>b['name'].toString()).where((n)=>n.toLowerCase()!='raw').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Sort Game')),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : _items.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children:[const Text('No unsorted items ready right now.'), const SizedBox(height:8), ElevatedButton(onPressed: _load, child: const Text('Refresh'))]))
        : _index >= _items.length ? const Center(child: Text('Batch done'))
        : Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children:[
            Text('Item ${_index+1}/${_items.length}  •  +${EconomyConfig.sortBatchReward} coins per batch (cap ${EconomyConfig.dailySortCoinCap}/day)', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Text((_items[_index]['content'] ?? '').toString(), style: const TextStyle(fontSize: 18)))),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in buckets) ElevatedButton(onPressed: ()=>_assign(b), child: Text(b)),
              OutlinedButton(onPressed: ()=>setState(()=>_index = (_index+1).clamp(0,_items.length)), child: const Text('Skip for now')),
            ]),
          ])),
    );
  }
}
