import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';
import '../utils/app_logger.dart';

/// Metadata for a verified backup file.
class BackupMetadata {
  final String filePath;
  final String fileName;
  final DateTime createdAt;
  final int sizeBytes;
  final int ideaCount;
  final bool integrityOk;

  const BackupMetadata({
    required this.filePath,
    required this.fileName,
    required this.createdAt,
    required this.sizeBytes,
    required this.ideaCount,
    required this.integrityOk,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get formattedDate {
    final y = createdAt.year.toString().padLeft(4, '0');
    final m = createdAt.month.toString().padLeft(2, '0');
    final d = createdAt.day.toString().padLeft(2, '0');
    final hh = createdAt.hour.toString().padLeft(2, '0');
    final mm = createdAt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

/// Prepared restore stage: holds verified temporary database stats
/// before user confirms replacement.
class RestorePreparation {
  final File backupFile;
  final File tempDatabaseFile;
  final int backupIdeaCount;
  final int currentIdeaCount;
  final bool integrityOk;

  const RestorePreparation({
    required this.backupFile,
    required this.tempDatabaseFile,
    required this.backupIdeaCount,
    required this.currentIdeaCount,
    required this.integrityOk,
  });
}

class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// Resolves the dedicated application backups directory.
  Future<Directory> getBackupsDirectory({String? customPath}) async {
    if (customPath != null) {
      final dir = Directory(customPath);
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }

    String basePath;
    try {
      if (!kIsWeb && Platform.isWindows) {
        final appSupport = await getApplicationSupportDirectory();
        basePath = join(appSupport.path, 'backups');
      } else {
        final dbPath = await getDatabasesPath();
        basePath = join(dbPath, 'backups');
      }
    } catch (_) {
      basePath = join(Directory.systemTemp.path, 'ThoughtHolderBackups');
    }

    final dir = Directory(basePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Creates a consistent database snapshot using SQLite's native VACUUM INTO,
  /// verifies its integrity, records idea count and size, and keeps the last 5.
  Future<BackupMetadata> createBackup({
    Database? db,
    String? customDirectoryPath,
    String? customFileName,
  }) async {
    final activeDb = db ?? await DatabaseHelper.instance.database;
    final backupsDir = await getBackupsDirectory(customPath: customDirectoryPath);

    final now = DateTime.now();
    final timestampStr = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';

    final fileName = customFileName ?? 'thought_backup_$timestampStr.db';
    final targetPath = join(backupsDir.path, fileName);
    final targetFile = File(targetPath);

    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    // Escape single quotes for SQLite string literal
    final escapedPath = targetPath.replaceAll("'", "''");

    // Perform VACUUM INTO for a non-blocking, clean snapshot
    await activeDb.execute("VACUUM INTO '$escapedPath'");

    // Verify backup integrity and read real idea count
    final checkDb = await openDatabase(targetPath, readOnly: true);
    bool integrityOk = false;
    int ideaCount = 0;
    try {
      final checkRes = await checkDb.rawQuery('PRAGMA integrity_check');
      integrityOk = checkRes.isNotEmpty && checkRes.first.values.first == 'ok';

      final countRes = await checkDb.rawQuery('SELECT COUNT(*) FROM thoughts');
      if (countRes.isNotEmpty) {
        ideaCount = Sqflite.firstIntValue(countRes) ?? 0;
      }
    } finally {
      await checkDb.close();
    }

    final sizeBytes = await targetFile.length();

    // Prune older backups to keep the newest 5
    await _pruneOldBackups(backupsDir, keep: 5);

    AppLogger.info('BackupService', 'Backup created successfully: $fileName ($sizeBytes bytes, $ideaCount ideas)');

    return BackupMetadata(
      filePath: targetPath,
      fileName: fileName,
      createdAt: now,
      sizeBytes: sizeBytes,
      ideaCount: ideaCount,
      integrityOk: integrityOk,
    );
  }

  /// Lists all stored thought backups sorted newest first.
  Future<List<BackupMetadata>> listBackups({String? customDirectoryPath}) async {
    final dir = await getBackupsDirectory(customPath: customDirectoryPath);
    if (!await dir.exists()) return [];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => basename(f.path).startsWith('thought_backup_') && f.path.endsWith('.db'))
        .toList();

    final List<BackupMetadata> result = [];

    for (final f in files) {
      final size = await f.length();
      final stat = await f.stat();
      int count = 0;
      bool ok = false;
      try {
        final checkDb = await openDatabase(f.path, readOnly: true);
        final checkRes = await checkDb.rawQuery('PRAGMA integrity_check');
        ok = checkRes.isNotEmpty && checkRes.first.values.first == 'ok';
        final countRes = await checkDb.rawQuery('SELECT COUNT(*) FROM thoughts');
        count = Sqflite.firstIntValue(countRes) ?? 0;
        await checkDb.close();
      } catch (e) {
        AppLogger.error('BackupService', 'Could not inspect backup ${f.path}', e);
      }

      result.add(BackupMetadata(
        filePath: f.path,
        fileName: basename(f.path),
        createdAt: stat.modified,
        sizeBytes: size,
        ideaCount: count,
        integrityOk: ok,
      ));
    }

    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// Prepares a safe restore:
  /// 1. Makes a safety backup of current live data first.
  /// 2. Restores candidate into a TEMPORARY database.
  /// 3. Verifies integrity and counts.
  /// 4. Returns data needed to ask: "This backup has N ideas, now you have M. Replace?".
  Future<RestorePreparation> prepareRestore(
    File backupFile, {
    Database? liveDb,
    String? liveDbPath,
  }) async {
    if (!await backupFile.exists()) {
      throw Exception('Selected backup file does not exist: ${backupFile.path}');
    }

    // 1. Safety backup of current live database
    try {
      await createBackup(db: liveDb, customFileName: 'thought_backup_pre_restore_${DateTime.now().millisecondsSinceEpoch}.db');
    } catch (e) {
      AppLogger.error('BackupService', 'Safety backup prior to restore failed', e);
      throw Exception('Could not create a safety backup before restoring. Restore aborted for safety.');
    }

    // 2. Copy into temporary database file
    Directory tempDir;
    try {
      tempDir = await getTemporaryDirectory();
    } catch (_) {
      tempDir = Directory.systemTemp;
    }
    final tempDbPath = join(tempDir.path, 'restore_temp_${DateTime.now().millisecondsSinceEpoch}.db');
    final tempFile = await backupFile.copy(tempDbPath);

    // 3. Verify integrity of temporary database
    final checkDb = await openDatabase(tempFile.path, readOnly: true);
    bool integrityOk = false;
    int backupIdeaCount = 0;
    try {
      final checkRes = await checkDb.rawQuery('PRAGMA integrity_check');
      integrityOk = checkRes.isNotEmpty && checkRes.first.values.first == 'ok';
      if (!integrityOk) {
        throw Exception('The selected backup file is corrupted. PRAGMA integrity_check did not pass.');
      }
      final countRes = await checkDb.rawQuery('SELECT COUNT(*) FROM thoughts');
      backupIdeaCount = Sqflite.firstIntValue(countRes) ?? 0;
    } finally {
      await checkDb.close();
    }

    // 4. Read current idea count
    int currentIdeaCount = 0;
    try {
      final db = liveDb ?? await DatabaseHelper.instance.database;
      final curRes = await db.rawQuery('SELECT COUNT(*) FROM thoughts');
      currentIdeaCount = Sqflite.firstIntValue(curRes) ?? 0;
    } catch (_) {
      currentIdeaCount = 0;
    }

    return RestorePreparation(
      backupFile: backupFile,
      tempDatabaseFile: tempFile,
      backupIdeaCount: backupIdeaCount,
      currentIdeaCount: currentIdeaCount,
      integrityOk: integrityOk,
    );
  }

  /// Finalizes restore after user confirmation:
  /// Closes database connection, swaps verified temporary DB into live path,
  /// re-opens database, and cleans up.
  Future<void> completeRestore(
    RestorePreparation prep, {
    String? liveDbPath,
  }) async {
    final targetPath = liveDbPath ?? await DatabaseHelper.instance.getDatabasePath();

    // Close active database connections
    await DatabaseHelper.instance.close();

    // Replace live file with verified temporary file
    final targetFile = File(targetPath);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    await prep.tempDatabaseFile.copy(targetPath);

    // Clean up temp database file
    try {
      if (await prep.tempDatabaseFile.exists()) {
        await prep.tempDatabaseFile.delete();
      }
    } catch (_) {}

    // Reopen database
    await DatabaseHelper.instance.database;

    AppLogger.info('BackupService', 'Restore completed successfully to $targetPath');
  }

  /// Exports a verified copy of the latest backup to an external directory
  /// (defaulting to Documents\ThoughtHolderBackups).
  Future<File> exportBackupToExternalFolder({String? customDestinationDir}) async {
    final backups = await listBackups();
    BackupMetadata source;
    if (backups.isNotEmpty && backups.first.integrityOk) {
      source = backups.first;
    } else {
      source = await createBackup();
    }

    String targetDirStr = customDestinationDir ?? '';
    if (targetDirStr.isEmpty) {
      if (!kIsWeb && Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'] ?? '';
        targetDirStr = join(userProfile, 'Documents', 'ThoughtHolderBackups');
      } else {
        try {
          final docsDir = await getApplicationDocumentsDirectory();
          targetDirStr = join(docsDir.path, 'ThoughtHolderBackups');
        } catch (_) {
          targetDirStr = join(Directory.systemTemp.path, 'ThoughtHolderBackups');
        }
      }
    }

    final targetDir = Directory(targetDirStr);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final targetPath = join(targetDir.path, source.fileName);
    final targetFile = await File(source.filePath).copy(targetPath);

    // Verify integrity of the exported copy
    final checkDb = await openDatabase(targetFile.path, readOnly: true);
    try {
      final res = await checkDb.rawQuery('PRAGMA integrity_check');
      if (res.isEmpty || res.first.values.first != 'ok') {
        throw Exception('Exported backup copy failed integrity verification.');
      }
    } finally {
      await checkDb.close();
    }

    AppLogger.info('BackupService', 'Exported verified copy to: $targetPath');
    return targetFile;
  }

  /// Prunes backups keeping only the [keep] newest files.
  Future<void> _pruneOldBackups(Directory dir, {int keep = 5}) async {
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => basename(f.path).startsWith('thought_backup_') && f.path.endsWith('.db'))
          .toList();

      if (files.length <= keep) return;

      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      for (int i = keep; i < files.length; i++) {
        try {
          await files[i].delete();
          AppLogger.info('BackupService', 'Pruned old backup: ${basename(files[i].path)}');
        } catch (_) {}
      }
    } catch (e) {
      AppLogger.error('BackupService', 'Error pruning old backups', e);
    }
  }
}
