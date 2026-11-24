import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thought_holder_flutter/services/database_migration_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
      'v5 migration is idempotent even when _onOpenDB already added columns',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('th_v5_migration_');
    final dbPath = '${tempDir.path}/test.db';
    final backupDir = '${tempDir.path}/backups';

    final db = await openDatabase(
      dbPath,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE thoughts (
            id TEXT PRIMARY KEY,
            thought_id TEXT NOT NULL,
            content TEXT NOT NULL,
            type TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at TEXT,
            updated_by TEXT,
            revision INTEGER DEFAULT 1,
            bucket TEXT,
            done INTEGER DEFAULT 0,
            trashed INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE buckets (
            name TEXT NOT NULL,
            icon TEXT DEFAULT 'folder',
            created_at INTEGER NOT NULL,
            updated_at TEXT,
            updated_by TEXT,
            revision INTEGER DEFAULT 1
          )
        ''');
        await db.insert('thoughts', {
          'id': 'keep-me',
          'thought_id': 'LOG-1',
          'content': 'Preserve this row',
          'type': 'thought',
          'status': 'active',
          'created_at': 1700000000000,
          'bucket': 'Work',
        });
      },
    );

    // Simulate DatabaseHelper._onOpenDB adding the v5 columns before migrations.
    await db.execute('ALTER TABLE thoughts ADD COLUMN recurrence TEXT');
    await db.execute('ALTER TABLE thoughts ADD COLUMN last_completed_at INTEGER');
    await db.execute('ALTER TABLE thoughts ADD COLUMN reminder_at INTEGER');
    await db.execute('ALTER TABLE buckets ADD COLUMN id TEXT');
    await db.execute("ALTER TABLE buckets ADD COLUMN type TEXT DEFAULT 'normal'");

    await DatabaseMigrationService.instance
        .runMigrations(db, dbPath, backupDirectoryPath: backupDir);

    var versionRows = await db.rawQuery('PRAGMA user_version');
    expect(versionRows.first.values.first, 5);

    final thoughtCols = (await db.rawQuery('PRAGMA table_info(thoughts)'))
        .map((r) => r['name'])
        .toSet();
    expect(thoughtCols, contains('due_at'));

    final rows = await db.query('thoughts', where: 'id = ?', whereArgs: ['keep-me']);
    expect(rows, hasLength(1));
    expect(rows.first['content'], 'Preserve this row');

    final buckets = await db.query('buckets');
    final names = buckets.map((b) => (b['name'] as String).toLowerCase()).toSet();
    expect(names, containsAll(<String>['raw', 'main', 'sides']));

    // Re-run case 5 by rewinding only user_version; columns already exist.
    await db.execute('PRAGMA user_version = 4');
    await DatabaseMigrationService.instance
        .runMigrations(db, dbPath, backupDirectoryPath: backupDir);

    versionRows = await db.rawQuery('PRAGMA user_version');
    expect(versionRows.first.values.first, 5);

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
