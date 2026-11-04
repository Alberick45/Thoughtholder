import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as c;
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';
import '../utils/app_logger.dart';
import 'backup_service.dart';

/// Service managing export and import of `.thoughtbundle` portable idea packages.
/// Format Version: 1
///
/// Rules:
/// - ideas: uuid, text, title, title_source, bucket uuid & name, when, time, status, created_at, updated_at, skipped_at, skip_count.
/// - buckets: uuid, name, icon, created_at.
/// - NO settings, NO keys, NO pairing data, NO audio.
/// - Header: format version, app version, exported-at, counts, SHA-256 checksum.
/// - Optional passphrase protection: AES/stream encryption, passphrase never stored.
class ThoughtBundleService {
  static final ThoughtBundleService instance = ThoughtBundleService._();
  ThoughtBundleService._();

  static const int formatVersion = 1;
  static const String appVersion = '1.0.0';

  /// Recursively sorts map keys to produce a deterministic, canonical JSON representation.
  static String canonicalJsonEncode(dynamic object) {
    dynamic sortValue(dynamic val) {
      if (val is Map) {
        final sortedMap = <String, dynamic>{};
        final sortedKeys = val.keys.map((k) => k.toString()).toList()..sort();
        for (final key in sortedKeys) {
          sortedMap[key] = sortValue(val[key]);
        }
        return sortedMap;
      } else if (val is List) {
        return val.map((e) => sortValue(e)).toList();
      }
      return val;
    }
    return jsonEncode(sortValue(object));
  }

  /// Extracts ideas and buckets from database and constructs the raw bundle data map.
  /// Wrapped in a single read transaction to guarantee a consistent snapshot point-in-time.
  /// Strictly excludes all settings, keys, pairing data, and audio.
  Future<Map<String, dynamic>> buildBundleData({Database? db}) async {
    final database = db ?? await DatabaseHelper.instance.database;

    return await database.transaction<Map<String, dynamic>>((txn) async {
      final thoughtRows = await txn.query('thoughts');
      final bucketRows = await txn.query('buckets');

      final Map<String, String> bucketNameToId = {};
      for (final b in bucketRows) {
        final name = b['name']?.toString() ?? '';
        final id = b['id']?.toString() ?? '';
        if (name.isNotEmpty && id.isNotEmpty) {
          bucketNameToId[name] = id;
        }
      }

      final List<Map<String, dynamic>> ideas = [];
      for (final r in thoughtRows) {
        // Determine clean status: 'trash', 'done', or 'active'
        String statusStr = 'active';
        final isTrashed = (r['trashed'] as int? ?? 0) == 1;
        final isDone = (r['done'] as int? ?? 0) == 1 || (r['status'] as String? ?? '').toLowerCase() == 'done';
        if (isTrashed) {
          statusStr = 'trash';
        } else if (isDone) {
          statusStr = 'done';
        }

        final bucketName = r['bucket']?.toString() ?? '';
        var bucketId = r['bucket_id']?.toString() ?? '';
        if (bucketId.isEmpty && bucketName.isNotEmpty && bucketNameToId.containsKey(bucketName)) {
          bucketId = bucketNameToId[bucketName]!;
        }

        ideas.add({
          'uuid': r['id']?.toString() ?? '',
          'text': r['content']?.toString() ?? '',
          'title': r['title']?.toString() ?? '',
          'title_source': r['title_source']?.toString() ?? 'auto',
          'bucket_uuid': bucketId,
          'bucket_name': bucketName,
          'when': r['when_val']?.toString() ?? 'Soon',
          'time': r['time_val']?.toString() ?? 'Medium',
          'status': statusStr,
          'created_at': r['created_at'],
          'updated_at': r['updated_at']?.toString(),
          'skipped_at': r['skipped_at'],
          'skip_count': r['skip_count'] as int? ?? 0,
        });
      }

      final List<Map<String, dynamic>> buckets = [];
      for (final b in bucketRows) {
        buckets.add({
          'uuid': b['id']?.toString() ?? '',
          'name': b['name']?.toString() ?? '',
          'icon': b['icon']?.toString() ?? 'folder',
          'created_at': b['created_at'],
        });
      }

      return {
        'ideas': ideas,
        'buckets': buckets,
      };
    });
  }

  /// Packages ideas and buckets into a verified `.thoughtbundle` JSON document.
  /// If [passphrase] is provided, encrypts the data section and never stores the passphrase.
  Future<String> createBundleString({
    Database? db,
    String? passphrase,
  }) async {
    final dataMap = await buildBundleData(db: db);
    final ideasList = dataMap['ideas'] as List;
    final bucketsList = dataMap['buckets'] as List;

    // 1. Calculate SHA-256 checksum on canonical data JSON
    final canonicalDataJson = canonicalJsonEncode(dataMap);
    final dataBytes = utf8.encode(canonicalDataJson);
    final checksum = sha256.convert(dataBytes).toString();

    final nowIso = DateTime.now().toUtc().toIso8601String();

    final header = <String, dynamic>{
      'format_version': formatVersion,
      'app_version': appVersion,
      'exported_at': nowIso,
      'counts': {
        'ideas': ideasList.length,
        'buckets': bucketsList.length,
      },
      'sha256': checksum,
      'is_encrypted': false,
      'salt': null,
    };

    final bundleEnvelope = <String, dynamic>{
      'header': header,
    };

    if (passphrase != null && passphrase.trim().isNotEmpty) {
      // Passphrase key derivation: Argon2id (RFC 9106) with 16-byte random salt
      final saltBytes = Uint8List(16);
      final rng = Random.secure();
      for (int i = 0; i < 16; i++) {
        saltBytes[i] = rng.nextInt(256);
      }
      final saltStr = base64Url.encode(saltBytes);

      const memoryKb = 19 * 1024; // 19 MB
      const iterations = 2;
      const parallelism = 1;
      const hashLength = 32;

      final argon2 = c.Argon2id(
        memory: memoryKb,
        iterations: iterations,
        parallelism: parallelism,
        hashLength: hashLength,
      );

      final derivedSecretKey = await argon2.deriveKey(
        secretKey: c.SecretKey(utf8.encode(passphrase.trim())),
        nonce: saltBytes,
      );

      // Standard authenticated cipher: AES-256-GCM with fresh random 12-byte nonce
      final aesGcm = c.AesGcm.with256bits();
      final secretBox = await aesGcm.encrypt(
        dataBytes,
        secretKey: derivedSecretKey,
      );

      header['is_encrypted'] = true;
      header['kdf'] = {
        'algorithm': 'argon2id',
        'memory_kb': memoryKb,
        'iterations': iterations,
        'parallelism': parallelism,
        'salt': saltStr,
        'hash_length': hashLength,
      };
      header['cipher'] = {
        'algorithm': 'aes-256-gcm',
        'nonce': base64Url.encode(secretBox.nonce),
        'mac': base64Url.encode(secretBox.mac.bytes),
      };
      bundleEnvelope['encrypted_data'] = base64Url.encode(secretBox.cipherText);
    } else {
      bundleEnvelope['data'] = dataMap;
    }

    return const JsonEncoder.withIndent('  ').convert(bundleEnvelope);
  }

  /// Resolves the default export folder according to platform conventions:
  /// - Windows: Documents\ThoughtHolderExports
  /// - Android/iOS: App documents directory / ThoughtHolderExports (no broad storage permission needed)
  Future<Directory> getDefaultExportDirectory({String? customPath}) async {
    if (customPath != null && customPath.trim().isNotEmpty) {
      final dir = Directory(customPath.trim());
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }

    String pathStr = '';
    if (!kIsWeb && Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      pathStr = p.join(userProfile, 'Documents', 'ThoughtHolderExports');
    } else {
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        pathStr = p.join(docsDir.path, 'ThoughtHolderExports');
      } catch (_) {
        pathStr = p.join(Directory.systemTemp.path, 'ThoughtHolderExports');
      }
    }

    final dir = Directory(pathStr);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Exports the user's ideas to a file on disk ending in `.thoughtbundle`.
  /// Returns a result map with file path, ideas count, buckets count, and directory.
  Future<ExportResult> exportToFile({
    Database? db,
    String? passphrase,
    String? customDestinationDir,
    String? customFileName,
  }) async {
    final bundleString = await createBundleString(db: db, passphrase: passphrase);

    final targetDir = await getDefaultExportDirectory(customPath: customDestinationDir);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = customFileName ?? 'thoughtbundle_$timestamp.thoughtbundle';
    final targetFile = File(p.join(targetDir.path, fileName));

    await targetFile.writeAsString(bundleString, flush: true);

    // Read back header to return exact numbers
    final envelope = jsonDecode(bundleString) as Map<String, dynamic>;
    final header = envelope['header'] as Map<String, dynamic>;
    final counts = header['counts'] as Map<String, dynamic>;
    final ideasCount = counts['ideas'] as int? ?? 0;
    final bucketsCount = counts['buckets'] as int? ?? 0;

    AppLogger.info('ThoughtBundleService', 'Exported bundle with $ideasCount ideas to ${targetFile.path}');

    return ExportResult(
      file: targetFile,
      ideasCount: ideasCount,
      bucketsCount: bucketsCount,
      folderPath: targetDir.path,
      isEncrypted: header['is_encrypted'] as bool? ?? false,
    );
  }

  /// Parses and validates a `.thoughtbundle` file or JSON string.
  /// Decrypts if protected with a passphrase.
  /// Throws clear format exceptions if invalid, with zero partial output on auth failure.
  static Future<UnpackedBundle> unpackBundle({
    required String jsonString,
    String? passphrase,
  }) async {
    Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      throw const FormatException('Invalid file: not a valid JSON document.');
    }

    final header = envelope['header'] as Map<String, dynamic>?;
    if (header == null) {
      throw const FormatException('Invalid .thoughtbundle: missing header.');
    }

    final formatVer = header['format_version'] as int?;
    if (formatVer != formatVersion) {
      throw FormatException('Unsupported bundle format version: $formatVer (expected $formatVersion).');
    }

    final isEncrypted = header['is_encrypted'] as bool? ?? false;
    final storedChecksum = header['sha256'] as String?;
    if (storedChecksum == null || storedChecksum.trim().isEmpty) {
      throw const FormatException('Invalid .thoughtbundle: missing SHA-256 checksum.');
    }

    Map<String, dynamic> dataMap;

    if (isEncrypted) {
      if (passphrase == null || passphrase.trim().isEmpty) {
        throw const FormatException('This file is protected with a passphrase. Please enter the passphrase.');
      }

      final kdf = header['kdf'] as Map<String, dynamic>?;
      final saltStr = (kdf != null ? kdf['salt'] : header['salt']) as String?;
      if (saltStr == null || saltStr.isEmpty) {
        throw const FormatException('Malformed encrypted bundle: missing salt.');
      }

      final encryptedDataStr = envelope['encrypted_data'] as String?;
      if (encryptedDataStr == null || encryptedDataStr.isEmpty) {
        throw const FormatException('Malformed encrypted bundle: missing encrypted payload.');
      }

      final saltBytes = base64Url.decode(saltStr);
      final kdfAlgo = (kdf?['algorithm'] as String? ?? 'argon2id').toLowerCase();

      c.SecretKey derivedSecretKey;
      if (kdfAlgo == 'pbkdf2-hmac-sha256') {
        final iterations = kdf?['iterations'] as int? ?? 600000;
        final pbkdf2 = c.Pbkdf2(
          macAlgorithm: c.Hmac.sha256(),
          iterations: iterations,
          bits: 256,
        );
        derivedSecretKey = await pbkdf2.deriveKey(
          secretKey: c.SecretKey(utf8.encode(passphrase.trim())),
          nonce: saltBytes,
        );
      } else {
        // Default: Argon2id
        final memoryKb = kdf?['memory_kb'] as int? ?? (19 * 1024);
        final iterations = kdf?['iterations'] as int? ?? 2;
        final parallelism = kdf?['parallelism'] as int? ?? 1;
        final hashLength = kdf?['hash_length'] as int? ?? 32;

        final argon2 = c.Argon2id(
          memory: memoryKb,
          iterations: iterations,
          parallelism: parallelism,
          hashLength: hashLength,
        );
        derivedSecretKey = await argon2.deriveKey(
          secretKey: c.SecretKey(utf8.encode(passphrase.trim())),
          nonce: saltBytes,
        );
      }

      // Standard cipher: AES-256-GCM
      final cipherMeta = header['cipher'] as Map<String, dynamic>?;
      final nonceStr = cipherMeta?['nonce'] as String?;
      final macStr = cipherMeta?['mac'] as String?;
      if (nonceStr == null || macStr == null) {
        throw const FormatException('Malformed encrypted bundle: missing cipher nonce or MAC tag.');
      }

      List<int> decryptedBytes;
      try {
        final cipherBytes = base64Url.decode(encryptedDataStr);
        final nonceBytes = base64Url.decode(nonceStr);
        final macBytes = base64Url.decode(macStr);

        final secretBox = c.SecretBox(
          cipherBytes,
          nonce: nonceBytes,
          mac: c.Mac(macBytes),
        );

        final aesGcm = c.AesGcm.with256bits();
        decryptedBytes = await aesGcm.decrypt(secretBox, secretKey: derivedSecretKey);
      } catch (e) {
        throw const FormatException('Incorrect passphrase or corrupted/tampered ciphertext.');
      }

      final decryptedJson = utf8.decode(decryptedBytes);
      dataMap = jsonDecode(decryptedJson) as Map<String, dynamic>;
    } else {
      final rawData = envelope['data'] as Map<String, dynamic>?;
      if (rawData == null) {
        throw const FormatException('Invalid .thoughtbundle: missing data section.');
      }
      dataMap = rawData;
    }

    // Verify SHA-256 checksum on data
    final canonicalJson = canonicalJsonEncode(dataMap);
    final computedChecksum = sha256.convert(utf8.encode(canonicalJson)).toString();
    if (computedChecksum != storedChecksum) {
      throw const FormatException('Checksum mismatch: bundle data is corrupted or tampered.');
    }

    final ideasList = (dataMap['ideas'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final bucketsList = (dataMap['buckets'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return UnpackedBundle(
      header: header,
      ideas: ideasList,
      buckets: bucketsList,
      checksum: storedChecksum,
    );
  }

  /// Maximum allowed bundle file size on disk (50 MB cap).
  static const int maxBundleFileSize = 50 * 1024 * 1024;

  /// Validates bundle structure, field types, and lengths.
  /// Throws FormatException if any untrusted or corrupted data is detected.
  static void validateIncomingBundleData(UnpackedBundle bundle) {
    for (final idea in bundle.ideas) {
      final uuid = idea['uuid'];
      if (uuid is! String || uuid.trim().isEmpty || uuid.length > 128) {
        throw const FormatException('Malformed bundle: idea missing or invalid "uuid".');
      }
      final text = idea['text'];
      if (text is! String || text.length > 1000000) {
        throw const FormatException('Malformed bundle: idea missing or oversized "text".');
      }
      final title = idea['title'];
      if (title != null && (title is! String || title.length > 500)) {
        throw const FormatException('Malformed bundle: idea has invalid "title".');
      }
      final titleSource = idea['title_source'];
      if (titleSource != null && (titleSource is! String || titleSource.length > 50)) {
        throw const FormatException('Malformed bundle: idea has invalid "title_source".');
      }
      final status = idea['status'];
      if (status != 'active' && status != 'done' && status != 'trash') {
        throw const FormatException('Malformed bundle: idea has invalid "status".');
      }
      final createdAt = idea['created_at'];
      if (createdAt is! int && (createdAt is! String || int.tryParse(createdAt) == null)) {
        throw const FormatException('Malformed bundle: idea has invalid "created_at".');
      }
      final updatedAt = idea['updated_at'];
      if (updatedAt != null && updatedAt is! String) {
        throw const FormatException('Malformed bundle: idea has invalid "updated_at".');
      }
    }

    for (final bucket in bundle.buckets) {
      final name = bucket['name'];
      if (name is! String || name.trim().isEmpty || name.length > 100) {
        throw const FormatException('Malformed bundle: bucket missing or invalid "name".');
      }
      final uuid = bucket['uuid'];
      if (uuid != null && (uuid is! String || uuid.length > 128)) {
        throw const FormatException('Malformed bundle: bucket has invalid "uuid".');
      }
      final icon = bucket['icon'];
      if (icon != null && (icon is! String || icon.length > 50)) {
        throw const FormatException('Malformed bundle: bucket has invalid "icon".');
      }
    }
  }

  /// Evaluates an untrusted .thoughtbundle file and prepares an exact preview breakdown
  /// without modifying any database tables.
  Future<ImportAnalysis> previewImport({
    required File file,
    String? passphrase,
    Database? db,
  }) async {
    if (!await file.exists()) {
      throw const FormatException('Selected file does not exist.');
    }
    int fileSize;
    try {
      fileSize = await file.length();
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        fileSize = await file.length();
      } catch (e) {
        throw FormatException('Unable to read bundle file: $e');
      }
    }
    if (fileSize > maxBundleFileSize) {
      throw const FormatException('File too large (exceeds 50 MB limit).');
    }

    final jsonContent = await file.readAsString();
    final bundle = await unpackBundle(jsonString: jsonContent, passphrase: passphrase);
    validateIncomingBundleData(bundle);

    final database = db ?? await DatabaseHelper.instance.database;

    // Read current state within a read transaction to ensure snapshot consistency
    return await database.transaction<ImportAnalysis>((txn) async {
      final existingThoughtRows = await txn.query('thoughts');
      final existingBucketRows = await txn.query('buckets');

      final Map<String, Map<String, dynamic>> existingThoughtsByUuid = {};
      for (final r in existingThoughtRows) {
        final id = r['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          existingThoughtsByUuid[id] = r;
        }
      }

      final Map<String, Map<String, dynamic>> existingBucketsByUuid = {};
      final Map<String, Map<String, dynamic>> existingBucketsByName = {};
      for (final b in existingBucketRows) {
        final id = b['id']?.toString() ?? '';
        final name = (b['name']?.toString() ?? '').toLowerCase().trim();
        if (id.isNotEmpty) existingBucketsByUuid[id] = b;
        if (name.isNotEmpty) existingBucketsByName[name] = b;
      }

      // Analyze buckets
      final List<Map<String, dynamic>> bucketsToAdd = [];
      final List<Map<String, dynamic>> bucketsMatchedByName = [];

      for (final incBucket in bundle.buckets) {
        final bUuid = incBucket['uuid']?.toString() ?? '';
        final bName = (incBucket['name']?.toString() ?? '').toLowerCase().trim();

        if (bUuid.isNotEmpty && existingBucketsByUuid.containsKey(bUuid)) {
          // Matched by uuid
          continue;
        } else if (bName.isNotEmpty && existingBucketsByName.containsKey(bName)) {
          bucketsMatchedByName.add(incBucket);
        } else {
          bucketsToAdd.add(incBucket);
        }
      }

      // Analyze ideas
      final List<Map<String, dynamic>> newIdeas = [];
      final List<Map<String, dynamic>> newerEdits = [];
      final List<Map<String, dynamic>> upToDateIdeas = [];
      final List<Map<String, dynamic>> conflicts = [];
      final List<Map<String, dynamic>> statusChanges = [];

      for (final incIdea in bundle.ideas) {
        final uuid = incIdea['uuid']?.toString() ?? '';
        final existing = existingThoughtsByUuid[uuid];

        if (existing == null) {
          newIdeas.add(incIdea);
          continue;
        }

        final incText = incIdea['text']?.toString() ?? '';
        final exText = existing['content']?.toString() ?? '';

        final incUpdatedAtStr = incIdea['updated_at']?.toString();
        final exUpdatedAtStr = existing['updated_at']?.toString();

        DateTime? incUpdatedAt;
        DateTime? exUpdatedAt;
        if (incUpdatedAtStr != null && incUpdatedAtStr.trim().isNotEmpty) {
          incUpdatedAt = DateTime.tryParse(incUpdatedAtStr);
        }
        if (exUpdatedAtStr != null && exUpdatedAtStr.trim().isNotEmpty) {
          exUpdatedAt = DateTime.tryParse(exUpdatedAtStr);
        }

        // Rule 3: "If the incoming idea has a newer updated_at, update it.
        // If missing updated_at or equal timestamps with different text, create a "Conflict copy: <title>" in Unsorted."
        if (incUpdatedAt == null || exUpdatedAt == null) {
          if (incText != exText) {
            conflicts.add(incIdea);
          } else {
            upToDateIdeas.add(incIdea);
          }
        } else if (incUpdatedAt.isAtSameMomentAs(exUpdatedAt)) {
          if (incText != exText) {
            conflicts.add(incIdea);
          } else {
            upToDateIdeas.add(incIdea);
          }
        } else if (incUpdatedAt.isAfter(exUpdatedAt)) {
          newerEdits.add(incIdea);
          final incStatus = incIdea['status']?.toString().toLowerCase() ?? 'active';
          final exDone = (existing['done'] as int? ?? 0) == 1;
          final exTrashed = (existing['trashed'] as int? ?? 0) == 1;
          final exStatus = exTrashed ? 'trash' : (exDone ? 'done' : 'active');
          if (incStatus != exStatus && (incStatus == 'done' || incStatus == 'trash')) {
            statusChanges.add(incIdea);
          }
        } else {
          upToDateIdeas.add(incIdea);
        }
      }

      return ImportAnalysis(
        bundle: bundle,
        newIdeas: newIdeas,
        newerEdits: newerEdits,
        upToDateIdeas: upToDateIdeas,
        conflicts: conflicts,
        statusChanges: statusChanges,
        bucketsToAdd: bucketsToAdd,
        bucketsMatchedByName: bucketsMatchedByName,
      );
    });
  }

  /// Applies import changes in ONE single database transaction with automatic rollback.
  /// Takes an automatic verified backup beforehand.
  Future<ImportApplyResult> applyImport({
    required ImportAnalysis analysis,
    Database? db,
    String? customBackupDir,
  }) async {
    final database = db ?? await DatabaseHelper.instance.database;

    // 1. Automatic verified backup before touching any live data
    final backupFileName = 'thought_backup_pre_import_${DateTime.now().millisecondsSinceEpoch}.db';
    final backupMetadata = await BackupService.instance.createBackup(
      db: db,
      customFileName: backupFileName,
      customDirectoryPath: customBackupDir,
    );

    // Verify backup integrity
    final checkDb = await openDatabase(backupMetadata.file.path, readOnly: true);
    final checkRes = await checkDb.rawQuery('PRAGMA integrity_check');
    final isOk = checkRes.isNotEmpty && checkRes.first.values.first == 'ok';
    await checkDb.close();
    if (!isOk) {
      throw Exception('Automatic pre-import backup failed integrity check. Import aborted.');
    }

    // Save pre-import backup metadata for "Undo this import" (retained for 7 days)
    try {
      final box = Hive.isBoxOpen('app_settings')
          ? Hive.box('app_settings')
          : await Hive.openBox('app_settings');
      await box.put('last_import_backup', {
        'path': backupMetadata.file.path,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'ideaCount': backupMetadata.ideaCount,
      });
    } catch (_) {}

    int insertedCount = 0;
    int updatedCount = 0;
    int conflictCount = 0;
    int addedBucketsCount = 0;

    // 2. Apply in ONE single database transaction (atomic rollback on error)
    await database.transaction((txn) async {
      // Step A: Insert buckets to add
      for (final b in analysis.bucketsToAdd) {
        final bName = b['name']?.toString() ?? '';
        final bUuid = b['uuid']?.toString() ?? '';
        final bIcon = b['icon']?.toString() ?? 'folder';
        final bCreatedAt = b['created_at'] is int
            ? b['created_at'] as int
            : (int.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch);

        await txn.insert('buckets', {
          'name': bName,
          'id': bUuid.isNotEmpty ? bUuid : 'b-${DateTime.now().millisecondsSinceEpoch}',
          'icon': bIcon,
          'created_at': bCreatedAt,
          'revision': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        addedBucketsCount++;
      }

      // Step B: Insert new ideas
      for (final idea in analysis.newIdeas) {
        final status = idea['status']?.toString().toLowerCase() ?? 'active';
        final isDone = status == 'done' ? 1 : 0;
        final isTrashed = status == 'trash' ? 1 : 0;
        final createdAt = idea['created_at'] is int
            ? idea['created_at'] as int
            : (int.tryParse(idea['created_at']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch);

        await txn.insert('thoughts', {
          'id': idea['uuid']?.toString() ?? '',
          'thought_id': idea['uuid']?.toString() ?? '',
          'content': idea['text']?.toString() ?? '',
          'type': 'text',
          'status': status,
          'done': isDone,
          'trashed': isTrashed,
          'title': idea['title']?.toString() ?? '',
          'title_source': idea['title_source']?.toString() ?? 'auto',
          'bucket': idea['bucket_name']?.toString() ?? '',
          'bucket_id': idea['bucket_uuid']?.toString() ?? '',
          'when_val': idea['when']?.toString() ?? 'Soon',
          'time_val': idea['time']?.toString() ?? 'Medium',
          'created_at': createdAt,
          'last_viewed_at': createdAt,
          'stale_score': 0,
          'updated_at': idea['updated_at']?.toString(),
          'skipped_at': idea['skipped_at'] is int ? idea['skipped_at'] as int : null,
          'skip_count': idea['skip_count'] as int? ?? 0,
        });
        insertedCount++;
      }

      // Step C: Update newer edits
      for (final idea in analysis.newerEdits) {
        final uuid = idea['uuid']?.toString() ?? '';
        final status = idea['status']?.toString().toLowerCase() ?? 'active';
        final isDone = status == 'done' ? 1 : 0;
        final isTrashed = status == 'trash' ? 1 : 0;

        await txn.update(
          'thoughts',
          {
            'content': idea['text']?.toString() ?? '',
            'title': idea['title']?.toString() ?? '',
            'title_source': idea['title_source']?.toString() ?? 'auto',
            'status': status,
            'done': isDone,
            'trashed': isTrashed,
            'bucket': idea['bucket_name']?.toString() ?? '',
            'bucket_id': idea['bucket_uuid']?.toString() ?? '',
            'when_val': idea['when']?.toString() ?? 'Soon',
            'time_val': idea['time']?.toString() ?? 'Medium',
            'updated_at': idea['updated_at']?.toString(),
            'skipped_at': idea['skipped_at'] is int ? idea['skipped_at'] as int : null,
            'skip_count': idea['skip_count'] as int? ?? 0,
          },
          where: 'id = ?',
          whereArgs: [uuid],
        );
        updatedCount++;
      }

      // Step D: Conflicts -> create "Conflict copy: <title>" in Unsorted
      final rng = Random();
      for (final idea in analysis.conflicts) {
        final originalTitle = idea['title']?.toString() ?? 'Untitled';
        final conflictTitle = 'Conflict copy: $originalTitle';
        final conflictUuid = 't-conflict-${DateTime.now().millisecondsSinceEpoch}-${rng.nextInt(999999)}';
        final nowMs = DateTime.now().millisecondsSinceEpoch;

        await txn.insert('thoughts', {
          'id': conflictUuid,
          'thought_id': conflictUuid,
          'content': idea['text']?.toString() ?? '',
          'type': 'text',
          'status': 'active',
          'done': 0,
          'trashed': 0,
          'title': conflictTitle,
          'title_source': 'manual',
          'bucket': null, // Unsorted
          'bucket_id': null,
          'when_val': idea['when']?.toString() ?? 'Soon',
          'time_val': idea['time']?.toString() ?? 'Medium',
          'created_at': nowMs,
          'last_viewed_at': nowMs,
          'stale_score': 0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'skipped_at': null,
          'skip_count': 0,
        });
        conflictCount++;
      }
    });

    AppLogger.info(
      'ThoughtBundleService',
      'Import applied: $insertedCount new, $updatedCount updated, $conflictCount conflicts, $addedBucketsCount buckets.',
    );

    return ImportApplyResult(
      insertedIdeasCount: insertedCount,
      updatedIdeasCount: updatedCount,
      conflictCopiesCount: conflictCount,
      addedBucketsCount: addedBucketsCount,
      backupFilePath: backupMetadata.file.path,
    );
  }

  /// Checks if an undo backup exists from within the last 7 days.
  Future<Map<String, dynamic>?> getLastImportBackupInfo() async {
    try {
      final box = Hive.isBoxOpen('app_settings')
          ? Hive.box('app_settings')
          : await Hive.openBox('app_settings');
      final raw = box.get('last_import_backup');
      if (raw is Map) {
        final timestamp = raw['timestamp'] as int? ?? 0;
        final age = DateTime.now().millisecondsSinceEpoch - timestamp;
        const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
        if (age <= sevenDaysMs) {
          final path = raw['path'] as String? ?? '';
          if (File(path).existsSync()) {
            return Map<String, dynamic>.from(raw);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Restores the pre-import backup to undo the last import.
  Future<bool> undoLastImport({Database? db, String? liveDbPath, String? customBackupDir}) async {
    final info = await getLastImportBackupInfo();
    if (info == null) {
      throw Exception('No valid pre-import backup found from the last 7 days.');
    }
    final backupFile = File(info['path'] as String);
    final prep = await BackupService.instance.prepareRestore(
      backupFile,
      liveDb: db,
      liveDbPath: liveDbPath,
      customDirectoryPath: customBackupDir,
    );
    if (db != null && db.isOpen) {
      await db.close();
    }
    await BackupService.instance.completeRestore(prep, liveDbPath: liveDbPath);

    try {
      final box = Hive.isBoxOpen('app_settings')
          ? Hive.box('app_settings')
          : await Hive.openBox('app_settings');
      await box.delete('last_import_backup');
    } catch (_) {}
    return true;
  }
}

class ImportAnalysis {
  final UnpackedBundle bundle;
  final List<Map<String, dynamic>> newIdeas;
  final List<Map<String, dynamic>> newerEdits;
  final List<Map<String, dynamic>> upToDateIdeas;
  final List<Map<String, dynamic>> conflicts;
  final List<Map<String, dynamic>> statusChanges;
  final List<Map<String, dynamic>> bucketsToAdd;
  final List<Map<String, dynamic>> bucketsMatchedByName;

  const ImportAnalysis({
    required this.bundle,
    required this.newIdeas,
    required this.newerEdits,
    required this.upToDateIdeas,
    required this.conflicts,
    required this.statusChanges,
    required this.bucketsToAdd,
    required this.bucketsMatchedByName,
  });

  int get newIdeasCount => newIdeas.length;
  int get newerEditsCount => newerEdits.length;
  int get upToDateCount => upToDateIdeas.length;
  int get conflictsCount => conflicts.length;
  int get statusChangesCount => statusChanges.length;
  int get bucketsToAddCount => bucketsToAdd.length;
  int get bucketsMatchedByNameCount => bucketsMatchedByName.length;
  int get totalIncomingIdeas => bundle.ideas.length;
  int get totalIncomingBuckets => bundle.buckets.length;
}

class ImportApplyResult {
  final int insertedIdeasCount;
  final int updatedIdeasCount;
  final int conflictCopiesCount;
  final int addedBucketsCount;
  final String backupFilePath;

  const ImportApplyResult({
    required this.insertedIdeasCount,
    required this.updatedIdeasCount,
    required this.conflictCopiesCount,
    required this.addedBucketsCount,
    required this.backupFilePath,
  });
}

class ExportResult {
  final File file;
  final int ideasCount;
  final int bucketsCount;
  final String folderPath;
  final bool isEncrypted;

  const ExportResult({
    required this.file,
    required this.ideasCount,
    required this.bucketsCount,
    required this.folderPath,
    required this.isEncrypted,
  });

  String get summaryText => 'Saved $ideasCount ideas and $bucketsCount buckets to $folderPath';
}

class UnpackedBundle {
  final Map<String, dynamic> header;
  final List<Map<String, dynamic>> ideas;
  final List<Map<String, dynamic>> buckets;
  final String checksum;

  const UnpackedBundle({
    required this.header,
    required this.ideas,
    required this.buckets,
    required this.checksum,
  });
}
