import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('raw recovery candidates exclude done/trashed and move only selected', () async {
    final tempDir = await Directory.systemTemp.createTemp('th_raw_recovery_');
    final dbPath = '${tempDir.path}/db.db';
    final db = await openDatabase(dbPath, version: 1, onCreate: (db, v) async {
      await db.execute('CREATE TABLE thoughts (id TEXT PRIMARY KEY, content TEXT, title TEXT, created_at INTEGER, bucket TEXT, status TEXT, done INTEGER, trashed INTEGER, updated_at TEXT, updated_by TEXT, revision INTEGER DEFAULT 1, bucket_id TEXT)');
    });
    final cutoff = 1000;
    await db.insert('thoughts', {'id':'1','content':'a','created_at':2000,'bucket':'Raw','status':'active','done':0,'trashed':0});
    await db.insert('thoughts', {'id':'2','content':'b','created_at':2000,'bucket':'Raw','status':'completed','done':1,'trashed':0});
    await db.insert('thoughts', {'id':'3','content':'c','created_at':2000,'bucket':'Raw','status':'vaulted_trash','done':0,'trashed':1});

    final candidates = await db.query('thoughts',
      columns:['id','content','created_at','bucket','status','done','trashed'],
      where:"LOWER(TRIM(COALESCE(bucket,'')))='raw' AND (trashed IS NULL OR trashed=0) AND status != 'vaulted_trash' AND done=0 AND created_at >= ?",
      whereArgs:[cutoff]);
    expect(candidates.map((e)=>e['id']).toList(), ['1']);

    await db.update('thoughts', {'bucket': null, 'bucket_id': null}, where: 'id=?', whereArgs:['1']);
    final row = (await db.query('thoughts', where:'id=?', whereArgs:['1'])).first;
    expect(row['bucket'], isNull);
    await db.close();
    await tempDir.delete(recursive: true);
  });
}
