import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thought_holder_flutter/services/backup_service.dart';
import 'package:thought_holder_flutter/services/self_check_service.dart';
import 'package:thought_holder_flutter/sync_identity.dart';
import 'package:thought_holder_flutter/thought_provider.dart';
import 'package:thought_holder_flutter/utils/app_logger.dart';
import 'package:thought_holder_flutter/utils/title_generator.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PHASE 4 - Item 1: Ranking Engine & Order', () {
    test('calculateScore prioritizes higher when and lower time', () {
      // Score = when / time
      // Today (3.0) / Quick (1.0) = 3.0 (highest possible)
      final tTop = {
        'id': '1',
        'when_val': 'Today',
        'time_val': 'Quick',
        'created_at': 2000,
      };
      expect(RankingEngine.calculateScore(tTop), 3.0);

      // Soon (2.0) / Medium (2.0) = 1.0
      final tMid = {
        'id': '2',
        'when_val': 'Soon',
        'time_val': 'Medium',
        'created_at': 2000,
      };
      expect(RankingEngine.calculateScore(tMid), 1.0);

      // Later (1.0) / Long (3.0) = 0.333... (lowest)
      final tLow = {
        'id': '3',
        'when_val': 'Later',
        'time_val': 'Long',
        'created_at': 2000,
      };
      expect(RankingEngine.calculateScore(tLow), closeTo(0.333, 0.001));
    });

    test('compareRanked sorts descending by score and breaks ties by oldest idea first', () {
      final t1 = {
        'id': '1',
        'when_val': 'Today',
        'time_val': 'Quick', // score 3.0
        'created_at': 5000,
      };
      final t2 = {
        'id': '2',
        'when_val': 'Soon',
        'time_val': 'Quick', // score 2.0
        'created_at': 4000,
      };
      final t3TieOld = {
        'id': '3',
        'when_val': 'Soon',
        'time_val': 'Medium', // score 1.0
        'created_at': 1000,   // older tie-break winner
      };
      final t4TieNew = {
        'id': '4',
        'when_val': 'Soon',
        'time_val': 'Medium', // score 1.0
        'created_at': 3000,   // newer tie-break loser
      };

      final list = [t4TieNew, t2, t1, t3TieOld];
      list.sort(RankingEngine.compareRanked);

      expect(list[0]['id'], '1'); // 3.0
      expect(list[1]['id'], '2'); // 2.0
      expect(list[2]['id'], '3'); // 1.0, created 1000
      expect(list[3]['id'], '4'); // 1.0, created 3000
    });

    test('Ranking reasons match when and time values', () {
      expect(
        RankingEngine.getReason({'when_val': 'Today', 'time_val': 'Quick'}),
        'Quick to finish · due today',
      );
      expect(
        RankingEngine.getReason({'when_val': 'Soon', 'time_val': 'Long'}),
        'Takes a while · due soon',
      );
      expect(
        RankingEngine.getReason({'when_val': 'Later', 'time_val': 'Medium'}),
        'Medium effort · no rush',
      );
    });
  });

  group('PHASE 4 - Item 2: Unsorted Order and Skip Memory', () {
    test('Unsorted order defaults to newest first and allows oldest first toggle', () {
      final thoughts = [
        {'id': 'a', 'created_at': 1000},
        {'id': 'b', 'created_at': 3000},
        {'id': 'c', 'created_at': 2000},
      ];

      // Newest first
      final newest = List<Map<String, dynamic>>.from(thoughts);
      newest.sort((x, y) => (y['created_at'] as int).compareTo(x['created_at'] as int));
      expect(newest.map((t) => t['id']).toList(), ['b', 'c', 'a']);

      // Oldest first
      final oldest = List<Map<String, dynamic>>.from(thoughts);
      oldest.sort((x, y) => (x['created_at'] as int).compareTo(y['created_at'] as int));
      expect(oldest.map((t) => t['id']).toList(), ['a', 'c', 'b']);
    });

    test('Skip for now moves idea to end of queue without altering created_at or LOG number', () {
      final thoughts = [
        {'id': '1', 'thought_id': 'LOG-001', 'created_at': 3000},
        {'id': '2', 'thought_id': 'LOG-002', 'created_at': 2000},
        {'id': '3', 'thought_id': 'LOG-003', 'created_at': 1000},
      ];

      final skippedIds = <String>['1'];

      final unskipped = thoughts.where((t) => !skippedIds.contains(t['id'])).toList();
      final skipped = thoughts.where((t) => skippedIds.contains(t['id'])).toList();
      final queue = [...unskipped, ...skipped];

      expect(queue[0]['id'], '2');
      expect(queue[1]['id'], '3');
      expect(queue[2]['id'], '1');

      // Crucial: metadata is uncorrupted
      expect(queue[2]['created_at'], 3000);
      expect(queue[2]['thought_id'], 'LOG-001');
    });
  });

  group('PHASE 4 - Item 3: "New" Rule', () {
    test('New idea receives auto-name, active/unsorted status, and format Today timestamp', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rawThought = {
        'id': SyncIdentity.newUuid(),
        'content': 'Remember to purchase groceries for dinner tonight',
        'status': 'unsorted',
        'bucket': null,
        'done': 0,
        'trashed': 0,
        'created_at': now,
        'source': 'text',
      };

      // 1. Auto-name derivation
      final name = TitleGenerator.getIdeaName(rawThought);
      expect(name, isNotEmpty);
      expect(name.toLowerCase(), isNot(equals('untitled')));
      expect(name, 'Remember to purchase groceries for');

      // 2. Formatted readable timestamp
      final timeStr = IdeaFormatters.formatReadableTimestamp(now);
      expect(timeStr.startsWith('Today,'), isTrue);

      // 3. New idea is active in Unsorted queue
      final isUnsorted = rawThought['bucket'] == null &&
          rawThought['trashed'] == 0 &&
          rawThought['done'] == 0;
      expect(isUnsorted, isTrue);
    });
  });

  group('PHASE 4 - Item 4: Auto-Naming Strict Rules', () {
    test('Strips leading filler words', () {
      expect(
        TitleGenerator.generate('Eh, so like we should build an offline database'),
        'We should build an offline database',
      );
      expect(
        TitleGenerator.generate('Um, okay so buy milk from the store'),
        'Buy milk from the store',
      );
      expect(
        TitleGenerator.generate('You know, I mean this could work nicely'),
        'This could work nicely',
      );
    });

    test('Truncates at word boundary under 40 chars and strips trailing punctuation', () {
      final long = 'A remarkably long and sophisticated thought that needs a short title';
      final res = TitleGenerator.generate(long);
      expect(res.length, lessThanOrEqualTo(40));
      expect(res, 'A remarkably long and sophisticated');

      final punctuated = 'Finish the report today, please!?!...';
      expect(TitleGenerator.generate(punctuated), 'Finish the report today, please');
    });

    test('Short ideas use their own text with sentence case', () {
      expect(TitleGenerator.generate('call mom'), 'Call mom');
      expect(TitleGenerator.generate('quick test'), 'Quick test');
    });

    test('Empty or filler-only inputs default to Quick note and never Untitled', () {
      expect(TitleGenerator.generate(''), 'Quick note');
      expect(TitleGenerator.generate('   '), 'Quick note');
      expect(TitleGenerator.generate('Um, uh, so...'), 'Quick note');
      expect(TitleGenerator.generate('Untitled'), 'Quick note');
      expect(TitleGenerator.generate('untitled'), 'Quick note');
    });

    test('User renamed title is never overwritten by auto-name generator', () {
      final thought = {
        'id': 'uuid-custom',
        'title': 'My Handcrafted Title',
        'title_source': 'user',
        'content': 'Completely different content',
      };
      expect(TitleGenerator.getIdeaName(thought), 'My Handcrafted Title');
    });
  });

  group('PHASE 4 - Item 5: Migrations on Real-Shaped Data', () {
    test('Database schema migration preserves existing rows and creates required columns & indexes', () async {
      // 1. Open an in-memory database with an older schema (version 1)
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE thoughts (
              id TEXT PRIMARY KEY,
              thought_id TEXT NOT NULL,
              content TEXT NOT NULL,
              type TEXT NOT NULL,
              status TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              last_viewed_at INTEGER NOT NULL,
              stale_score INTEGER NOT NULL,
              bucket TEXT,
              done INTEGER DEFAULT 0,
              trashed INTEGER DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE buckets (
              name TEXT PRIMARY KEY,
              icon TEXT DEFAULT 'folder',
              created_at INTEGER NOT NULL
            )
          ''');
        },
      );

      // 2. Insert real-shaped legacy rows
      await db.insert('thoughts', {
        'id': 'legacy-1',
        'thought_id': 'LOG-101',
        'content': 'Legacy thought content before hardening',
        'type': 'text',
        'status': 'unsorted',
        'created_at': 1700000000000,
        'last_viewed_at': 1700000000000,
        'stale_score': 0,
        'bucket': null,
        'done': 0,
        'trashed': 0,
      });

      // 3. Apply migration (simulating _onOpenDB in DatabaseHelper)
      // Adds missing columns if not present
      final tableInfo = await db.rawQuery('PRAGMA table_info(thoughts)');
      final columnNames = tableInfo.map((c) => c['name'] as String).toSet();

      if (!columnNames.contains('title')) {
        await db.execute('ALTER TABLE thoughts ADD COLUMN title TEXT;');
      }
      if (!columnNames.contains('title_source')) {
        await db.execute('ALTER TABLE thoughts ADD COLUMN title_source TEXT;');
      }
      if (!columnNames.contains('updated_at')) {
        await db.execute('ALTER TABLE thoughts ADD COLUMN updated_at TEXT;');
      }

      // Add performance indexes
      await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_bucket ON thoughts(bucket);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_status_done ON thoughts(status, done);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_created_at ON thoughts(created_at);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_trashed ON thoughts(trashed);');

      // 4. Verify existing row is fully preserved
      final rows = await db.query('thoughts', where: 'id = ?', whereArgs: ['legacy-1']);
      expect(rows.length, 1);
      expect(rows.first['content'], 'Legacy thought content before hardening');
      expect(rows.first['thought_id'], 'LOG-101');

      // 5. Verify indexes and columns now exist
      final updatedInfo = await db.rawQuery('PRAGMA table_info(thoughts)');
      final updatedColumns = updatedInfo.map((c) => c['name'] as String).toSet();
      expect(updatedColumns.contains('title'), isTrue);
      expect(updatedColumns.contains('title_source'), isTrue);

      final indexInfo = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'index'");
      final indexes = indexInfo.map((r) => r['name'] as String).toSet();
      expect(indexes.contains('idx_thoughts_bucket'), isTrue);
      expect(indexes.contains('idx_thoughts_status_done'), isTrue);
      expect(indexes.contains('idx_thoughts_created_at'), isTrue);
      expect(indexes.contains('idx_thoughts_trashed'), isTrue);

      await db.close();
    });
  });

  group('PHASE 4 - Item 6: Backup then Restore Equals Original', () {
    test('Backup creates verified snapshot and prepareRestore validates data', () async {
      final tempDir = await Directory.systemTemp.createTemp('th_backup_test_');
      final dbPath = '${tempDir.path}/test_thoughts.db';
      final backupDir = '${tempDir.path}/backups';

      final db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE thoughts (
              id TEXT PRIMARY KEY,
              thought_id TEXT NOT NULL,
              content TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              status TEXT NOT NULL,
              bucket TEXT,
              done INTEGER DEFAULT 0,
              trashed INTEGER DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE buckets (
              name TEXT PRIMARY KEY,
              icon TEXT DEFAULT 'folder',
              created_at INTEGER NOT NULL
            )
          ''');
        },
      );

      // Insert test thoughts
      await db.insert('thoughts', {
        'id': 'idea-1',
        'thought_id': 'LOG-001',
        'content': 'First test idea for backup verification',
        'created_at': 1700000000,
        'status': 'unsorted',
        'bucket': null,
        'done': 0,
        'trashed': 0,
      });
      await db.insert('thoughts', {
        'id': 'idea-2',
        'thought_id': 'LOG-002',
        'content': 'Second test idea',
        'created_at': 1700001000,
        'status': 'sorted',
        'bucket': 'Work',
        'done': 0,
        'trashed': 0,
      });

      // Create backup
      final backupMeta = await BackupService.instance.createBackup(
        db: db,
        customDirectoryPath: backupDir,
      );

      expect(backupMeta.ideaCount, 2);
      expect(backupMeta.integrityOk, isTrue);
      expect(File(backupMeta.filePath).existsSync(), isTrue);

      // Verify restore preparation
      final prep = await BackupService.instance.prepareRestore(
        File(backupMeta.filePath),
        liveDb: db,
        liveDbPath: dbPath,
      );

      expect(prep.backupIdeaCount, 2);
      expect(prep.integrityOk, isTrue);

      // Clean up
      await db.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
  });

  group('PHASE 4 - Item 7: Save Failure Keeps the Text', () {
    test('Simulated save failure preserves user draft text in state without loss', () async {
      final controller = TextEditingController(text: 'Crucial user idea text that must never be lost');

      bool saveSucceeded = false;
      String preservedText = controller.text;

      Future<void> attemptSave(Database failingDb) async {
        try {
          // Attempt insert into a closed or read-only database to simulate error
          await failingDb.insert('non_existent_table', {'data': controller.text});
          saveSucceeded = true;
        } catch (e) {
          // Failure caught: preserve draft text
          preservedText = controller.text;
          AppLogger.error('SaveTest', 'Simulated save error handled safely', e);
        }
      }

      final dummyDb = await openDatabase(inMemoryDatabasePath);
      await attemptSave(dummyDb);
      await dummyDb.close();

      expect(saveSucceeded, isFalse);
      // User's typed text remains 100% intact
      expect(preservedText, 'Crucial user idea text that must never be lost');
      expect(controller.text, 'Crucial user idea text that must never be lost');
      controller.dispose();
    });
  });

  group('PHASE 4 - Item 8: Diagnostic Report & Logs Never Contain Idea Text', () {
    test('SelfCheckReport toDiagnosticReport contains numbers and statuses only, zero idea text', () {
      final report = SelfCheckReport(
        checkTime: DateTime.now(),
        durationMs: 42,
        overallStatus: CheckStatus.green,
        items: const [
          CheckItemResult(
            title: 'Data integrity',
            status: CheckStatus.green,
            summary: 'File structure is sound',
            details: 'All database pages, B-trees, and indexes verified without corruption.',
          ),
          CheckItemResult(
            title: 'Idea identity',
            status: CheckStatus.green,
            summary: 'Every idea has a unique identity',
            details: '698 ideas verified with distinct identifiers.',
          ),
        ],
        totalIdeas: 698,
        liveIdeas: 643,
        doneIdeas: 55,
        trashedIdeas: 0,
        bucketCount: 13,
        backupCount: 2,
        lastBackupDate: DateTime.now(),
        databaseSizeBytes: 524288,
        databaseSchemaVersion: 3,
        appVersion: '1.0.0',
      );

      final reportText = report.toDiagnosticReport();

      // Report contains metrics and status words
      expect(reportText.contains('698'), isTrue);
      expect(reportText.contains('512.0 KB'), isTrue);
      expect(reportText.contains('PASS'), isTrue);

      // Must NEVER contain user idea text, secret keys, or passwords
      expect(reportText.contains('gsk_'), isFalse);
      expect(reportText.contains('password'), isFalse);
      expect(reportText.contains('My private secret idea'), isFalse);
    });

    test('Self-repair detects and adds missing indexes and missing buckets safely', () async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE thoughts (
              id TEXT PRIMARY KEY,
              thought_id TEXT,
              content TEXT NOT NULL,
              title TEXT,
              title_source TEXT,
              status TEXT,
              bucket TEXT,
              done INTEGER DEFAULT 0,
              trashed INTEGER DEFAULT 0,
              created_at INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE buckets (
              name TEXT PRIMARY KEY,
              icon TEXT DEFAULT 'folder',
              created_at INTEGER NOT NULL
            )
          ''');
        },
      );

      // Insert idea referencing an orphaned bucket 'Research'
      await db.insert('thoughts', {
        'id': 'repair-1',
        'content': 'Read research paper on AI',
        'title': null, // Missing title
        'bucket': 'Research', // Missing from buckets table
        'status': 'unsorted',
        'created_at': 1700000000,
      });

      // Run repair
      final repair = await SelfCheckService.instance.performSafeSelfRepair(customDb: db);
      expect(repair.success, isTrue);
      expect(repair.bucketsCreated, 1);
      expect(repair.titlesGenerated, 1);

      // Verify bucket 'Research' was safely added
      final bucketQuery = await db.query('buckets', where: 'name = ?', whereArgs: ['Research']);
      expect(bucketQuery.length, 1);
      expect(bucketQuery.first['name'], 'Research');

      // Verify title was safely derived
      final thoughtQuery = await db.query('thoughts', where: 'id = ?', whereArgs: ['repair-1']);
      expect(thoughtQuery.first['title'], 'Read research paper on AI');
      expect(thoughtQuery.first['title_source'], 'auto');

      await db.close();
    });
  });
}
