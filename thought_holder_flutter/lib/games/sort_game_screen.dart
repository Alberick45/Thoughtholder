import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../thought_provider.dart';
import '../services/economy_config.dart';
import '../settings_service.dart';
import '../settings/create_bucket_sheet.dart';
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
  bool _expanded = false;
  String _bucketQuery = '';
  final List<String> _sortedIds = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final batch = await SortGameService.instance.pickBatch();
    await SortGameService.instance.markShown(batch.map((e)=>e['id'].toString()).toList());
    if (!mounted) return;
    setState(() { _items = batch; _index = 0; _expanded = false; _sortedIds.clear(); _loading = false; });
  }

  Future<void> _finishIfDone() async {
    if (_index < _items.length) return;
    final settings = context.read<SettingsService>();
    if (_sortedIds.isNotEmpty) {
      await settings.recordSortGameSorted(_sortedIds.length);
    }
    final dailySorted = settings.sortGameSortedToday();
    final requiredDaily = EconomyConfig.sortBatchSize;
    final shouldAward = dailySorted >= requiredDaily && _sortedIds.isNotEmpty;
    final res = shouldAward
        ? await SortGameService.instance.completeBatch(sortedIds: _sortedIds, requiredCount: 1)
        : await SortGameService.instance.completeBatch(sortedIds: const [], requiredCount: 999);
    if (!mounted) return;
    final msg = shouldAward
        ? 'Sorted ${_sortedIds.length} this batch. Today: $dailySorted/$requiredDaily. +${res.awardedCoins} coins${res.capReached ? ' (daily cap reached)' : ''}. Balance: ${res.newBalance}.'
        : 'Sorted ${_sortedIds.length} this batch. Today: $dailySorted/$requiredDaily. Sort $requiredDaily total today to earn coins. You can leave and come back.';
    await showDialog(context: context, builder: (ctx)=>AlertDialog(
      title: Text(shouldAward ? 'Progress saved' : 'Batch paused'),
      content: Text(msg),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('OK'))],
    ));
    _load();
  }

  void _next() { setState(() { _index++; _expanded = false; }); }

  Future<void> _assign(String bucket) async {
    if (_index >= _items.length) return;
    final t = _items[_index];
    final id = t['id'].toString();
    await context.read<ThoughtProvider>().fileThought(id, bucket);
    _sortedIds.add(id);
    if (!mounted) return;
    _next();
    await _finishIfDone();
  }

  Future<void> _trash() async {
    if (_index >= _items.length) return;
    final t = _items[_index];
    final id = t['id'].toString();
    await context.read<ThoughtProvider>().moveToTrash(id);
    if (!mounted) return;
    _next();
    await _finishIfDone();
  }

  Future<void> _skip() async {
    if (_index >= _items.length) return;
    final t = _items[_index];
    final id = t['id'].toString();
    await SortGameService.instance.clearShown([id]); // allow it to reappear later; not counted as sorted
    if (!mounted) return;
    _next();
    await _finishIfDone();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThoughtProvider>();
    final settings = context.watch<SettingsService>();
    final buckets = provider.getOrderedBuckets(settings.bucketOrder).map((b)=>b['name'].toString()).where((n)=>n.toLowerCase()!='raw').where((n)=>n.toLowerCase().contains(_bucketQuery.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Sort Game')),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : _items.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children:[const Text('No unsorted items ready right now.'), const SizedBox(height:8), ElevatedButton(onPressed: _load, child: const Text('Refresh'))]))
        : _index >= _items.length ? const Center(child: Text('Batch done'))
        : SafeArea(child: ListView(padding: const EdgeInsets.all(16), children:[
            Builder(builder: (ctx){
              final s = ctx.watch<SettingsService>();
              final today = s.sortGameSortedToday();
              final need = EconomyConfig.sortBatchSize;
              return Text('Item ${_index+1}/${_items.length}  •  Today sorted: $today/$need for coins (cap ${EconomyConfig.dailySortCoinCap}/day)', style: const TextStyle(fontSize: 12));
            }),
            const SizedBox(height: 12),
            Card(child: SizedBox(height: 170, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
              Expanded(child: SingleChildScrollView(child: Text((_items[_index]['content'] ?? '').toString(), style: const TextStyle(fontSize: 18), maxLines: _expanded ? null : 4, overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis))),
              Align(alignment: Alignment.centerRight, child: TextButton(onPressed: ()=>setState(()=>_expanded=!_expanded), child: Text(_expanded ? 'Show less' : 'Read more'))),
            ])))),
            const SizedBox(height: 12),
            Text('Sorted this batch: ${_sortedIds.length}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search buckets...', isDense: true, border: OutlineInputBorder()), onChanged: (v)=>setState(()=>_bucketQuery=v)),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: buckets.isEmpty
                ? const Center(child: Text('No buckets match. Create one.'))
                : ListView.builder(
                    itemCount: buckets.length,
                    itemBuilder: (ctx, i) {
                      final b = buckets[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ElevatedButton(onPressed: ()=>_assign(b), child: Align(alignment: Alignment.centerLeft, child: Text(b))),
                      );
                    },
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('New bucket'), onPressed: () async {
                final colors = AppColors.of(Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light');
                final name = await showCreateBucketSheet(context, provider, colors);
                if (name != null && mounted) await _assign(name);
              }),
              OutlinedButton(onPressed: _trash, child: const Text('Trash')),
              OutlinedButton(onPressed: _skip, child: const Text('Skip for now')),
            ]),
          ])),
    );
  }
}
