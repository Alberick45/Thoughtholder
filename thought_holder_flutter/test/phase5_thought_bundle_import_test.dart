import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thought_holder_flutter/services/thought_bundle_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late File dbFile;
  late Database db;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('bundle_import_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );

    Hive.init(tempDir.path);
    await Hive.openBox('app_settings');
  });

  tearDownAll(() async {
    try {
      await Hive.close();
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    final uniqueName = 'import_test_${DateTime.now().microsecondsSinceEpoch}.db';
    dbFile = File('${tempDir.path}/$uniqueName');
    db = await databaseFactory.openDatabase(dbFile.path);

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
        trashed INTEGER DEFAULT 0,
        done_at INTEGER,
        trashed_at INTEGER,
        edited_at INTEGER,
        bucket_id TEXT,
        updated_at TEXT,
        updated_by TEXT,
        revision INTEGER DEFAULT 1,
        skipped_at INTEGER,
        skip_count INTEGER DEFAULT 0,
        title TEXT,
        title_source TEXT DEFAULT 'auto'
      )
    ''');

    await db.execute('''
      CREATE TABLE buckets (
        name TEXT PRIMARY KEY,
        id TEXT,
        icon TEXT,
        created_at INTEGER,
        revision INTEGER DEFAULT 1
      )
    ''');
  });

  tearDown(() async {
    await db.close();
    try {
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
    } catch (_) {}
  });

  group('Phase 5 Part 4: Thought Bundle Import Requirements', () {
    test('1. Valid import: imports ideas and buckets accurately and matches buckets by name', () async {
      // Seed initial data
      await db.insert('buckets', {
        'name': 'Work',
        'id': 'b-work-1',
        'icon': 'work',
        'created_at': 1700000000,
        'revision': 1,
      });

      await db.insert('thoughts', {
        'id': 'idea-1',
        'thought_id': 'idea-1',
        'content': 'Existing thought 1',
        'type': 'text',
        'status': 'active',
        'created_at': 1700000000,
        'last_viewed_at': 1700000000,
        'stale_score': 0,
        'bucket': 'Work',
        'bucket_id': 'b-work-1',
        'title': 'Thought One',
        'title_source': 'manual',
        'updated_at': '2026-01-01T10:00:00Z',
      });

      // Construct incoming bundle file
      final bundleData = {
        'ideas': [
          {
            'uuid': 'idea-2',
            'text': 'Brand new incoming idea',
            'title': 'New Idea',
            'title_source': 'auto',
            'bucket_uuid': 'b-personal-1',
            'bucket_name': 'Personal',
            'when': 'Soon',
            'time': 'Quick',
            'status': 'active',
            'created_at': 1700001000,
            'updated_at': '2026-02-01T12:00:00Z',
            'skipped_at': null,
            'skip_count': 0,
          },
          {
            'uuid': 'idea-3',
            'text': 'Incoming idea for existing bucket Work',
            'title': 'Work Task',
            'title_source': 'manual',
            'bucket_uuid': 'b-work-remote',
            'bucket_name': 'Work',
            'when': 'Later',
            'time': 'Deep',
            'status': 'done',
            'created_at': 1700002000,
            'updated_at': '2026-02-02T12:00:00Z',
            'skipped_at': null,
            'skip_count': 0,
          }
        ],
        'buckets': [
          {
            'uuid': 'b-personal-1',
            'name': 'Personal',
            'icon': 'home',
            'created_at': 1700001000,
          },
          {
            'uuid': 'b-work-remote',
            'name': 'Work', // Existing bucket name
            'icon': 'work',
            'created_at': 1700000000,
          }
        ]
      };

      final bundleFile = File('${tempDir.path}/valid_test.thoughtbundle');

      // Create valid bundle string via service
      await bundleFile.writeAsString(jsonEncode({
        'header': {
          'format_version': 1,
          'app_version': '1.0.0',
          'exported_at': DateTime.now().toUtc().toIso8601String(),
          'counts': {'ideas': 2, 'buckets': 2},
          'sha256': await _computeChecksum(bundleData),
          'is_encrypted': false,
          'salt': null,
        },
        'data': bundleData,
      }));

      // 1. Preview
      final analysis = await ThoughtBundleService.instance.previewImport(
        file: bundleFile,
        db: db,
      );

      expect(analysis.newIdeasCount, 2);
      expect(analysis.newerEditsCount, 0);
      expect(analysis.upToDateCount, 0);
      expect(analysis.conflictsCount, 0);
      expect(analysis.bucketsToAddCount, 1); // 'Personal'
      expect(analysis.bucketsMatchedByNameCount, 1); // 'Work'

      // Database should NOT have changed yet
      final thoughtsBefore = await db.query('thoughts');
      expect(thoughtsBefore.length, 1);

      // 2. Apply
      final result = await ThoughtBundleService.instance.applyImport(
        analysis: analysis,
        db: db,
        customBackupDir: tempDir.path,
      );

      expect(result.insertedIdeasCount, 2);
      expect(result.addedBucketsCount, 1);

      // Verify in database
      final thoughtsAfter = await db.query('thoughts');
      expect(thoughtsAfter.length, 3);

      final bucketsAfter = await db.query('buckets');
      expect(bucketsAfter.length, 2);
      expect(bucketsAfter.any((b) => b['name'] == 'Personal'), isTrue);
      expect(bucketsAfter.any((b) => b['name'] == 'Work'), isTrue);
    });

    test('2. Bad checksum: tampered payload rejected with plain message and 0 writes', () async {
      await db.insert('thoughts', {
        'id': 'initial-1',
        'thought_id': 'initial-1',
        'content': 'Original text',
        'type': 'text',
        'status': 'active',
        'created_at': 1700000000,
        'last_viewed_at': 1700000000,
        'stale_score': 0,
        'title': 'Original',
      });

      final tamperedData = {
        'ideas': [
          {
            'uuid': 'tampered-idea',
            'text': 'Malicious or corrupted text',
            'title': 'Corrupted',
            'title_source': 'auto',
            'bucket_uuid': '',
            'bucket_name': '',
            'when': 'Soon',
            'time': 'Medium',
            'status': 'active',
            'created_at': 1700000000,
            'updated_at': null,
            'skipped_at': null,
            'skip_count': 0,
          }
        ],
        'buckets': []
      };

      // Set incorrect checksum intentionally
      final tamperedFile = File('${tempDir.path}/tampered.thoughtbundle');
      await tamperedFile.writeAsString(jsonEncode({
        'header': {
          'format_version': 1,
          'app_version': '1.0.0',
          'exported_at': DateTime.now().toUtc().toIso8601String(),
          'counts': {'ideas': 1, 'buckets': 0},
          'sha256': '0000000000000000000000000000000000000000000000000000000000000000',
          'is_encrypted': false,
        },
        'data': tamperedData,
      }));

      await expectLater(
        () => ThoughtBundleService.instance.previewImport(file: tamperedFile, db: db),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Checksum mismatch: bundle data is corrupted or tampered.'),
        )),
      );

      // Verify 0 writes were made to the database
      final rows = await db.query('thoughts');
      expect(rows.length, 1);
      expect(rows.first['id'], 'initial-1');
    });

    test('3. Malformed bundle and oversized bundle (> 50 MB) rejected, writing nothing', () async {
      // 3A. Missing required fields in idea schema
      final invalidSchemaData = {
        'ideas': [
          {
            // Missing 'uuid'
            'text': 'Missing uuid field',
            'status': 'active',
          }
        ],
        'buckets': []
      };
      final schemaChecksum = await _computeChecksum(invalidSchemaData);
      final invalidSchemaFile = File('${tempDir.path}/invalid_schema.thoughtbundle');
      await invalidSchemaFile.writeAsString(jsonEncode({
        'header': {
          'format_version': 1,
          'app_version': '1.0.0',
          'exported_at': DateTime.now().toUtc().toIso8601String(),
          'counts': {'ideas': 1, 'buckets': 0},
          'sha256': schemaChecksum,
          'is_encrypted': false,
        },
        'data': invalidSchemaData,
      }));

      await expectLater(
        () => ThoughtBundleService.instance.previewImport(file: invalidSchemaFile, db: db),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Malformed bundle: idea missing or invalid "uuid".'),
        )),
      );

      // 3B. Oversized file check (> 50 MB cap)
      final oversizedFile = File('${tempDir.path}/oversized_${DateTime.now().microsecondsSinceEpoch}.thoughtbundle');
      final sink = oversizedFile.openWrite();
      final oneMb = Uint8List(1024 * 1024);
      for (int i = 0; i < 51; i++) {
        sink.add(oneMb);
      }
      await sink.flush();
      await sink.close();
      await Future.delayed(const Duration(milliseconds: 150));

      await expectLater(
        () => ThoughtBundleService.instance.previewImport(file: oversizedFile, db: db),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('File too large (exceeds 50 MB limit).'),
        )),
      );
      try {
        await oversizedFile.delete();
      } catch (_) {}
    });

    test('4. Newer-wins rule: incoming idea with newer updated_at updates, older does not', () async {
      await db.insert('thoughts', {
        'id': 'idea-newer-test',
        'thought_id': 'idea-newer-test',
        'content': 'Original local text',
        'type': 'text',
        'status': 'active',
        'created_at': 1700000000,
        'last_viewed_at': 1700000000,
        'stale_score': 0,
        'title': 'Original Title',
        'title_source': 'manual',
        'updated_at': '2026-03-01T10:00:00Z',
      });

      // Bundle with newer timestamp (2026-03-05)
      final newerData = {
        'ideas': [
          {
            'uuid': 'idea-newer-test',
            'text': 'Updated text from remote device',
            'title': 'Updated Title',
            'title_source': 'manual',
            'bucket_uuid': '',
            'bucket_name': '',
            'when': 'Soon',
            'time': 'Medium',
            'status': 'active',
            'created_at': 1700000000,
            'updated_at': '2026-03-05T15:00:00Z',
            'skipped_at': null,
            'skip_count': 0,
          }
        ],
        'buckets': []
      };

      final newerChecksum = await _computeChecksum(newerData);
      final newerFile = File('${tempDir.path}/newer_wins.thoughtbundle');
      await newerFile.writeAsString(jsonEncode({
        'header': {
          'format_version': 1,
          'app_version': '1.0.0',
          'exported_at': DateTime.now().toUtc().toIso8601String(),
          'counts': {'ideas': 1, 'buckets': 0},
          'sha256': newerChecksum,
          'is_encrypted': false,
        },
        'data': newerData,
      }));

      final analysis = await ThoughtBundleService.instance.previewImport(file: newerFile, db: db);
      expect(analysis.newerEditsCount, 1);
      expect(analysis.newIdeasCount, 0);

      await ThoughtBundleService.instance.applyImport(analysis: analysis, db: db, customBackupDir: tempDir.path);

      final row = (await db.query('thoughts', where: 'id = ?', whereArgs: ['idea-newer-test'])).first;
      expect(row['content'], 'Updated text from remote device');
      expect(row['title'], 'Updated Title');
      expect(row['updated_at'], '2026-03-05T15:00:00Z');

      // Now test older timestamp: should NOT overwrite
      final olderData = {
        'ideas': [
          {
            'uuid': 'idea-newer-test',
            'text': 'Stale old text',
            'title': 'Stale Title',
            'title_source': 'manual',
            'bucket_uuid': '',
            'bucket_name': '',
            'when': 'Soon',
            'time': 'Medium',
            'status': 'active',
            'created_at': 1700000000,
            'updated_at': '2026-02-01T10:00:00Z', // older than current 2026-03-05
            'skipped_at': null,
            'skip_count': 0,
          }
        ],
        'buckets': []
      };
      final olderChecksum = await _computeChecksum(olderData);
      final olderFile = File('${tempDir.path}/older.thoughtbundle');
      await olderFile.writeAsString(jsonEncode({
        'header': {
          'format_version': 1,
          'app_version': '1.0.0',
          'exported_at': DateTime.now().toUtc().toIso8601String(),
          'counts': {'ideas': 1, 'buckets': 0},
          'sha256': olderChecksum,
          'is_encrypted': false,
        },
        'data': olderData,
      }));

      final olderAnalysis = await ThoughtBundleService.instance.previewImport(file: olderFile, db: db);
      expect(olderAnalysis.newerEditsCount, 0);
      expect(olderAnalysis.upToDateCount, 1);

      await ThoughtBundleService.instance.applyImport(analysis: olderAnalysis, db: db, customBackupDir: tempDir.path);

      final rowAfterOlder = (await db.query('thoughts', where: 'id = ?', whereArgs: ['idea-newer-test'])).first;
      expect(rowAfterOlder['content'], 'Updated text from remote device'); // Still the newer version
    });

    test('5. Conflict copy: equal timestamps with different text creates "Conflict copy: <title>" in Unsorted', () async {
      await db.insert('thoughts', {
        'id': 'idea-conflict-test',
        'thought_id': 'idea-conflict-test',
        'content': 'Local version of thought',
        'type': 'text',
        'status': 'active',
        'created_at': 1700000000,
        'last_viewed_at': 1700000000,
        'stale_score': 0,
        'title': 'Project Roadmap',
        'title_source': 'manual',
        'updated_at': '2026-04-01T12:00:00Z',
      });

      // Incoming thought has same uuid, same updated_at, but different text
      final conflictData = {
        'ideas': [
          {
            'uuid': 'idea-conflict-test',
            'text': 'Conflicting remote version of roadmap',
            'title': 'Project Roadmap',
            'title_source': 'manual',
            'bucket_uuid': '',
            'bucket_name': '',
            'when': 'Soon',
            'time': 'Medium',
            'status': 'active',
            'created_at': 1700000000,
            'updated_at': '2026-04-01T12:00:00Z', // EXACT same moment
            'skipped_at': null,
            'skip_count': 0,
          }
        ],
        'buckets': []
      };

      final conflictChecksum = await _computeChecksum(conflictData);
      final conflictFile = File('${tempDir.path}/conflict.thoughtbundle');
      await conflictFile.writeAsString(jsonEncode({
        'header': {
          'format_version': 1,
          'app_version': '1.0.0',
          'exported_at': DateTime.now().toUtc().toIso8601String(),
          'counts': {'ideas': 1, 'buckets': 0},
          'sha256': conflictChecksum,
          'is_encrypted': false,
        },
        'data': conflictData,
      }));

      final analysis = await ThoughtBundleService.instance.previewImport(file: conflictFile, db: db);
      expect(analysis.conflictsCount, 1);

      final result = await ThoughtBundleService.instance.applyImport(
        analysis: analysis,
        db: db,
        customBackupDir: tempDir.path,
      );
      expect(result.conflictCopiesCount, 1);

      // Verify existing original thought is unchanged
      final original = (await db.query('thoughts', where: 'id = ?', whereArgs: ['idea-conflict-test'])).first;
      expect(original['content'], 'Local version of thought');
      expect(original['title'], 'Project Roadmap');

      // Verify conflict copy was created in Unsorted (bucket is null)
      final allThoughts = await db.query('thoughts');
      expect(allThoughts.length, 2);

      final conflictCopy = allThoughts.firstWhere((t) => t['id'] != 'idea-conflict-test');
      expect(conflictCopy['title'], 'Conflict copy: Project Roadmap');
      expect(conflictCopy['content'], 'Conflicting remote version of roadmap');
      expect(conflictCopy['bucket'], isNull); // In Unsorted
    });

    test('6. Rollback on error: transaction rolls back completely if an error occurs midway', () async {
      await db.insert('thoughts', {
        'id': 'original-stay',
        'thought_id': 'original-stay',
        'content': 'Must remain untouched if transaction fails',
        'type': 'text',
        'status': 'active',
        'created_at': 1700000000,
        'last_viewed_at': 1700000000,
        'stale_score': 0,
        'title': 'Original Stay',
      });

      // Construct an analysis with 1 valid idea and 1 idea that triggers an SQL error
      final faultyBundle = UnpackedBundle(
        header: {'format_version': 1},
        ideas: [
          {
            'uuid': 'idea-will-succeed-first',
            'text': 'First insert',
            'status': 'active',
            'created_at': 1700000000,
          },
          {
            // Null id or conflicting constraint that will fail in transaction
            'uuid': 'original-stay', // Primary key collision on thoughts table
            'text': 'Should fail',
            'status': 'active',
            'created_at': 1700000000,
          }
        ],
        buckets: [],
        checksum: 'dummy',
      );

      final faultyAnalysis = ImportAnalysis(
        bundle: faultyBundle,
        newIdeas: faultyBundle.ideas, // forcing both into newIdeas will cause PK violation on 2nd
        newerEdits: [],
        upToDateIdeas: [],
        conflicts: [],
        statusChanges: [],
        bucketsToAdd: [],
        bucketsMatchedByName: [],
      );

      // Apply should throw and roll back
      await expectLater(
        () => ThoughtBundleService.instance.applyImport(
          analysis: faultyAnalysis,
          db: db,
          customBackupDir: tempDir.path,
        ),
        throwsA(isA<Exception>()),
      );

      // Confirm database has only the original record and 'idea-will-succeed-first' was rolled back
      final rows = await db.query('thoughts');
      expect(rows.length, 1);
      expect(rows.first['id'], 'original-stay');
      expect(rows.first['content'], 'Must remain untouched if transaction fails');
    });

    test('7. Undo restores previous state: restores exact pre-import database and counts', () async {
      // Start with 2 thoughts
      await db.insert('thoughts', {
        'id': 'base-1',
        'thought_id': 'base-1',
        'content': 'Base thought 1',
        'type': 'text',
        'status': 'active',
        'created_at': 1700000000,
        'last_viewed_at': 1700000000,
        'stale_score': 0,
        'title': 'Base One',
      });
      await db.insert('thoughts', {
        'id': 'base-2',
        'thought_id': 'base-2',
        'content': 'Base thought 2',
        'type': 'text',
        'status': 'active',
        'created_at': 1700000000,
        'last_viewed_at': 1700000000,
        'stale_score': 0,
        'title': 'Base Two',
      });

      final initialCounts = await db.query('thoughts');
      expect(initialCounts.length, 2);

      // Perform an import that adds 2 new thoughts
      final importData = {
        'ideas': [
          {
            'uuid': 'imported-1',
            'text': 'Imported thought 1',
            'title': 'Imported One',
            'title_source': 'auto',
            'bucket_uuid': '',
            'bucket_name': '',
            'when': 'Soon',
            'time': 'Medium',
            'status': 'active',
            'created_at': 1700000000,
            'updated_at': null,
            'skipped_at': null,
            'skip_count': 0,
          },
          {
            'uuid': 'imported-2',
            'text': 'Imported thought 2',
            'title': 'Imported Two',
            'title_source': 'auto',
            'bucket_uuid': '',
            'bucket_name': '',
            'when': 'Soon',
            'time': 'Medium',
            'status': 'active',
            'created_at': 1700000000,
            'updated_at': null,
            'skipped_at': null,
            'skip_count': 0,
          }
        ],
        'buckets': []
      };

      final chk = await _computeChecksum(importData);
      final importFile = File('${tempDir.path}/undo_test.thoughtbundle');
      await importFile.writeAsString(jsonEncode({
        'header': {
          'format_version': 1,
          'app_version': '1.0.0',
          'exported_at': DateTime.now().toUtc().toIso8601String(),
          'counts': {'ideas': 2, 'buckets': 0},
          'sha256': chk,
          'is_encrypted': false,
        },
        'data': importData,
      }));

      final backupSubDir = Directory('${tempDir.path}/test7_backups')..createSync(recursive: true);
      final analysis = await ThoughtBundleService.instance.previewImport(file: importFile, db: db);
      await ThoughtBundleService.instance.applyImport(
        analysis: analysis,
        db: db,
        customBackupDir: backupSubDir.path,
      );

      // Database now has 4 thoughts
      final afterImport = await db.query('thoughts');
      expect(afterImport.length, 4);

      // Undo last import
      final undoSuccess = await ThoughtBundleService.instance.undoLastImport(
        db: db,
        liveDbPath: dbFile.path,
        customBackupDir: backupSubDir.path,
      );
      expect(undoSuccess, isTrue);

      // Re-open DB to verify restored disk state
      final restoredDb = await databaseFactory.openDatabase(dbFile.path);
      final restoredRows = await restoredDb.query('thoughts');
      expect(restoredRows.length, 2);
      expect(restoredRows.any((r) => r['id'] == 'base-1'), isTrue);
      expect(restoredRows.any((r) => r['id'] == 'base-2'), isTrue);
      expect(restoredRows.any((r) => r['id'] == 'imported-1'), isFalse);
      await restoredDb.close();
    });

    test('8. Full round-trip: export from real copy, import into fresh empty database, verify exact 701 ideas and 15 buckets', () async {
      final copyDbPath = '${tempDir.path}/real_copy.db';
      await File('../backups/backup_phase5_item2_part4.db').copy(copyDbPath);
      final sourceDb = await databaseFactory.openDatabase(copyDbPath);

      // Verify source counts
      final sourceIdeas = Sqflite.firstIntValue(await sourceDb.rawQuery('SELECT COUNT(*) FROM thoughts')) ?? 0;
      final sourceBuckets = Sqflite.firstIntValue(await sourceDb.rawQuery('SELECT COUNT(*) FROM buckets')) ?? 0;
      expect(sourceIdeas, 701);
      expect(sourceBuckets, 15);

      // Export bundle to file
      final exportResult = await ThoughtBundleService.instance.exportToFile(
        db: sourceDb,
        customDestinationDir: tempDir.path,
        customFileName: 'roundtrip_real.thoughtbundle',
      );
      expect(exportResult.ideasCount, 701);
      expect(exportResult.bucketsCount, 15);
      await sourceDb.close();

      // Create target fresh empty database
      final targetDbPath = '${tempDir.path}/target_empty.db';
      final targetDb = await databaseFactory.openDatabase(targetDbPath);
      await targetDb.execute('''
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
          trashed INTEGER DEFAULT 0,
          done_at INTEGER,
          trashed_at INTEGER,
          edited_at INTEGER,
          bucket_id TEXT,
          updated_at TEXT,
          updated_by TEXT,
          revision INTEGER DEFAULT 1,
          skipped_at INTEGER,
          skip_count INTEGER DEFAULT 0,
          title TEXT,
          title_source TEXT DEFAULT 'auto'
        )
      ''');
      await targetDb.execute('''
        CREATE TABLE buckets (
          name TEXT PRIMARY KEY,
          id TEXT,
          icon TEXT,
          created_at INTEGER,
          revision INTEGER DEFAULT 1
        )
      ''');

      final targetBefore = Sqflite.firstIntValue(await targetDb.rawQuery('SELECT COUNT(*) FROM thoughts')) ?? 0;
      expect(targetBefore, 0);

      // Preview import
      final analysis = await ThoughtBundleService.instance.previewImport(
        file: exportResult.file,
        db: targetDb,
      );
      expect(analysis.newIdeasCount, 701);
      expect(analysis.bucketsToAddCount, 15);

      // Apply import
      final applyResult = await ThoughtBundleService.instance.applyImport(
        analysis: analysis,
        db: targetDb,
        customBackupDir: tempDir.path,
      );
      expect(applyResult.insertedIdeasCount, 701);
      expect(applyResult.addedBucketsCount, 15);

      // Verify in target database
      final targetIdeas = Sqflite.firstIntValue(await targetDb.rawQuery('SELECT COUNT(*) FROM thoughts')) ?? 0;
      final targetBuckets = Sqflite.firstIntValue(await targetDb.rawQuery('SELECT COUNT(*) FROM buckets')) ?? 0;
      expect(targetIdeas, 701);
      expect(targetBuckets, 15);

      await targetDb.close();
    });

    test('9. Phone export compatibility: ideas with title_source "user" validate and import cleanly', () async {
      final phoneExportData = {
        'ideas': [
          {
            'uuid': 'phone-idea-1',
            'text': 'Grocery list idea',
            'title': 'My Groceries',
            'title_source': 'user', // Set when user manually edits title on phone
            'bucket_uuid': null,
            'bucket_name': null,
            'when': 'Soon',
            'time': 'Quick',
            'status': 'active',
            'created_at': 1705000000,
            'updated_at': '2026-03-01T10:00:00Z',
            'skipped_at': null,
            'skip_count': 0,
          },
          {
            'uuid': 'phone-idea-2',
            'text': 'Auto titled note from speech',
            'title': 'Note From Speech',
            'title_source': 'auto',
            'bucket_uuid': null,
            'bucket_name': null,
            'when': 'Later',
            'time': 'Medium',
            'status': 'done',
            'created_at': 1705001000,
            'updated_at': '2026-03-01T11:00:00Z',
            'skipped_at': null,
            'skip_count': 0,
          }
        ],
        'buckets': []
      };

      final checksum = await _computeChecksum(phoneExportData);
      final phoneFile = File('${tempDir.path}/phone_bundle.thoughtbundle');
      await phoneFile.writeAsString(jsonEncode({
        'header': {
          'format_version': 1,
          'app_version': '1.0.0',
          'exported_at': DateTime.now().toUtc().toIso8601String(),
          'counts': {'ideas': 2, 'buckets': 0},
          'sha256': checksum,
          'is_encrypted': false,
        },
        'data': phoneExportData,
      }));

      // Preview should succeed without FormatException
      final analysis = await ThoughtBundleService.instance.previewImport(file: phoneFile, db: db);
      expect(analysis.newIdeasCount, 2);

      // Apply should insert cleanly
      final result = await ThoughtBundleService.instance.applyImport(
        analysis: analysis,
        db: db,
        customBackupDir: tempDir.path,
      );
      expect(result.insertedIdeasCount, 2);

      final rows = await db.query('thoughts', where: "id = ?", whereArgs: ['phone-idea-1']);
      expect(rows.length, 1);
      expect(rows.first['title_source'], 'user');
      expect(rows.first['title'], 'My Groceries');
    });
  });
}

Future<String> _computeChecksum(Map<String, dynamic> data) async {
  final canonicalJson = ThoughtBundleService.canonicalJsonEncode(data);
  return sha256.convert(utf8.encode(canonicalJson)).toString();
}
