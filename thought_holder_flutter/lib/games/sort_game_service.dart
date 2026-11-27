import 'dart:math';
import '../database_helper.dart';
import '../services/economy_config.dart';
import '../models/sort_game_result.dart';

class SortGameService {
  SortGameService._();
  static final SortGameService instance = SortGameService._();

  Future<List<Map<String, dynamic>>> pickBatch({int size = EconomyConfig.sortBatchSize}) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cooldownMs = EconomyConfig.reviewItemCooldownDays * 24 * 60 * 60 * 1000;
    final rows = await db.rawQuery('''
      SELECT * FROM thoughts
      WHERE (bucket IS NULL OR TRIM(bucket)='') AND (trashed IS NULL OR trashed=0) AND (done IS NULL OR done=0) AND status != 'vaulted_trash'
        AND (COALESCE(sort_last_shown_at,0)=0 OR ? - sort_last_shown_at >= ?)
      ORDER BY created_at DESC
      LIMIT ?
    ''', [now, cooldownMs, size]);
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> markShown(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final id in ids) {
      batch.rawUpdate('UPDATE thoughts SET sort_last_shown_at=? WHERE id=?', [now, id]);
    }
    await batch.commit(noResult: true);
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
  }

  Future<int> awardedToday() async {
    final db = await DatabaseHelper.instance.database;
    final day = _today();
    final start = DateTime.parse(day).millisecondsSinceEpoch;
    final end = start + 24*60*60*1000;
    final res = await db.rawQuery("SELECT COALESCE(SUM(delta),0) AS s FROM coin_ledger WHERE reason='sort_game' AND created_at>=? AND created_at<?", [start, end]);
    final v = (res.first['s'] as num?)?.toInt() ?? 0;
    return v;
  }

  Future<SortGameResult> completeBatch({required List<String> sortedIds}) async {
    if (sortedIds.isEmpty) return SortGameResult(awardedCoins: 0, newBalance: await DatabaseHelper.instance.fetchCoinBalance(), capReached: false, sortedCount: 0);
    final today = _today();
    final already = await awardedToday();
    final remaining = max(0, EconomyConfig.dailySortCoinCap - already);
    final award = min(EconomyConfig.sortBatchReward, remaining);
    final idempotency = 'sort_batch:$today:${sortedIds.toSet().join(',')}';
    int newBal = await DatabaseHelper.instance.fetchCoinBalance();
    if (award > 0) {
      newBal = await DatabaseHelper.instance.awardCoins(amount: award, reason: 'sort_game', refId: idempotency, idempotencyKey: idempotency);
    }
    return SortGameResult(awardedCoins: award, newBalance: newBal, capReached: already + award >= EconomyConfig.dailySortCoinCap, sortedCount: sortedIds.length);
  }
}
