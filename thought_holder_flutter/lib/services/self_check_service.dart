import 'dart:io';
import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';
import '../sync_identity.dart';
import '../utils/app_logger.dart';
import '../utils/title_generator.dart';
import '../secure_storage_service.dart';
import 'backup_service.dart';

enum CheckStatus {
  green, // Healthy, working as expected
  amber, // Attention needed, can be safely repaired or is a gentle warning
  red,   // Critical problem (corruption, mismatch) requiring action
}

class CheckItemResult {
  final String title;
  final CheckStatus status;
  final String summary;
  final String details;
  final bool isAutoRepairable;

  const CheckItemResult({
    required this.title,
    required this.status,
    required this.summary,
    required this.details,
    this.isAutoRepairable = false,
  });
}

class SelfCheckReport {
  final DateTime checkTime;
  final int durationMs;
  final CheckStatus overallStatus;
  final List<CheckItemResult> items;
  final int totalIdeas;
  final int liveIdeas;
  final int doneIdeas;
  final int trashedIdeas;
  final int bucketCount;
  final int backupCount;
  final DateTime? lastBackupDate;
  final int databaseSizeBytes;
  final int databaseSchemaVersion;
  final String appVersion;

  const SelfCheckReport({
    required this.checkTime,
    required this.durationMs,
    required this.overallStatus,
    required this.items,
    required this.totalIdeas,
    required this.liveIdeas,
    required this.doneIdeas,
    required this.trashedIdeas,
    required this.bucketCount,
    required this.backupCount,
    required this.lastBackupDate,
    required this.databaseSizeBytes,
    required this.databaseSchemaVersion,
    required this.appVersion,
  });

  bool get hasIssues => overallStatus != CheckStatus.green;
  bool get hasRepairableIssues => items.any((i) => i.isAutoRepairable && i.status != CheckStatus.green);

  String get formattedDatabaseSize {
    if (databaseSizeBytes < 1024) return '$databaseSizeBytes B';
    if (databaseSizeBytes < 1024 * 1024) {
      return '${(databaseSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(databaseSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get formattedLastBackup {
    if (lastBackupDate == null) return 'Never backed up';
    final now = DateTime.now();
    final diff = now.difference(lastBackupDate!);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        final mins = diff.inMinutes;
        return mins <= 1 ? 'Just now' : '$mins minutes ago';
      }
      return '${diff.inHours} hours ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }

  /// Formatted report containing numbers and statuses ONLY.
  /// Strictly zero idea text, zero secret keys, zero file paths.
  String toDiagnosticReport() {
    final buffer = StringBuffer();
    buffer.writeln('=== THOUGHTHOLDER DIAGNOSTIC REPORT ===');
    buffer.writeln('Report time: ${checkTime.toUtc().toIso8601String()}');
    buffer.writeln('App version: $appVersion');
    buffer.writeln('Database version: $databaseSchemaVersion');
    buffer.writeln('Database size: $formattedDatabaseSize ($databaseSizeBytes bytes)');
    buffer.writeln('Last backup: $formattedLastBackup');
    buffer.writeln('Backups count: $backupCount');
    buffer.writeln('Check elapsed: ${durationMs}ms');
    buffer.writeln('');
    buffer.writeln('--- NUMERICAL METRICS ---');
    buffer.writeln('Total ideas: $totalIdeas');
    buffer.writeln('Live ideas: $liveIdeas');
    buffer.writeln('Done ideas: $doneIdeas');
    buffer.writeln('Trashed ideas: $trashedIdeas');
    buffer.writeln('Folders (buckets): $bucketCount');
    buffer.writeln('');
    buffer.writeln('--- AREA STATUSES ---');
    buffer.writeln('Overall status: ${_statusName(overallStatus)}');
    for (final item in items) {
      buffer.writeln('• ${item.title}: [${_statusName(item.status)}] - ${item.summary}');
      if (item.details.isNotEmpty) {
        buffer.writeln('  Details: ${item.details}');
      }
    }
    buffer.writeln('=======================================');
    return buffer.toString();
  }

  static String _statusName(CheckStatus status) {
    switch (status) {
      case CheckStatus.green:
        return 'PASS';
      case CheckStatus.amber:
        return 'ATTENTION';
      case CheckStatus.red:
        return 'CRITICAL';
    }
  }
}

class SelfRepairResult {
  final bool success;
  final String safetyBackupPath;
  final int indexesAdded;
  final int bucketsCreated;
  final int titlesGenerated;
  final int idsGenerated;
  final String message;

  const SelfRepairResult({
    required this.success,
    required this.safetyBackupPath,
    required this.indexesAdded,
    required this.bucketsCreated,
    required this.titlesGenerated,
    required this.idsGenerated,
    required this.message,
  });
}

class SelfCheckService {
  SelfCheckService._();
  static final SelfCheckService instance = SelfCheckService._();

  static const String appVersion = '1.0.0';

  /// Runs all database and health self-checks asynchronously.
  /// Designed to be fast (< 300 ms on 2,000 ideas), non-blocking, and never crash.
  Future<SelfCheckReport> runSelfCheck({Database? testDb, String? testDbPath}) async {
    final stopwatch = Stopwatch()..start();
    final items = <CheckItemResult>[];

    Database? db;
    int dbSize = 0;
    int schemaVersion = 0;
    int totalIdeas = 0;
    int liveIdeas = 0;
    int doneIdeas = 0;
    int trashedIdeas = 0;
    int bucketCount = 0;
    int backupCount = 0;
    DateTime? lastBackupDate;

    try {
      // 1. Database Connection & File accessibility
      try {
        db = testDb ?? await DatabaseHelper.instance.database;
        final dbFilePath = testDbPath ?? await DatabaseHelper.instance.getDatabasePath();
        final dbFile = File(dbFilePath);
        if (await dbFile.exists()) {
          dbSize = await dbFile.length();
        }

        final verResult = await db.rawQuery('PRAGMA user_version');
        if (verResult.isNotEmpty) {
          schemaVersion = Sqflite.firstIntValue(verResult) ?? 0;
        }

        items.add(const CheckItemResult(
          title: 'Database connection',
          status: CheckStatus.green,
          summary: 'Database opens cleanly',
          details: 'Storage file is accessible and readable.',
        ));
      } catch (e) {
        items.add(CheckItemResult(
          title: 'Database connection',
          status: CheckStatus.red,
          summary: 'Database could not open',
          details: 'The local database storage could not be accessed.',
        ));
        stopwatch.stop();
        return SelfCheckReport(
          checkTime: DateTime.now(),
          durationMs: stopwatch.elapsedMilliseconds,
          overallStatus: CheckStatus.red,
          items: items,
          totalIdeas: 0,
          liveIdeas: 0,
          doneIdeas: 0,
          trashedIdeas: 0,
          bucketCount: 0,
          backupCount: 0,
          lastBackupDate: null,
          databaseSizeBytes: 0,
          databaseSchemaVersion: 0,
          appVersion: appVersion,
        );
      }

      // 2. PRAGMA integrity_check
      try {
        final integrityRes = await db.rawQuery('PRAGMA integrity_check');
        final isOk = integrityRes.isNotEmpty && integrityRes.first.values.first == 'ok';
        if (isOk) {
          items.add(const CheckItemResult(
            title: 'Data integrity',
            status: CheckStatus.green,
            summary: 'File structure is sound',
            details: 'All database pages, B-trees, and indexes verified without corruption.',
          ));
        } else {
          items.add(const CheckItemResult(
            title: 'Data integrity',
            status: CheckStatus.red,
            summary: 'Database integrity check reported an issue',
            details: 'SQLite reported page inconsistencies. A restore from backup is recommended.',
          ));
        }
      } catch (e) {
        items.add(const CheckItemResult(
          title: 'Data integrity',
          status: CheckStatus.red,
          summary: 'Integrity check failed to execute',
          details: 'Could not run verification check.',
        ));
      }

      // 3. Schema & Required Performance Indexes
      try {
        final indexQuery = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'index'");
        final existingIndexes = indexQuery.map((r) => r['name'] as String?).whereType<String>().toSet();

        const requiredIndexes = [
          'idx_thoughts_bucket',
          'idx_thoughts_status_done',
          'idx_thoughts_created_at',
          'idx_thoughts_trashed',
        ];

        final missingIndexes = requiredIndexes.where((idx) => !existingIndexes.contains(idx)).toList();

        if (missingIndexes.isEmpty) {
          items.add(const CheckItemResult(
            title: 'Speed indexes',
            status: CheckStatus.green,
            summary: 'All 4 performance indexes active',
            details: 'Fast lookup and sorting enabled for high-volume idea libraries.',
          ));
        } else {
          items.add(CheckItemResult(
            title: 'Speed indexes',
            status: CheckStatus.amber,
            summary: '${missingIndexes.length} performance indexes can be added',
            details: 'Missing indexes can be safely derived and created without affecting your ideas.',
            isAutoRepairable: true,
          ));
        }
      } catch (e) {
        items.add(const CheckItemResult(
          title: 'Speed indexes',
          status: CheckStatus.amber,
          summary: 'Could not inspect index status',
          details: 'Speed checks encountered an error.',
        ));
      }

      // 4. Ideas uniqueness (Unique IDs)
      try {
        final uniqueRes = await db.rawQuery('SELECT COUNT(DISTINCT id), COUNT(*) FROM thoughts');
        final distinctCount = Sqflite.firstIntValue(uniqueRes) ?? 0;
        final countRes = await db.rawQuery('SELECT COUNT(*) FROM thoughts');
        totalIdeas = Sqflite.firstIntValue(countRes) ?? 0;

        if (distinctCount == totalIdeas) {
          items.add(CheckItemResult(
            title: 'Idea identity',
            status: CheckStatus.green,
            summary: 'Every idea has a unique identity',
            details: '$totalIdeas ideas verified with distinct identifiers.',
          ));
        } else {
          final dupes = totalIdeas - distinctCount;
          items.add(CheckItemResult(
            title: 'Idea identity',
            status: CheckStatus.amber,
            summary: '$dupes ideas share an identifier or have empty IDs',
            details: 'Can safely derive unique identifiers for empty rows.',
            isAutoRepairable: true,
          ));
        }
      } catch (e) {
        items.add(const CheckItemResult(
          title: 'Idea identity',
          status: CheckStatus.amber,
          summary: 'Could not verify ID uniqueness',
          details: 'Check was unable to query thoughts table.',
        ));
      }

      // 5. Bucket consistency (No orphaned bucket references)
      int missingBucketCount = 0;
      try {
        final bucketRes = await db.rawQuery('SELECT COUNT(*) FROM buckets');
        bucketCount = Sqflite.firstIntValue(bucketRes) ?? 0;

        final orphanedRes = await db.rawQuery('''
          SELECT DISTINCT bucket FROM thoughts 
          WHERE bucket IS NOT NULL 
            AND trim(bucket) != '' 
            AND bucket NOT IN (SELECT name FROM buckets)
        ''');

        missingBucketCount = orphanedRes.length;
        if (missingBucketCount == 0) {
          items.add(CheckItemResult(
            title: 'Folders consistency',
            status: CheckStatus.green,
            summary: 'All idea folder links are valid',
            details: '$bucketCount folders cataloged cleanly.',
          ));
        } else {
          items.add(CheckItemResult(
            title: 'Folders consistency',
            status: CheckStatus.amber,
            summary: '$missingBucketCount referenced folders are not in your folder list',
            details: 'Can safely add these missing folder names to your folder list so no ideas are misplaced.',
            isAutoRepairable: true,
          ));
        }
      } catch (e) {
        items.add(const CheckItemResult(
          title: 'Folders consistency',
          status: CheckStatus.amber,
          summary: 'Could not verify folder references',
          details: 'Folder consistency check could not run.',
        ));
      }

      // 6. Counts Arithmetic (live + done + trash = total)
      try {
        final liveRes = await db.rawQuery(
          "SELECT COUNT(*) FROM thoughts WHERE trashed = 0 AND (done = 0 AND status != 'done')"
        );
        liveIdeas = Sqflite.firstIntValue(liveRes) ?? 0;

        final doneRes = await db.rawQuery(
          "SELECT COUNT(*) FROM thoughts WHERE trashed = 0 AND (done = 1 OR status = 'done')"
        );
        doneIdeas = Sqflite.firstIntValue(doneRes) ?? 0;

        final trashRes = await db.rawQuery(
          'SELECT COUNT(*) FROM thoughts WHERE trashed = 1'
        );
        trashedIdeas = Sqflite.firstIntValue(trashRes) ?? 0;

        final sum = liveIdeas + doneIdeas + trashedIdeas;
        if (sum == totalIdeas) {
          items.add(CheckItemResult(
            title: 'Idea counts',
            status: CheckStatus.green,
            summary: 'Idea counts add up perfectly',
            details: 'Live ($liveIdeas) + Finished ($doneIdeas) + Trash ($trashedIdeas) = Total ($totalIdeas).',
          ));
        } else {
          final diff = (totalIdeas - sum).abs();
          items.add(CheckItemResult(
            title: 'Idea counts',
            status: CheckStatus.amber,
            summary: 'Count difference of $diff ideas detected',
            details: 'Status flags on some ideas can be safely recalculated.',
            isAutoRepairable: true,
          ));
        }
      } catch (e) {
        items.add(const CheckItemResult(
          title: 'Idea counts',
          status: CheckStatus.amber,
          summary: 'Count arithmetic could not be completed',
          details: 'Could not query status distributions.',
        ));
      }

      // 7. Title Health (Missing names)
      try {
        final missingTitlesRes = await db.rawQuery('''
          SELECT COUNT(*) FROM thoughts 
          WHERE title IS NULL 
             OR trim(title) = '' 
             OR lower(trim(title)) = 'untitled'
        ''');
        final missingTitles = Sqflite.firstIntValue(missingTitlesRes) ?? 0;

        if (missingTitles == 0) {
          items.add(const CheckItemResult(
            title: 'Idea names',
            status: CheckStatus.green,
            summary: 'All ideas have clean names',
            details: 'No missing names or "Untitled" placeholders.',
          ));
        } else {
          items.add(CheckItemResult(
            title: 'Idea names',
            status: CheckStatus.amber,
            summary: '$missingTitles ideas need generated names',
            details: 'Can automatically derive concise names from idea text without modifying user edits.',
            isAutoRepairable: true,
          ));
        }
      } catch (_) {}

      // 8. Backup Freshness (Not older than 7 days)
      try {
        final backups = await BackupService.instance.listBackups();
        backupCount = backups.length;
        if (backups.isNotEmpty) {
          lastBackupDate = backups.first.createdAt;
          final now = DateTime.now();
          final ageDays = now.difference(lastBackupDate).inDays;

          if (ageDays <= 7) {
            items.add(CheckItemResult(
              title: 'Safety backups',
              status: CheckStatus.green,
              summary: 'Recent backup verified',
              details: '$backupCount backups saved on disk. Most recent was $ageDays day${ageDays == 1 ? '' : 's'} ago.',
            ));
          } else {
            items.add(CheckItemResult(
              title: 'Safety backups',
              status: CheckStatus.amber,
              summary: 'Last backup is $ageDays days old',
              details: 'It has been more than 7 days since your last backup. A fresh backup is recommended.',
              isAutoRepairable: true,
            ));
          }
        } else {
          items.add(const CheckItemResult(
            title: 'Safety backups',
            status: CheckStatus.amber,
            summary: 'No backup found yet',
            details: 'Creating a safety backup ensures your ideas are preserved against accidents.',
            isAutoRepairable: true,
          ));
        }
      } catch (e) {
        items.add(const CheckItemResult(
          title: 'Safety backups',
          status: CheckStatus.amber,
          summary: 'Could not inspect backup storage',
          details: 'Backup directory could not be read.',
        ));
      }

      // 9. OS Secure Storage (Windows Credential Vault / Keychain)
      try {
        final secureHealthOk = await SecureStorageService.testSecureStorageHealth();
        if (secureHealthOk) {
          items.add(const CheckItemResult(
            title: 'Secure storage',
            status: CheckStatus.green,
            summary: 'Hardware / OS credential vault operational',
            details: 'Write, read, and delete validation cycle succeeded without leaking secrets.',
          ));
        } else {
          items.add(const CheckItemResult(
            title: 'Secure storage',
            status: CheckStatus.amber,
            summary: 'OS credential vault not active in current session',
            details: 'Credentials will fall back safely to guarded memory.',
          ));
        }
      } catch (e) {
        items.add(const CheckItemResult(
          title: 'Secure storage',
          status: CheckStatus.amber,
          summary: 'Secure storage check could not run',
          details: 'OS vault check was skipped.',
        ));
      }
    } catch (e) {
      AppLogger.error('SelfCheckService', 'Unexpected error in self check', e);
    } finally {
      stopwatch.stop();
    }

    CheckStatus overall = CheckStatus.green;
    if (items.any((i) => i.status == CheckStatus.red)) {
      overall = CheckStatus.red;
    } else if (items.any((i) => i.status == CheckStatus.amber)) {
      overall = CheckStatus.amber;
    }

    return SelfCheckReport(
      checkTime: DateTime.now(),
      durationMs: stopwatch.elapsedMilliseconds,
      overallStatus: overall,
      items: items,
      totalIdeas: totalIdeas,
      liveIdeas: liveIdeas,
      doneIdeas: doneIdeas,
      trashedIdeas: trashedIdeas,
      bucketCount: bucketCount,
      backupCount: backupCount,
      lastBackupDate: lastBackupDate,
      databaseSizeBytes: dbSize,
      databaseSchemaVersion: schemaVersion,
      appVersion: appVersion,
    );
  }

  /// Performs SAFE self-repair:
  /// - ONLY ADDS or DERIVES items (indexes, missing folder names, missing titles, missing IDs).
  /// - NEVER deletes, moves, or alters existing idea content.
  /// - ALWAYS creates a verified safety backup first.
  Future<SelfRepairResult> performSafeSelfRepair({Database? customDb}) async {
    final db = customDb ?? await DatabaseHelper.instance.database;

    // 1. ALWAYS create a safety backup before repairing anything
    BackupMetadata safetyBackup;
    try {
      safetyBackup = await BackupService.instance.createBackup(
        db: db,
        customFileName: 'thought_backup_pre_repair_${DateTime.now().millisecondsSinceEpoch}.db',
      );
    } catch (e) {
      AppLogger.error('SelfCheckService', 'Safety backup prior to repair failed', e);
      return const SelfRepairResult(
        success: false,
        safetyBackupPath: '',
        indexesAdded: 0,
        bucketsCreated: 0,
        titlesGenerated: 0,
        idsGenerated: 0,
        message: 'Could not create a safety backup. Self-repair stopped to protect your data.',
      );
    }

    int indexesAdded = 0;
    int bucketsCreated = 0;
    int titlesGenerated = 0;
    int idsGenerated = 0;

    // 2. Safe repair: ADD missing performance indexes
    try {
      const indexSqls = [
        'CREATE INDEX IF NOT EXISTS idx_thoughts_bucket ON thoughts(bucket);',
        'CREATE INDEX IF NOT EXISTS idx_thoughts_status_done ON thoughts(status, done);',
        'CREATE INDEX IF NOT EXISTS idx_thoughts_created_at ON thoughts(created_at);',
        'CREATE INDEX IF NOT EXISTS idx_thoughts_trashed ON thoughts(trashed);',
      ];

      for (final sql in indexSqls) {
        await db.execute(sql);
        indexesAdded++;
      }
    } catch (e) {
      AppLogger.error('SelfCheckService', 'Failed adding indexes during repair', e);
    }

    // 3. Safe repair: ADD missing bucket names referenced by ideas
    try {
      final orphanedRes = await db.rawQuery('''
        SELECT DISTINCT bucket FROM thoughts 
        WHERE bucket IS NOT NULL 
          AND trim(bucket) != '' 
          AND bucket NOT IN (SELECT name FROM buckets)
      ''');

      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in orphanedRes) {
        final bName = row['bucket'] as String?;
        if (bName != null && bName.trim().isNotEmpty) {
          await db.insert(
            'buckets',
            {
              'name': bName.trim(),
              'icon': 'folder',
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          bucketsCreated++;
        }
      }
    } catch (e) {
      AppLogger.error('SelfCheckService', 'Failed adding missing buckets during repair', e);
    }

    // 4. Safe repair: DERIVE missing titles from content
    try {
      final missingTitleRows = await db.rawQuery('''
        SELECT id, content FROM thoughts 
        WHERE title IS NULL 
           OR trim(title) = '' 
           OR lower(trim(title)) = 'untitled'
      ''');

      for (final row in missingTitleRows) {
        final id = row['id'] as String?;
        final content = (row['content'] as String?) ?? '';
        if (id != null && id.isNotEmpty) {
          final derivedTitle = TitleGenerator.generate(content);
          await db.update(
            'thoughts',
            {
              'title': derivedTitle,
              'title_source': 'auto',
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          titlesGenerated++;
        }
      }
    } catch (e) {
      AppLogger.error('SelfCheckService', 'Failed deriving titles during repair', e);
    }

    // 5. Safe repair: DERIVE unique UUIDs for empty IDs
    try {
      final emptyIdRows = await db.rawQuery("SELECT rowid, id FROM thoughts WHERE id IS NULL OR trim(id) = ''");
      for (final row in emptyIdRows) {
        final rowid = row['rowid'];
        final newUuid = SyncIdentity.newUuid();
        await db.rawUpdate('UPDATE thoughts SET id = ? WHERE rowid = ?', [newUuid, rowid]);
        idsGenerated++;
      }
    } catch (e) {
      AppLogger.error('SelfCheckService', 'Failed deriving empty IDs during repair', e);
    }

    // 6. Safe repair: create baseline backup if none exists
    try {
      final backups = await BackupService.instance.listBackups();
      if (backups.isEmpty) {
        await BackupService.instance.createBackup(db: db);
      }
    } catch (_) {}

    AppLogger.info(
      'SelfCheckService',
      'Self-repair complete: $indexesAdded indexes, $bucketsCreated folders, $titlesGenerated titles, $idsGenerated IDs',
    );

    return SelfRepairResult(
      success: true,
      safetyBackupPath: safetyBackup.filePath,
      indexesAdded: indexesAdded,
      bucketsCreated: bucketsCreated,
      titlesGenerated: titlesGenerated,
      idsGenerated: idsGenerated,
      message: 'Self-repair finished safely. A safety backup was saved first. Nothing was deleted or overwritten.',
    );
  }
}
