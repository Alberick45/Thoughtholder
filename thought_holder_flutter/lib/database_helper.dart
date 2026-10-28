import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('thoughts.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onOpen: _onOpenDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE thoughts (
  id TEXT PRIMARY KEY,
  thought_id TEXT NOT NULL,
  content TEXT NOT NULL,
  type TEXT NOT NULL,
  status TEXT NOT NULL,
  tags TEXT,
  summary TEXT,
  created_at INTEGER NOT NULL,
  last_viewed_at INTEGER NOT NULL,
  stale_score INTEGER NOT NULL,
  linked_thoughts TEXT,
  bucket TEXT,
  when_val TEXT DEFAULT 'Soon',
  time_val TEXT DEFAULT 'Medium',
  done INTEGER DEFAULT 0,
  trashed INTEGER DEFAULT 0
)
''');

    await db.execute('''
CREATE TABLE buckets (
  name TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL
)
''');

    await _seedDefaultBuckets(db);
  }

  Future<void> _onOpenDB(Database db) async {
    // 1. Verify and migrate columns in thoughts table if needed
    final List<Map<String, dynamic>> columns =
        await db.rawQuery('PRAGMA table_info(thoughts)');
    final existingColNames =
        columns.map((col) => col['name'] as String).toSet();

    if (!existingColNames.contains('bucket')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN bucket TEXT');
    }
    if (!existingColNames.contains('when_val')) {
      await db.execute(
          "ALTER TABLE thoughts ADD COLUMN when_val TEXT DEFAULT 'Soon'");
    }
    if (!existingColNames.contains('time_val')) {
      await db.execute(
          "ALTER TABLE thoughts ADD COLUMN time_val TEXT DEFAULT 'Medium'");
    }
    if (!existingColNames.contains('done')) {
      await db
          .execute('ALTER TABLE thoughts ADD COLUMN done INTEGER DEFAULT 0');
    }
    if (!existingColNames.contains('trashed')) {
      await db.execute(
          'ALTER TABLE thoughts ADD COLUMN trashed INTEGER DEFAULT 0');
    }

    // 2. Data migration from legacy status field
    // Old Done stays Done
    await db.execute(
        "UPDATE thoughts SET done = 1 WHERE status = 'completed' AND (done IS NULL OR done = 0)");
    // Old Trash stays Trash
    await db.execute(
        "UPDATE thoughts SET trashed = 1 WHERE status = 'vaulted_trash' AND (trashed IS NULL OR trashed = 0)");
    // Defaults for null values
    await db.execute(
        "UPDATE thoughts SET when_val = 'Soon' WHERE when_val IS NULL");
    await db.execute(
        "UPDATE thoughts SET time_val = 'Medium' WHERE time_val IS NULL");
    await db.execute("UPDATE thoughts SET done = 0 WHERE done IS NULL");
    await db.execute("UPDATE thoughts SET trashed = 0 WHERE trashed IS NULL");

    // 3. Ensure buckets table exists
    await db.execute('''
CREATE TABLE IF NOT EXISTS buckets (
  name TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL
)
''');

    // 4. Seed default buckets if empty
    final countList =
        await db.rawQuery('SELECT COUNT(*) as count FROM buckets');
    final int count = Sqflite.firstIntValue(countList) ?? 0;
    if (count == 0) {
      await _seedDefaultBuckets(db);
    }
  }

  Future<void> _seedDefaultBuckets(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final defaultBuckets = [
      'School related',
      'Personal revisions',
      'Personal projects',
      "Others' projects",
    ];

    for (int i = 0; i < defaultBuckets.length; i++) {
      await db.insert(
        'buckets',
        {
          'name': defaultBuckets[i],
          'created_at': now + i,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  // --- Thought Operations ---

  Future<void> insertThought(Map<String, dynamic> thought) async {
    final db = await instance.database;
    await db.insert('thoughts', thought,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> fetchAllThoughts() async {
    final db = await instance.database;
    return await db.query('thoughts', orderBy: 'created_at DESC');
  }

  Future<void> updateThoughtStatus(String id, String status) async {
    final db = await instance.database;
    final int done = (status == 'completed') ? 1 : 0;
    final int trashed = (status == 'vaulted_trash') ? 1 : 0;
    await db.update(
      'thoughts',
      {
        'status': status,
        'done': done,
        'trashed': trashed,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateThoughtContent(String id, String content) async {
    final db = await instance.database;
    await db.update(
      'thoughts',
      {'content': content},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateThoughtBucket(String id, String? bucket) async {
    final db = await instance.database;
    await db.update(
      'thoughts',
      {'bucket': bucket},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateThoughtRanking(
    String id, {
    String? whenVal,
    String? timeVal,
  }) async {
    final db = await instance.database;
    final Map<String, dynamic> updates = {};
    if (whenVal != null) updates['when_val'] = whenVal;
    if (timeVal != null) updates['time_val'] = timeVal;
    if (updates.isEmpty) return;

    await db.update(
      'thoughts',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateThoughtDone(String id, bool done) async {
    final db = await instance.database;
    await db.update(
      'thoughts',
      {
        'done': done ? 1 : 0,
        'status': done ? 'completed' : 'active',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateThoughtTrashed(String id, bool trashed) async {
    final db = await instance.database;
    await db.update(
      'thoughts',
      {
        'trashed': trashed ? 1 : 0,
        'status': trashed ? 'vaulted_trash' : 'active',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteThought(String id) async {
    final db = await instance.database;
    await db.delete('thoughts', where: 'id = ?', whereArgs: [id]);
  }

  // --- Bucket Operations ---

  Future<List<String>> fetchBuckets() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> rows =
        await db.query('buckets', orderBy: 'created_at ASC');
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> insertBucket(String name) async {
    final db = await instance.database;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await db.insert(
      'buckets',
      {
        'name': trimmed,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
