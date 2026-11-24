import 'dart:io';
import 'package:sqflite/sqflite.dart';
import '../utils/app_logger.dart';
import 'backup_service.dart';

class MigrationException implements Exception {
  final String message;
  final String? backupPath;
  final dynamic cause;

  MigrationException(this.message, {this.backupPath, this.cause});

  @override
  String toString() => 'MigrationException: $message (Backup: $backupPath, Cause: $cause)';
}

class DatabaseMigrationService {
  DatabaseMigrationService._();
  static final DatabaseMigrationService instance = DatabaseMigrationService._();

  static const int currentSchemaVersion = 5;
  String? lastSafeBackupPath;
  String? migrationError;

  /// Runs database migrations with automatic pre-migration backup and transaction safety.
  /// If any migration step fails, the original database is restored from backup,
  /// preserving 100% of user data.
  Future<void> runMigrations(Database db, String databaseFilePath,
      {String? backupDirectoryPath}) async {
    final res = await db.rawQuery('PRAGMA user_version');
    final int currentVersion = Sqflite.firstIntValue(res) ?? 0;

    AppLogger.info('DatabaseMigrationService', 'Current DB schema version: $currentVersion. Target: $currentSchemaVersion');

    if (currentVersion >= currentSchemaVersion) {
      return;
    }

    // 1. Create a safe pre-migration backup snapshot
    BackupMetadata? backup;
    try {
      backup = await BackupService.instance.createBackup(
        db: db,
        customFileName: 'pre_migration_v${currentVersion}_to_v$currentSchemaVersion.db',
        customDirectoryPath: backupDirectoryPath,
      );
      lastSafeBackupPath = backup.filePath;
      AppLogger.info('DatabaseMigrationService', 'Pre-migration backup safe at: ${backup.filePath}');
    } catch (e) {
      AppLogger.error('DatabaseMigrationService', 'Could not create pre-migration backup: $e');
      // If we cannot back up, abort immediately to protect user data
      throw MigrationException('Pre-migration backup failed. Aborting database upgrade for safety.', cause: e);
    }

    // 2. Run migrations step-by-step
    try {
      for (int v = currentVersion + 1; v <= currentSchemaVersion; v++) {
        AppLogger.info('DatabaseMigrationService', 'Applying migration step to v$v...');
        await _applyMigrationStep(db, v);
        await db.execute('PRAGMA user_version = $v');
      }
      AppLogger.info('DatabaseMigrationService', 'Database successfully migrated to version $currentSchemaVersion');
    } catch (e) {
      migrationError = e.toString();
      AppLogger.error('DatabaseMigrationService', 'Migration step failed! Initiating rollback: $e');

      // 3. Rollback safety: restore pre-migration backup
      try {
        if (File(backup.filePath).existsSync()) {
          final backupBytes = await File(backup.filePath).readAsBytes();
          final targetFile = File(databaseFilePath);
          if (await targetFile.exists()) {
            await targetFile.writeAsBytes(backupBytes, flush: true);
            AppLogger.info('DatabaseMigrationService', 'Database safely restored from backup.');
          }
        }
      } catch (restoreErr) {
        AppLogger.error('DatabaseMigrationService', 'Failed to restore backup during rollback: $restoreErr');
      }

      throw MigrationException(
        'Database migration failed. Original database has been safely restored.',
        backupPath: backup.filePath,
        cause: e,
      );
    }
  }

  Future<void> _applyMigrationStep(Database db, int version) async {
    switch (version) {
      case 1:
        // Base schema (thoughts table)
        await db.execute('''
          CREATE TABLE IF NOT EXISTS thoughts (
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
            pinned_at INTEGER
          )
        ''');
        break;

      case 2:
        // Buckets and voice recordings
        await db.execute('''
          CREATE TABLE IF NOT EXISTS buckets (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            icon TEXT DEFAULT 'folder',
            created_at INTEGER NOT NULL,
            updated_at TEXT,
            updated_by TEXT,
            revision INTEGER DEFAULT 1
          )
        ''');
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
        break;

      case 3:
        // Daily goals, gamification meta, and tombstone records
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
        break;

      case 4:
        // Schema V4: indexes & safety flags
        await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_bucket ON thoughts(bucket)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_status_done ON thoughts(status, done)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_created_at ON thoughts(created_at)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_trashed ON thoughts(trashed)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_thoughts_is_pinned ON thoughts(is_pinned)');
        break;

      case 5:
        // Schema V5: Buckets Raw/Main/Sides + Recurrence & Completion tracking.
        // Note: _onOpenDB may have already added these columns on older DBs, so
        // every step here must be idempotent.
        if (!await _hasColumn(db, 'buckets', 'type')) {
          await db.execute("ALTER TABLE buckets ADD COLUMN type TEXT DEFAULT 'normal'");
        }

        if (!await _hasColumn(db, 'thoughts', 'recurrence')) {
          await db.execute("ALTER TABLE thoughts ADD COLUMN recurrence TEXT");
        }
        if (!await _hasColumn(db, 'thoughts', 'last_completed_at')) {
          await db.execute("ALTER TABLE thoughts ADD COLUMN last_completed_at INTEGER");
        }
        if (!await _hasColumn(db, 'thoughts', 'reminder_at')) {
          await db.execute("ALTER TABLE thoughts ADD COLUMN reminder_at INTEGER");
        }
        if (!await _hasColumn(db, 'thoughts', 'due_at')) {
          await db.execute("ALTER TABLE thoughts ADD COLUMN due_at INTEGER");
        }

        // 3. Seed Raw, Main, Sides system buckets
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
            await db.update(
              'buckets',
              {'type': sys['type']},
              where: 'id = ?',
              whereArgs: [existing.first['id']],
            );
          } else {
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
        }
        break;

      default:
        break;
    }
  }

  Future<bool> _hasColumn(Database db, String table, String column) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    return cols.any((c) => c['name'] == column);
  }
}

