import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'sync_identity.dart';
import 'utils/title_generator.dart';
import 'utils/app_logger.dart';
import 'services/database_migration_service.dart';

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

  /// Returns the resolved absolute file path of the database.
  Future<String> getDatabasePath([String filePath = 'thoughts.db']) async {
    if (!kIsWeb && Platform.isWindows) {
      final appSupportDir = await getApplicationSupportDirectory();
      final targetDir = Directory(join(appSupportDir.path, 'databases'));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      return join(targetDir.path, filePath);
    } else {
      final dbPath = await getDatabasesPath();
      return join(dbPath, filePath);
    }
  }

  /// Closes the active database connection safely and resets the handle.
  Future<void> close() async {
    if (_database != null) {
      if (_database!.isOpen) {
        await _database!.close();
      }
      _database = null;
    }
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
      version: 7,
      onCreate: (db, version) async {
        await _createDB(db, version);
        await db.execute('PRAGMA user_version = 7');
      },
      onOpen: (db) async {
        await _onOpenDB(db);
        await DatabaseMigrationService.instance.runMigrations(db, path);
      },
    );
  }

  Future _createDB(Database db, int version) async {
    // Thoughts table (UPDATE 7 + V5 schema with recurrence, last_completed_at, reminder_at)
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
  title_source TEXT,
  skipped_at INTEGER,
  skip_count INTEGER DEFAULT 0,
  is_pinned INTEGER DEFAULT 0,
  board_position INTEGER DEFAULT -1,
  pinned_at INTEGER,
  recurrence TEXT,
  last_completed_at INTEGER,
  reminder_at INTEGER,
  due_at INTEGER,
  action_text TEXT,
  measure_text TEXT,
  deadline_at INTEGER,
  trigger_text TEXT,
  intent_type TEXT DEFAULT 'unknown',
  sub_steps TEXT,
  next_sub_step_index INTEGER DEFAULT 0,
  goal_target INTEGER,
  goal_unit TEXT,
  intent_confidence REAL DEFAULT 0
)
''');

    // Buckets table (UPDATE 7 + V5 schema with type)
    await db.execute('''
CREATE TABLE buckets (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT DEFAULT 'normal',
  icon TEXT DEFAULT 'folder',
  created_at INTEGER NOT NULL,
  updated_at TEXT,
  updated_by TEXT,
  revision INTEGER DEFAULT 1
)
''');

    // Seed Raw, Main, Sides system buckets
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final systemBuckets = [
      {'name': 'Raw', 'type': 'raw', 'icon': 'inbox'},
      {'name': 'Main', 'type': 'main', 'icon': 'star'},
      {'name': 'Sides', 'type': 'sides', 'icon': 'list'},
    ];
    for (final sys in systemBuckets) {
      final id = 'bucket_${sys['name']!.toLowerCase()}';
      await db.insert('buckets', {
        'id': id,
        'name': sys['name'],
        'type': sys['type'],
        'icon': sys['icon'],
        'created_at': nowMs,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': 'system',
        'revision': 1,
      });
    }

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

    // Voice recordings table (Part 2: Never Lose a Voice Note)
    await db.execute('''
CREATE TABLE voice_recordings (
  id TEXT PRIMARY KEY,
  file_path TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  status TEXT NOT NULL,
  total_segments INTEGER DEFAULT 1,
  completed_segments INTEGER DEFAULT 0,
  error_message TEXT,
  transcript TEXT,
  associated_thought_id TEXT,
  audio_kept_until INTEGER
)
''');

    // Voice segments table
    await db.execute('''
CREATE TABLE voice_segments (
  id TEXT PRIMARY KEY,
  recording_id TEXT NOT NULL,
  segment_index INTEGER NOT NULL,
  file_path TEXT NOT NULL,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  status TEXT NOT NULL,
  transcript TEXT,
  error_message TEXT,
  retry_count INTEGER DEFAULT 0
)
''');

    await db.execute('''
CREATE TABLE daily_goals (
  date TEXT PRIMARY KEY,
  tasks_completed INTEGER DEFAULT 0,
  goal INTEGER DEFAULT 4,
  xp_earned INTEGER DEFAULT 0,
  goal_reached INTEGER DEFAULT 0,
  rest_day INTEGER DEFAULT 0,
  completed_thought_ids TEXT DEFAULT ''
)
''');

    await db.execute('''
CREATE TABLE gamification_meta (
  key TEXT PRIMARY KEY,
  value TEXT
)
''');

    await db.execute('''
CREATE TABLE coin_ledger (
  id TEXT PRIMARY KEY,
  delta INTEGER NOT NULL,
  reason TEXT NOT NULL,
  ref_id TEXT,
  idempotency_key TEXT,
  created_at INTEGER NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_coin_ledger_created_at ON coin_ledger(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_coin_ledger_reason ON coin_ledger(reason)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_coin_ledger_ref_id_unique ON coin_ledger(ref_id) WHERE ref_id IS NOT NULL',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_coin_ledger_idempotency_key_unique ON coin_ledger(idempotency_key) WHERE idempotency_key IS NOT NULL',
    );

    // Indexes for fast querying
    await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_bucket ON thoughts(bucket)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_status_done ON thoughts(status, done)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_created_at ON thoughts(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_trashed ON thoughts(trashed)');
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
    if (!existingTCols.contains('skipped_at')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN skipped_at INTEGER');
    }
    if (!existingTCols.contains('skip_count')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN skip_count INTEGER DEFAULT 0');
    }
    if (!existingTCols.contains('is_pinned')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN is_pinned INTEGER DEFAULT 0');
    }
    if (!existingTCols.contains('board_position')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN board_position INTEGER DEFAULT -1');
    }
    if (!existingTCols.contains('pinned_at')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN pinned_at INTEGER');
    }
    if (!existingTCols.contains('recurrence')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN recurrence TEXT');
    }
    if (!existingTCols.contains('last_completed_at')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN last_completed_at INTEGER');
    }
    if (!existingTCols.contains('reminder_at')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN reminder_at INTEGER');
    }
    if (!existingTCols.contains('due_at')) {
      await db.execute('ALTER TABLE thoughts ADD COLUMN due_at INTEGER');
    }
    for (final col in <String, String>{
      'action_text': 'ALTER TABLE thoughts ADD COLUMN action_text TEXT',
      'measure_text': 'ALTER TABLE thoughts ADD COLUMN measure_text TEXT',
      'deadline_at': 'ALTER TABLE thoughts ADD COLUMN deadline_at INTEGER',
      'trigger_text': 'ALTER TABLE thoughts ADD COLUMN trigger_text TEXT',
      'intent_type': "ALTER TABLE thoughts ADD COLUMN intent_type TEXT DEFAULT 'unknown'",
      'sub_steps': 'ALTER TABLE thoughts ADD COLUMN sub_steps TEXT',
      'next_sub_step_index': 'ALTER TABLE thoughts ADD COLUMN next_sub_step_index INTEGER DEFAULT 0',
      'goal_target': 'ALTER TABLE thoughts ADD COLUMN goal_target INTEGER',
      'goal_unit': 'ALTER TABLE thoughts ADD COLUMN goal_unit TEXT',
      'intent_confidence': 'ALTER TABLE thoughts ADD COLUMN intent_confidence REAL DEFAULT 0',
    }.entries) {
      if (!existingTCols.contains(col.key)) await db.execute(col.value);
    }

    // Ensure voice_recordings and voice_segments tables exist
    await db.execute('''
CREATE TABLE IF NOT EXISTS voice_recordings (
  id TEXT PRIMARY KEY,
  file_path TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  status TEXT NOT NULL,
  total_segments INTEGER DEFAULT 1,
  completed_segments INTEGER DEFAULT 0,
  error_message TEXT,
  transcript TEXT,
  associated_thought_id TEXT,
  audio_kept_until INTEGER
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS voice_segments (
  id TEXT PRIMARY KEY,
  recording_id TEXT NOT NULL,
  segment_index INTEGER NOT NULL,
  file_path TEXT NOT NULL,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  status TEXT NOT NULL,
  transcript TEXT,
  error_message TEXT,
  retry_count INTEGER DEFAULT 0
)
''');

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
    if (!existingBCols.contains('type')) {
      await db.execute("ALTER TABLE buckets ADD COLUMN type TEXT DEFAULT 'normal'");
    }

    // Seed Raw, Main, Sides system buckets if not present
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final systemBuckets = [
      {'name': 'Raw', 'type': 'raw', 'icon': 'inbox'},
      {'name': 'Main', 'type': 'main', 'icon': 'star'},
      {'name': 'Sides', 'type': 'sides', 'icon': 'list'},
    ];
    for (final sys in systemBuckets) {
      final existing = await db.query(
        'buckets',
        where: 'LOWER(name) = ?',
        whereArgs: [sys['name']!.toLowerCase()],
      );
      if (existing.isNotEmpty) {
        final currentType = existing.first['type']?.toString();
        if (currentType != sys['type']) {
          await db.update(
            'buckets',
            {'type': sys['type']},
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }
      } else {
        await db.insert('buckets', {
          'id': 'bucket_${sys['name']!.toLowerCase()}',
          'name': sys['name'],
          'type': sys['type'],
          'icon': sys['icon'],
          'created_at': nowMs,
          'updated_at': DateTime.now().toIso8601String(),
          'updated_by': 'system',
          'revision': 1,
        });
      }
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

    // Ensure gamification tables exist (included in database backups)
    await db.execute('''
CREATE TABLE IF NOT EXISTS daily_goals (
  date TEXT PRIMARY KEY,
  tasks_completed INTEGER DEFAULT 0,
  goal INTEGER DEFAULT 4,
  xp_earned INTEGER DEFAULT 0,
  goal_reached INTEGER DEFAULT 0,
  rest_day INTEGER DEFAULT 0,
  completed_thought_ids TEXT DEFAULT ''
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS gamification_meta (
  key TEXT PRIMARY KEY,
  value TEXT
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS coin_ledger (
  id TEXT PRIMARY KEY,
  delta INTEGER NOT NULL,
  reason TEXT NOT NULL,
  ref_id TEXT,
  idempotency_key TEXT,
  created_at INTEGER NOT NULL
)
''');
    final coinCols = (await db.rawQuery('PRAGMA table_info(coin_ledger)')).map((c) => c['name'] as String).toSet();
    if (!coinCols.contains('idempotency_key')) {
      await db.execute('ALTER TABLE coin_ledger ADD COLUMN idempotency_key TEXT');
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_coin_ledger_created_at ON coin_ledger(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_coin_ledger_reason ON coin_ledger(reason)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_coin_ledger_ref_id_unique ON coin_ledger(ref_id) WHERE ref_id IS NOT NULL',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_coin_ledger_idempotency_key_unique ON coin_ledger(idempotency_key) WHERE idempotency_key IS NOT NULL',
    );

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

    // 5. Ensure performance indexes exist
    await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_bucket ON thoughts(bucket)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_status_done ON thoughts(status, done)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_created_at ON thoughts(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_trashed ON thoughts(trashed)');
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

  /// Items likely auto-filed into Raw by the v1.3.1 default (2026-11-23T01:24:31Z).
  /// Used for a one-time, user-confirmed recovery back to Unsorted.
  Future<List<Map<String, dynamic>>> fetchRawDefaultRecoveryCandidates({
    required int sinceCreatedAtMs,
  }) async {
    final db = await instance.database;
    return await db.query(
      'thoughts',
      columns: ['id', 'content', 'title', 'created_at', 'bucket', 'status', 'done', 'trashed'],
      where:
          "LOWER(TRIM(COALESCE(bucket, ''))) = 'raw' AND (trashed IS NULL OR trashed = 0) AND status != 'vaulted_trash' AND created_at >= ?",
      whereArgs: [sinceCreatedAtMs],
      orderBy: 'created_at DESC',
    );
  }

  Future<int> moveRawThoughtsToUnsorted(List<String> ids, {String? deviceId}) async {
    if (ids.isEmpty) return 0;
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    final nowHlc = Hlc.now(node).toString();
    var updated = 0;
    await db.transaction((txn) async {
      for (final id in ids) {
        final count = await txn.rawUpdate('''
UPDATE thoughts SET
  bucket = NULL,
  bucket_id = NULL,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ? AND LOWER(TRIM(COALESCE(bucket, ''))) = 'raw' AND (trashed IS NULL OR trashed = 0)
''', [nowHlc, node, id]);
        updated += count;
      }
    });
    return updated;
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

    if (done) {
      await db.rawUpdate('''
UPDATE thoughts SET
  done = 1,
  status = 'completed',
  done_at = ?,
  last_completed_at = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [
        now,
        now,
        Hlc.now(node).toString(),
        node,
        id,
      ]);
    } else {
      await db.rawUpdate('''
UPDATE thoughts SET
  done = 0,
  status = 'active',
  done_at = NULL,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [
        Hlc.now(node).toString(),
        node,
        id,
      ]);
    }
  }

  Future<void> updateThoughtRecurrence(String id, String? recurrence, {String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    await db.rawUpdate('''
UPDATE thoughts SET
  recurrence = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [recurrence, Hlc.now(node).toString(), node, id]);
  }

  Future<void> updateThoughtReminder(String id, int? reminderAt, {String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    await db.rawUpdate('''
UPDATE thoughts SET
  reminder_at = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [reminderAt, Hlc.now(node).toString(), node, id]);
  }

  Future<void> updateThoughtDueAt(String id, int? dueAt, {String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    await db.rawUpdate('''
UPDATE thoughts SET
  due_at = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [dueAt, Hlc.now(node).toString(), node, id]);
  }

  Future<void> updateThoughtActionPlan(
    String id, {
    String? actionText,
    String? measureText,
    int? deadlineAt,
    bool clearDeadline = false,
    String? triggerText,
    String? intentType,
    double? intentConfidence,
    String? subStepsJson,
    int? nextSubStepIndex,
    int? goalTarget,
    bool clearGoalTarget = false,
    String? goalUnit,
    bool clearGoalUnit = false,
    String? deviceId,
  }) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    final updates = <String, dynamic>{'updated_at': Hlc.now(node).toString(), 'updated_by': node};
    void set(String k, dynamic v) => updates[k] = v;
    if (actionText != null) set('action_text', actionText);
    if (measureText != null) set('measure_text', measureText);
    if (clearDeadline) set('deadline_at', null); else if (deadlineAt != null) set('deadline_at', deadlineAt);
    if (triggerText != null) set('trigger_text', triggerText);
    if (intentType != null) set('intent_type', intentType);
    if (intentConfidence != null) set('intent_confidence', intentConfidence);
    if (subStepsJson != null) set('sub_steps', subStepsJson);
    if (nextSubStepIndex != null) set('next_sub_step_index', nextSubStepIndex);
    if (clearGoalTarget) set('goal_target', null); else if (goalTarget != null) set('goal_target', goalTarget);
    if (clearGoalUnit) set('goal_unit', null); else if (goalUnit != null) set('goal_unit', goalUnit);
    final setClause = updates.keys.map((k) => '$k = ?').join(', ');
    await db.rawUpdate('UPDATE thoughts SET $setClause, revision = revision + 1 WHERE id = ?', [...updates.values, id]);
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
      {String icon = 'folder', String type = 'normal', String? id, String? deviceId}) async {
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
        'type': type,
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
      // Protect Raw, Main, Sides from renaming
      final rows = await txn.query('buckets', where: 'name = ?', whereArgs: [oldName]);
      if (rows.isNotEmpty) {
        final bType = (rows.first['type'] as String?)?.toLowerCase();
        final nLower = oldName.trim().toLowerCase();
        if (bType == 'raw' || bType == 'main' || bType == 'sides' ||
            nLower == 'raw' || nLower == 'main' || nLower == 'sides') {
          AppLogger.info('DatabaseHelper', 'Cannot rename protected system bucket: $oldName');
          return;
        }
      }

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
        // Protect Raw, Main, Sides from deletion
        final bType = (rows.first['type'] as String?)?.toLowerCase();
        final nLower = name.trim().toLowerCase();
        if (bType == 'raw' || bType == 'main' || bType == 'sides' ||
            nLower == 'raw' || nLower == 'main' || nLower == 'sides') {
          AppLogger.info('DatabaseHelper', 'Cannot delete protected system bucket: $name');
          return;
        }

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

  // --- Coin Ledger (v6: balance = SUM(delta), never negative) ---

  Future<int> fetchCoinBalance({DatabaseExecutor? db}) async {
    final executor = db ?? await instance.database;
    final res = await executor.rawQuery(
      'SELECT COALESCE(SUM(delta), 0) AS balance FROM coin_ledger',
    );
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<int> awardCoins({
    required int amount,
    required String reason,
    String? refId,
    String? idempotencyKey,
    int? createdAt,
  }) async {
    if (amount <= 0) return await fetchCoinBalance();
    final db = await instance.database;
    final now = createdAt ?? DateTime.now().millisecondsSinceEpoch;
    final key = idempotencyKey ?? refId;
    try {
      await db.insert('coin_ledger', {
        'id': SyncIdentity.newUuid(),
        'delta': amount,
        'reason': reason,
        'ref_id': refId,
        'idempotency_key': key,
        'created_at': now,
      });
    } on DatabaseException catch (e) {
      if (!e.isUniqueConstraintError()) rethrow;
    }
    return fetchCoinBalance(db: db);
  }

  Future<int> spendCoins({
    required int amount,
    required String reason,
    String? refId,
    String? idempotencyKey,
    int? createdAt,
  }) async {
    if (amount <= 0) return await fetchCoinBalance();
    final db = await instance.database;
    final now = createdAt ?? DateTime.now().millisecondsSinceEpoch;
    final key = idempotencyKey ?? refId;
    return db.transaction<int>((txn) async {
      if (key != null) {
        final existing = await txn.query('coin_ledger', columns: ['id'], where: 'idempotency_key = ?', whereArgs: [key], limit: 1);
        if (existing.isNotEmpty) {
          final bal = await txn.rawQuery('SELECT COALESCE(SUM(delta), 0) AS balance FROM coin_ledger');
          return Sqflite.firstIntValue(bal) ?? 0;
        }
      }
      final res = await txn.rawQuery('SELECT COALESCE(SUM(delta), 0) AS balance FROM coin_ledger');
      final balance = Sqflite.firstIntValue(res) ?? 0;
      if (balance < amount) throw StateError('Insufficient coins: have $balance, need $amount');
      await txn.insert('coin_ledger', {
        'id': SyncIdentity.newUuid(),
        'delta': -amount,
        'reason': reason,
        'ref_id': refId,
        'idempotency_key': key,
        'created_at': now,
      });
      final after = await txn.rawQuery('SELECT COALESCE(SUM(delta), 0) AS balance FROM coin_ledger');
      return Sqflite.firstIntValue(after) ?? 0;
    });
  }

  Future<List<Map<String, dynamic>>> fetchCoinLedger({int limit = 50}) async {
    final db = await instance.database;
    return db.query('coin_ledger', orderBy: 'created_at DESC', limit: limit);
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

  // --- Pin to Board Operations (PART 1) ---

  Future<void> pinThought(String id, {int? position, String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Determine position if not specified
    int pos = position ?? -1;
    if (pos < 0) {
      final existingPinned = await db.query(
        'thoughts',
        columns: ['board_position'],
        where: 'is_pinned = 1 AND trashed = 0 AND done = 0',
      );
      final taken = existingPinned
          .map((r) => r['board_position'] as int? ?? -1)
          .where((p) => p >= 0 && p < 8)
          .toSet();
      for (int i = 0; i < 8; i++) {
        if (!taken.contains(i)) {
          pos = i;
          break;
        }
      }
      if (pos < 0) pos = 0;
    }

    await db.rawUpdate('''
UPDATE thoughts SET
  is_pinned = 1,
  board_position = ?,
  pinned_at = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [pos, now, Hlc.now(node).toString(), node, id]);
  }

  Future<void> unpinThought(String id, {String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;

    await db.rawUpdate('''
UPDATE thoughts SET
  is_pinned = 0,
  board_position = -1,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [Hlc.now(node).toString(), node, id]);
  }

  Future<void> updateBoardPositions(Map<String, int> positions, {String? deviceId}) async {
    final db = await instance.database;
    final node = deviceId ?? currentDeviceId;
    final hlcStr = Hlc.now(node).toString();

    await db.transaction((txn) async {
      for (final entry in positions.entries) {
        await txn.rawUpdate('''
UPDATE thoughts SET
  board_position = ?,
  updated_at = ?,
  updated_by = ?,
  revision = revision + 1
WHERE id = ?
''', [entry.value, hlcStr, node, entry.key]);
      }
    });
  }

  // --- Voice Recordings DB Operations (PART 2) ---

  Future<void> insertVoiceRecording(Map<String, dynamic> recording) async {
    final db = await instance.database;
    await db.insert('voice_recordings', recording, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateVoiceRecording(String id, Map<String, dynamic> updates) async {
    final db = await instance.database;
    await db.update('voice_recordings', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> fetchVoiceRecordings() async {
    final db = await instance.database;
    return await db.query('voice_recordings', orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> fetchAllVoiceRecordings() => fetchVoiceRecordings();

  Future<Map<String, dynamic>?> fetchVoiceRecording(String id) async {
    final db = await instance.database;
    final res = await db.query('voice_recordings', where: 'id = ?', whereArgs: [id]);
    return res.firstOrNull;
  }

  Future<void> deleteVoiceRecording(String id) async {
    final db = await instance.database;
    await db.delete('voice_segments', where: 'recording_id = ?', whereArgs: [id]);
    await db.delete('voice_recordings', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> insertVoiceSegment(Map<String, dynamic> segment) async {
    final db = await instance.database;
    await db.insert('voice_segments', segment, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateVoiceSegment(String id, Map<String, dynamic> updates) async {
    final db = await instance.database;
    await db.update('voice_segments', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> fetchVoiceSegments(String recordingId) async {
    final db = await instance.database;
    return await db.query('voice_segments', where: 'recording_id = ?', whereArgs: [recordingId], orderBy: 'segment_index ASC');
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
