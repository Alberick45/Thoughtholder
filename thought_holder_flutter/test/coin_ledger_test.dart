import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('coin ledger awards, spends atomically, and never goes negative', () async {
    final tempDir = await Directory.systemTemp.createTemp('th_coin_ledger_');
    final dbPath = '${tempDir.path}/coins.db';
    final db = await openDatabase(dbPath, version: 1, onCreate: (db, v) async {
      await db.execute('CREATE TABLE coin_ledger (id TEXT PRIMARY KEY, delta INTEGER NOT NULL, reason TEXT NOT NULL, ref_id TEXT, created_at INTEGER NOT NULL)');
      await db.execute('CREATE UNIQUE INDEX idx_coin_ledger_ref_id_unique ON coin_ledger(ref_id) WHERE ref_id IS NOT NULL');
    });

    await db.insert('coin_ledger', {'id':'a1','delta':30,'reason':'daily_goal','ref_id':'d1','created_at':1});
    final bal1 = Sqflite.firstIntValue(await db.rawQuery('SELECT COALESCE(SUM(delta),0) FROM coin_ledger')) ?? 0;
    expect(bal1, 30);

    // atomic spend should fail when insufficient
    var threw = false;
    try {
      await db.transaction((txn) async {
        final b = Sqflite.firstIntValue(await txn.rawQuery('SELECT COALESCE(SUM(delta),0) FROM coin_ledger')) ?? 0;
        if (b < 50) throw StateError('insufficient');
        await txn.insert('coin_ledger', {'id':'s1','delta':-50,'reason':'shop','ref_id':'x','created_at':2});
      });
    } catch (_) {
      threw = true;
    }
    expect(threw, isTrue);
    final bal2 = Sqflite.firstIntValue(await db.rawQuery('SELECT COALESCE(SUM(delta),0) FROM coin_ledger')) ?? 0;
    expect(bal2, 30);

    await db.transaction((txn) async {
      final b = Sqflite.firstIntValue(await txn.rawQuery('SELECT COALESCE(SUM(delta),0) FROM coin_ledger')) ?? 0;
      if (b < 10) throw StateError('insufficient');
      await txn.insert('coin_ledger', {'id':'s2','delta':-10,'reason':'shop','ref_id':'x2','created_at':3});
    });
    final bal3 = Sqflite.firstIntValue(await db.rawQuery('SELECT COALESCE(SUM(delta),0) FROM coin_ledger')) ?? 0;
    expect(bal3, 20);

    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('duplicate reward ref_id fails at database level', () async {
    final tempDir = await Directory.systemTemp.createTemp('th_coin_unique_');
    final dbPath = '${tempDir.path}/coins.db';
    final db = await openDatabase(dbPath, version: 1, onCreate: (db, v) async {
      await db.execute('CREATE TABLE coin_ledger (id TEXT PRIMARY KEY, delta INTEGER NOT NULL, reason TEXT NOT NULL, ref_id TEXT, created_at INTEGER NOT NULL)');
      await db.execute('CREATE UNIQUE INDEX idx_coin_ledger_ref_id_unique ON coin_ledger(ref_id) WHERE ref_id IS NOT NULL');
    });
    await db.insert('coin_ledger', {'id':'a1','delta':25,'reason':'daily_goal_complete','ref_id':'daily_goal:2026-11-27','created_at':1});
    var threw = false;
    try {
      await db.insert('coin_ledger', {'id':'a2','delta':25,'reason':'daily_goal_complete','ref_id':'daily_goal:2026-11-27','created_at':2});
    } catch (_) {
      threw = true;
    }
    expect(threw, isTrue);
    final bal = Sqflite.firstIntValue(await db.rawQuery('SELECT COALESCE(SUM(delta),0) FROM coin_ledger')) ?? 0;
    expect(bal, 25);
    await db.close();
    await tempDir.delete(recursive: true);
  });
}
