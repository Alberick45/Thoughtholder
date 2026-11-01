import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'sync_identity.dart';
import 'utils/title_generator.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static String? _cachedDeviceId;

  DatabaseHelper._init();

  static void setDeviceId(String id) {
    _cachedDeviceId = id;
  }

  static String get currentDeviceId => _cachedDeviceId ?? 'local-device';

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

    String path;
    if (!kIsWeb && Platform.isWindows) {
      final appSupportDir = await getApplicationSupportDirectory();
      final targetDir = Directory(join(appSupportDir.path, 'databases'));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      path = join(targetDir.path, filePath);

      final targetFile = File(path);
      if (!await targetFile.exists() || await targetFile.length() < 1000) {
        final candidatePaths = [
          r'C:\Users\PAAPA\Desktop\testwritingapp\thought_holder_flutter\build\windows\x64\runner\Debug\.dart_tool\sqflite_common_ffi\databases\thoughts.db',
          r'C:\Users\PAAPA\Desktop\testwritingapp\thought_holder_flutter\.dart_tool\sqflite_common_ffi\databases\thoughts.db',
          r'C:\Users\PAAPA\Desktop\testwritingapp\thought_holder_flutter\build\windows\x64\runner\Release\.dart_tool\sqflite_common_ffi\databases\thoughts.db',
          join(Directory.current.path, '.dart_tool', 'sqflite_common_ffi', 'databases', filePath),
        ];

        for (final cand in candidatePaths) {
          final candFile = File(cand);
          if (await candFile.exists() && await candFile.length() > 5000) {
            try {
              await candFile.copy(path);
              break;
            } catch (_) {}
          }
        }
      }
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, filePath);
    }

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onOpen: _onOpenDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // Thoughts table (UPDATE 7 schema with UUID, HLC, revision, title, title_source)
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
  bucket_id TEXT,
  when_val TEXT DEFAULT 'Soon',
  time_val TEXT DEFAULT 'Medium',
  done INTEGER DEFAULT 0,
  trashed INTEGER DEFAULT 0,
  done_at INTEGER,
  trashed_at INTEGER,
  edited_at INTEGER,
  updated_at TEXT,
  updated_by TEXT,
  revision INTEGER DEFAULT 1,
  title TEXT,
  title_source TEXT
)
''');

    // Buckets table (UPDATE 7 schema with UUID id)
    await db.execute('''
CREATE TABLE buckets (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  icon TEXT DEFAULT 'folder',
  created_at INTEGER NOT NULL,
  updated_at TEXT,
  updated_by TEXT,
  revision INTEGER DEFAULT 1
)
''');

    // Deletions / Tombstones table (90-day retention)
    await db.execute('''
CREATE TABLE deleted_records (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  deleted_at INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  updated_by TEXT NOT NULL
)
''');

    // Bucket aliases table (for merged bucket IDs)
    await db.execute('''
CREATE TABLE bucket_aliases (
  alias_id TEXT PRIMARY KEY,
  canonical_id TEXT NOT NULL,
  created_at INTEGER NOT NULL
)
''');
  }

  Future<void> _onOpenDB(Database db) async {
    // 1. Ensure thoughts columns exist
    final List<Map<String, dynamic>> tCols =
        await db.rawQuery('PRAGMA table_info(thoughts)');
    final existingTCols = tCols.map((c) => c['name'] as String).toSet();

    if (!existingTCols.contains('bucket')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN bucket TEXT');
    }
    if (!existingTCols.contains('bucket_id')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN bucket_id TEXT');
    }
    if (!existingTCols.contains('when_val')) {
      await db.execute("ALTER TABLE thoughts ADD COLUMN when_val TEXT DEFAULT 'Soon'");
    }
    if (!existingTCols.contains('time_val')) {
      await db.execute("ALTER TABLE thoughts ADD COLUMN time_val TEXT DEFAULT 'Medium'");
    }
    if (!existingTCols.contains('done')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN done INTEGER DEFAULT 0');
    }
    if (!existingTCols.contains('trashed')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN trashed INTEGER DEFAULT 0');
    }
    if (!existingTCols.contains('done_at')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN done_at INTEGER');
    }
    if (!existingTCols.contains('trashed_at')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN trashed_at INTEGER');
    }
    if (!existingTCols.contains('edited_at')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN edited_at INTEGER');
    }
    if (!existingTCols.contains('updated_at')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN updated_at TEXT');
    }
    if (!existingTCols.contains('updated_by')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN updated_by TEXT');
    }
    if (!existingTCols.contains('revision')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN revision INTEGER DEFAULT 1');
    }
    if (!existingTCols.contains('title')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN title TEXT');
    }
    if (!existingTCols.contains('title_source')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN title_source TEXT');
    }

    // 2. Ensure buckets table and columns exist
    await db.execute('''
CREATE TABLE IF NOT EXISTS buckets (
  name TEXT PRIMARY KEY,
  icon TEXT DEFAULT 'folder',
  created_at INTEGER NOT NULL
)
''');

    final List<Map<String, dynamic>> bCols =
        await db.rawQuery('PRAGMA table_info(buckets)');
    final existingBCols = bCols.map((c) => c['name'] as String).toSet();

    if (!existingBCols.contains('id')) {
      await db.execute('ALTER TABLE buckets ADD COLUMN id TEXT');
    }
    if (!existingBCols.contains('icon')) {
      await db.execute("ALTER TABLE buckets ADD COLUMN icon TEXT DEFAULT 'folder'");
    }
    if (!existingBCols.contains('updated_at')) {
      await db.execute('ALTER TABLE buckets ADD COLUMN updated_at TEXT');
    }
    if (!existingBCols.contains('updated_by')) {
      await db.execute('ALTER TABLE buckets ADD COLUMN updated_by TEXT');
    }
    if (!existingBCols.contains('revision')) {
      await db.execute('ALTER TABLE buckets ADD COLUMN revision INTEGER DEFAULT 1');
    }

    // 3. Ensure deleted_records and bucket_aliases tables exist
    await db.execute('''
CREATE TABLE IF NOT EXISTS deleted_records (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  deleted_at INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  updated_by TEXT NOT NULL
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS bucket_aliases (
  alias_id TEXT PRIMARY KEY,
  canonical_id TEXT NOT NULL,
  created_at INTEGER NOT NULL
)
''');

    // 4. MIGRATION (Section 2): Assign UUIDs, default HLC, and link bucket_ids
    // Assign UUIDs to buckets lacking one
    final bucketRows = await db.query('buckets');
    final bucketNameToId = <String, String>{};

    for (final b in bucketRows) {
      final String? curId = b['id'] as String?;
      final String name = b['name'] as String;
      final String bucketId;
      if (curId == null || curId.isEmpty) {
        bucketId = SyncIdentity.newUuid();
        await db.update(
          'buckets',
          {
            'id': bucketId,
            'updated_at': Hlc.now(currentDeviceId).toString(),
            'updated_by': currentDeviceId,
            'revision': 1,
          },
          where: 'name = ?',
          whereArgs: [name],
        );
      } else {
        bucketId = curId;
      }
      bucketNameToId[name.trim().toLowerCase()] = bucketId;
    }

    // Migrate thoughts: Ensure UUID id, HLC updated_at, revision, and bucket_id
    final thoughtRows = await db.query('thoughts');
    for (final t in thoughtRows) {
      final String id = t['id'] as String;
      final updates = <String, dynamic>{};

      // Ensure updated_at exists
      if (t['updated_at'] == null || (t['updated_at'] as String).isEmpty) {
        final int timeVal = (t['edited_at'] as num?)?.toInt() ??
            (t['created_at'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;
        updates['updated_at'] = Hlc(millis: timeVal, counter: 0, nodeId: currentDeviceId).toString();
        updates['updated_by'] = currentDeviceId;
        updates['revision'] = 1;
      }

      // Link bucket_id if bucket name exists
      final String? bName = t['bucket'] as String?;
      if (bName != null && bName.trim().isNotEmpty) {
        final String? matchedId = bucketNameToId[bName.trim().toLowerCase()];
        if (matchedId != null && (t['bucket_id'] == null || (t['bucket_id'] as String).isEmpty)) {
          updates['bucket_id'] = matchedId;
        }
      }

      if (updates.isNotEmpty) {
        await db.update('thoughts', updates, where: 'id = ?', whereArgs: [id]);
      }
    }
  }

  // --- Thought Operations ---

  Future<void> insertThought(Map<String, dynamic> thought, {String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    final mutable = Map<String, dynamic>.from(thought);

    if (mutable['id'] == null || (mutable['id'] as String).isEmpty) {
      mutable['id'] = SyncIdentity.newUuid();
    }
    if (mutable['updated_at'] == null) {
      mutable['updated_at'] = Hlc.now(node).toString();
    }
    if (mutable['updated_by'] == null) {
      mutable['updated_by'] = node;
    }
    if (mutable['revision'] == null) {
      mutable['revision'] = 1;
    }

    await db.insert('thoughts', mutable, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> fetchAllThoughts() async {
    final db = await instance.database;
    return await db.query('thoughts', orderBy: 'created_at DESC');
  }

  Future<void> updateThoughtStatus(String id, String status, {String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    final int done = (status == 'completed') ? 1 : 0;
    final int trashed = (status == 'vaulted_trash') ? 1 : 0;
    final int now = DateTime.now().millisecondsSinceEpoch;

    await db.rawUpdate('''
UPDATE thoughts SET
  status = ?,
  done = ?,
  trashed = ?,
  done_at = ?,
  trashed_at = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [
      status,
      done,
      trashed,
      done == 1 ? now : null,
      trashed == 1 ? now : null,
      Hlc.now(node).toString(),
      node,
      id,
    ]);
  }

  Future<void> updateThoughtContent(String id, String content,
      {int? editedAt, String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    final now = editedAt ?? DateTime.now().millisecondsSinceEpoch;

    // Check title_source to preserve user-assigned titles
    final rows = await db.query(
      'thoughts',
      columns: ['title', 'title_source'],
      where: 'id = ?',
      whereArgs: [id],
    );
    final source = rows.isNotEmpty ? (rows.first['title_source'] as String?) : null;

    if (source == null || source == 'auto') {
      final newTitle = TitleGenerator.generate(content);
      await db.rawUpdate('''
UPDATE thoughts SET
  content = ?,
  title = ?,
  title_source = 'auto',
  edited_at = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [content, newTitle, now, Hlc.now(node).toString(), node, id]);
    } else {
      await db.rawUpdate('''
UPDATE thoughts SET
  content = ?,
  edited_at = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [content, now, Hlc.now(node).toString(), node, id]);
    }
  }

  Future<void> updateThoughtTitle(String id, String title,
      {String titleSource = 'user', String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;

    await db.rawUpdate('''
UPDATE thoughts SET
  title = ?,
  title_source = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [title.trim(), titleSource, Hlc.now(node).toString(), node, id]);
  }

  /// Populates missing titles for up to [batchSize] thoughts at a time in background
  Future<int> populateMissingTitlesBatch({int batchSize = 200}) async {
    final db = await instance.database;
    final rows = await db.query(
      'thoughts',
      columns: ['id', 'content'],
      where: 'title IS NULL OR trim(title) = ?',
      whereArgs: [''],
      limit: batchSize,
    );
    if (rows.isEmpty) return 0;

    final batch = db.batch();
    for (final row in rows) {
      final id = row['id'] as String;
      final content = (row['content'] as String?) ?? '';
      final autoTitle = TitleGenerator.generate(content);
      batch.rawUpdate(
        'UPDATE thoughts SET title = ?, title_source = ? WHERE id = ?',
        [autoTitle, 'auto', id],
      );
    }
    await batch.commit(noResult: true);
    return rows.length;
  }

  Future<void> updateThoughtBucket(String id, String? bucket,
      {String? bucketId, String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;

    String? resolvedBucketId = bucketId;
    if (resolvedBucketId == null && bucket != null && bucket.trim().isNotEmpty) {
      final bRows = await db.query('buckets',
          columns: ['id'], where: 'name = ?', whereArgs: [bucket.trim()]);
      if (bRows.isNotEmpty) {
        resolvedBucketId = bRows.first['id'] as String?;
      }
    }

    await db.rawUpdate('''
UPDATE thoughts SET
  bucket = ?,
  bucket_id = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [bucket, resolvedBucketId, Hlc.now(node).toString(), node, id]);
  }

  Future<void> updateThoughtRanking(
    String id, {
    String? whenVal,
    String? timeVal,
    String? deviceId,
  }) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;

    final existing = await db.query('thoughts',
        columns: ['when_val', 'time_val'], where: 'id = ?', whereArgs: [id]);
    if (existing.isEmpty) return;

    final newWhen = whenVal ?? (existing.first['when_val'] as String? ?? 'Soon');
    final newTime = timeVal ?? (existing.first['time_val'] as String? ?? 'Medium');

    await db.rawUpdate('''
UPDATE thoughts SET
  when_val = ?,
  time_val = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [newWhen, newTime, Hlc.now(node).toString(), node, id]);
  }

  Future<void> updateThoughtDone(String id, bool done, {String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    final int now = DateTime.now().millisecondsSinceEpoch;

    await db.rawUpdate('''
UPDATE thoughts SET
  done = ?,
  status = ?,
  done_at = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [
      done ? 1 : 0,
      done ? 'completed' : 'active',
      done ? now : null,
      Hlc.now(node).toString(),
      node,
      id,
    ]);
  }

  Future<void> updateThoughtTrashed(String id, bool trashed, {String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    final int now = DateTime.now().millisecondsSinceEpoch;

    await db.rawUpdate('''
UPDATE thoughts SET
  trashed = ?,
  status = ?,
  trashed_at = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [
      trashed ? 1 : 0,
      trashed ? 'vaulted_trash' : 'active',
      trashed ? now : null,
      Hlc.now(node).toString(),
      node,
      id,
    ]);
  }

  /// Delete forever creates a tombstone record (Section 6)
  Future<void> deleteThought(String id, {String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlcStr = Hlc.now(node).toString();

    await db.transaction((txn) async {
      await txn.insert(
        'deleted_records',
        {
          'id': id,
          'type': 'thought',
          'deleted_at': now,
          'updated_at': hlcStr,
          'updated_by': node,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('thoughts', where: 'id = ?', whereArgs: [id]);
    });
  }

  // --- Bucket Operations ---

  Future<List<Map<String, dynamic>>> fetchBuckets() async {
    final db = await instance.database;
    return await db.query('buckets', orderBy: 'created_at ASC');
  }

  Future<String> insertBucket(String name,
      {String icon = 'folder', String? id, String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';

    final bucketId = id ?? SyncIdentity.newUuid();
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'buckets',
      {
        'id': bucketId,
        'name': trimmed,
        'icon': icon,
        'created_at': now,
        'updated_at': Hlc.now(node).toString(),
        'updated_by': node,
        'revision': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return bucketId;
  }

  Future<void> renameBucket(String oldName, String newName, {String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;

    await db.transaction((txn) async {
      await txn.rawUpdate('''
UPDATE buckets SET
  name = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE name = ?
''', [trimmed, Hlc.now(node).toString(), node, oldName]);

      await txn.update('thoughts', {'bucket': trimmed},
          where: 'bucket = ?', whereArgs: [oldName]);
    });
  }

  Future<void> updateBucketIcon(String name, String icon, {String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;

    await db.rawUpdate('''
UPDATE buckets SET
  icon = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE name = ?
''', [icon, Hlc.now(node).toString(), node, name]);
  }

  /// Deleting a bucket creates a tombstone and returns its thoughts to Unsorted (Section 4 & 6)
  Future<int> deleteBucket(String name, {String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlcStr = Hlc.now(node).toString();
    int unfiledCount = 0;

    await db.transaction((txn) async {
      final rows = await txn.query('buckets', where: 'name = ?', whereArgs: [name]);
      if (rows.isNotEmpty) {
        final bId = rows.first['id'] as String? ?? name;
        await txn.insert(
          'deleted_records',
          {
            'id': bId,
            'type': 'bucket',
            'deleted_at': now,
            'updated_at': hlcStr,
            'updated_by': node,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      unfiledCount = await txn.update(
        'thoughts',
        {'bucket': null, 'bucket_id': null},
        where: 'bucket = ?',
        whereArgs: [name],
      );
      await txn.delete('buckets', where: 'name = ?', whereArgs: [name]);
    });
    return unfiledCount;
  }

  // --- Tombstones & Aliases ---

  Future<List<Map<String, dynamic>>> fetchTombstones() async {
    final db = await instance.database;
    return await db.query('deleted_records');
  }

  Future<List<Map<String, dynamic>>> fetchAliases() async {
    final db = await instance.database;
    return await db.query('bucket_aliases');
  }

  // --- Snapshot Backups (Section 5: 7-Day Undo Retention) ---

  static Future<Directory> getSnapshotDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(join(support.path, 'sync_snapshots'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> createSyncSnapshot() async {
    final db = await instance.database;
    final thoughts = await db.query('thoughts');
    final buckets = await db.query('buckets');
    final tombstones = await db.query('deleted_records');
    final aliases = await db.query('bucket_aliases');

    final data = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'thoughts': thoughts,
      'buckets': buckets,
      'deleted_records': tombstones,
      'bucket_aliases': aliases,
    };

    final dir = await getSnapshotDir();
    final now = DateTime.now().millisecondsSinceEpoch;
    final file = File(join(dir.path, 'snapshot_$now.json'));
    await file.writeAsString(json.encode(data));

    // Clean snapshots older than 7 days
    await pruneOldSnapshots();
    return file.path;
  }

  Future<bool> restoreLatestSnapshot() async {
    final dir = await getSnapshotDir();
    if (!await dir.exists()) return false;

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => basename(f.path).startsWith('snapshot_') && f.path.endsWith('.json'))
        .toList();

    if (files.isEmpty) return false;

    files.sort((a, b) => b.path.compareTo(a.path)); // Most recent first
    final latestFile = files.first;

    final content = await latestFile.readAsString();
    final Map<String, dynamic> data = json.decode(content);

    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('thoughts');
      await txn.delete('buckets');
      await txn.delete('deleted_records');
      await txn.delete('bucket_aliases');

      for (final t in (data['thoughts'] as List? ?? [])) {
        await txn.insert('thoughts', Map<String, dynamic>.from(t));
      }
      for (final b in (data['buckets'] as List? ?? [])) {
        await txn.insert('buckets', Map<String, dynamic>.from(b));
      }
      for (final d in (data['deleted_records'] as List? ?? [])) {
        await txn.insert('deleted_records', Map<String, dynamic>.from(d));
      }
      for (final a in (data['bucket_aliases'] as List? ?? [])) {
        await txn.insert('bucket_aliases', Map<String, dynamic>.from(a));
      }
    });

    return true;
  }

  Future<void> pruneOldSnapshots() async {
    try {
      final dir = await getSnapshotDir();
      if (!await dir.exists()) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final sevenDaysMs = 7 * 24 * 60 * 60 * 1000;

      for (final file in dir.listSync().whereType<File>()) {
        final name = basename(file.path);
        if (name.startsWith('snapshot_') && name.endsWith('.json')) {
          final timeStr = name.replaceAll('snapshot_', '').replaceAll('.json', '');
          final time = int.tryParse(timeStr);
          if (time != null && (now - time > sevenDaysMs)) {
            try {
              file.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }
}
