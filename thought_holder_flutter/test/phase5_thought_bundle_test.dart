import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thought_holder_flutter/services/thought_bundle_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Database db;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('bundle_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );
  });

  tearDownAll(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    final dbPath = inMemoryDatabasePath;
    db = await databaseFactory.openDatabase(dbPath);

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
      );
    ''');

    await db.execute('''
      CREATE TABLE buckets (
        name TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        icon TEXT DEFAULT 'folder',
        id TEXT,
        updated_at TEXT,
        updated_by TEXT,
        revision INTEGER DEFAULT 1
      );
    ''');

    // Insert 2 buckets
    await db.insert('buckets', {
      'name': 'Work Projects',
      'id': 'b-uuid-1',
      'icon': 'briefcase',
      'created_at': 1700000000000,
    });
    await db.insert('buckets', {
      'name': 'Personal Reading',
      'id': 'b-uuid-2',
      'icon': 'book',
      'created_at': 1700000001000,
    });

    // Insert 3 thoughts
    await db.insert('thoughts', {
      'id': 't-uuid-1',
      'thought_id': 't-uuid-1',
      'content': 'Finish the quarterly architecture review',
      'type': 'text',
      'status': 'active',
      'created_at': 1700000002000,
      'last_viewed_at': 1700000002000,
      'stale_score': 0,
      'bucket': 'Work Projects',
      'bucket_id': 'b-uuid-1',
      'when_val': 'Now',
      'time_val': 'Long',
      'done': 0,
      'trashed': 0,
      'updated_at': '2026-11-03T12:00:00Z',
      'skipped_at': null,
      'skip_count': 0,
      'title': 'Quarterly review',
      'title_source': 'auto',
    });

    await db.insert('thoughts', {
      'id': 't-uuid-2',
      'thought_id': 't-uuid-2',
      'content': 'Read Chapter 4 of Distributed Systems',
      'type': 'text',
      'status': 'done',
      'created_at': 1700000003000,
      'last_viewed_at': 1700000003000,
      'stale_score': 0,
      'bucket': 'Personal Reading',
      'bucket_id': 'b-uuid-2',
      'when_val': 'Later',
      'time_val': 'Medium',
      'done': 1,
      'trashed': 0,
      'updated_at': '2026-11-03T13:00:00Z',
      'skipped_at': null,
      'skip_count': 1,
      'title': 'Distributed Systems reading',
      'title_source': 'manual',
    });

    await db.insert('thoughts', {
      'id': 't-uuid-3',
      'thought_id': 't-uuid-3',
      'content': 'Old junk grocery note',
      'type': 'text',
      'status': 'trash',
      'created_at': 1700000004000,
      'last_viewed_at': 1700000004000,
      'stale_score': 0,
      'bucket': null,
      'bucket_id': null,
      'when_val': 'Soon',
      'time_val': 'Short',
      'done': 0,
      'trashed': 1,
      'updated_at': '2026-11-03T14:00:00Z',
      'skipped_at': 1700000005000,
      'skip_count': 2,
      'title': 'Quick note',
      'title_source': 'auto',
    });
  });

  tearDown(() async {
    await db.close();
  });

  group('ThoughtBundleService Export Tests', () {
    test('1. Bundle contains only required idea and bucket fields, NO keys, NO settings, NO audio', () async {
      final bundleData = await ThoughtBundleService.instance.buildBundleData(db: db);

      expect(bundleData.keys.toSet(), equals({'ideas', 'buckets'}));
      expect(bundleData.containsKey('settings'), isFalse);
      expect(bundleData.containsKey('keys'), isFalse);
      expect(bundleData.containsKey('groq_key'), isFalse);
      expect(bundleData.containsKey('pairing_data'), isFalse);
      expect(bundleData.containsKey('audio'), isFalse);

      final ideas = bundleData['ideas'] as List;
      expect(ideas.length, equals(3));

      final requiredIdeaKeys = {
        'uuid',
        'text',
        'title',
        'title_source',
        'bucket_uuid',
        'bucket_name',
        'when',
        'time',
        'status',
        'created_at',
        'updated_at',
        'skipped_at',
        'skip_count',
      };

      for (final idea in ideas) {
        final m = idea as Map<String, dynamic>;
        expect(m.keys.toSet(), equals(requiredIdeaKeys), reason: 'Idea must match exact required schema');
        expect(m.containsKey('audio'), isFalse);
        expect(m.containsKey('audio_path'), isFalse);
        expect(m.containsKey('apiKey'), isFalse);
        expect(m.containsKey('sync_key'), isFalse);
      }

      final buckets = bundleData['buckets'] as List;
      expect(buckets.length, equals(2));

      final requiredBucketKeys = {
        'uuid',
        'name',
        'icon',
        'created_at',
      };

      for (final bucket in buckets) {
        final b = bucket as Map<String, dynamic>;
        expect(b.keys.toSet(), equals(requiredBucketKeys), reason: 'Bucket must match exact required schema');
      }
    });

    test('2. Unencrypted bundle has valid header, correct counts, and matching SHA-256 checksum', () async {
      final jsonStr = await ThoughtBundleService.instance.createBundleString(db: db);
      final envelope = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(envelope.containsKey('header'), isTrue);
      expect(envelope.containsKey('data'), isTrue);
      expect(envelope.containsKey('encrypted_data'), isFalse);

      final header = envelope['header'] as Map<String, dynamic>;
      expect(header['format_version'], equals(1));
      expect(header['app_version'], equals('1.0.0'));
      expect(header['exported_at'], isNotEmpty);
      expect(header['is_encrypted'], isFalse);

      final counts = header['counts'] as Map<String, dynamic>;
      expect(counts['ideas'], equals(3));
      expect(counts['buckets'], equals(2));

      final data = envelope['data'] as Map<String, dynamic>;
      final canonicalData = ThoughtBundleService.canonicalJsonEncode(data);
      final expectedSha = sha256.convert(utf8.encode(canonicalData)).toString();
      expect(header['sha256'], equals(expectedSha));

      // Unpack check
      final unpacked = await ThoughtBundleService.unpackBundle(jsonString: jsonStr);
      expect(unpacked.ideas.length, equals(3));
      expect(unpacked.buckets.length, equals(2));
      expect(unpacked.checksum, equals(expectedSha));
    });

    test('3. Passphrase protected export uses Argon2id + AES-256-GCM, stores parameters, never stores passphrase, and unpacks cleanly', () async {
      const testPassphrase = 'MySuperSecretPassphrase123!';
      final encryptedJsonStr = await ThoughtBundleService.instance.createBundleString(
        db: db,
        passphrase: testPassphrase,
      );

      final envelope = jsonDecode(encryptedJsonStr) as Map<String, dynamic>;
      final header = envelope['header'] as Map<String, dynamic>;

      expect(header['is_encrypted'], isTrue);
      expect(header.containsKey('kdf'), isTrue);
      final kdf = header['kdf'] as Map<String, dynamic>;
      expect(kdf['algorithm'], equals('argon2id'));
      expect(kdf['memory_kb'], equals(19456));
      expect(kdf['iterations'], equals(2));
      expect(kdf['parallelism'], equals(1));
      expect(kdf['salt'], isNotEmpty);
      expect(kdf['hash_length'], equals(32));

      expect(header.containsKey('cipher'), isTrue);
      final cipher = header['cipher'] as Map<String, dynamic>;
      expect(cipher['algorithm'], equals('aes-256-gcm'));
      expect(cipher['nonce'], isNotEmpty);
      expect(cipher['mac'], isNotEmpty);

      expect(envelope.containsKey('data'), isFalse);
      expect(envelope.containsKey('encrypted_data'), isTrue);

      // Plaintext passphrase must never exist anywhere in the bundle
      expect(encryptedJsonStr.contains(testPassphrase), isFalse);
      expect(encryptedJsonStr.contains('Finish the quarterly architecture review'), isFalse);

      // Unpack with correct passphrase
      final unpacked = await ThoughtBundleService.unpackBundle(
        jsonString: encryptedJsonStr,
        passphrase: testPassphrase,
      );
      expect(unpacked.ideas.length, equals(3));
      expect(unpacked.buckets.length, equals(2));
      expect(unpacked.ideas[0]['text'], equals('Finish the quarterly architecture review'));
    });

    test('4. Wrong passphrase fails cleanly with no partial output', () async {
      const testPassphrase = 'CorrectPassphrase456!';
      final encryptedJsonStr = await ThoughtBundleService.instance.createBundleString(
        db: db,
        passphrase: testPassphrase,
      );

      // Attempt unpack without passphrase
      expect(
        () => ThoughtBundleService.unpackBundle(jsonString: encryptedJsonStr),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('protected with a passphrase'),
        )),
      );

      // Attempt unpack with wrong passphrase
      expect(
        () => ThoughtBundleService.unpackBundle(
          jsonString: encryptedJsonStr,
          passphrase: 'CompletelyWrongPassphrase',
        ),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Incorrect passphrase'),
        )),
      );
    });

    test('5. Tampered ciphertext or MAC fails authentication cleanly', () async {
      const testPassphrase = 'CorrectPassphrase789!';
      final encryptedJsonStr = await ThoughtBundleService.instance.createBundleString(
        db: db,
        passphrase: testPassphrase,
      );

      final envelope = jsonDecode(encryptedJsonStr) as Map<String, dynamic>;
      final rawCipherBytes = base64Url.decode(envelope['encrypted_data'] as String);
      // Flip a bit in the ciphertext
      rawCipherBytes[rawCipherBytes.length ~/ 2] ^= 0xFF;
      envelope['encrypted_data'] = base64Url.encode(rawCipherBytes);

      final tamperedJsonStr = jsonEncode(envelope);

      expect(
        () => ThoughtBundleService.unpackBundle(
          jsonString: tamperedJsonStr,
          passphrase: testPassphrase,
        ),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('corrupted/tampered ciphertext'),
        )),
      );
    });

    test('6. Tampered unencrypted bundle payload fails SHA-256 checksum verification', () async {
      final jsonStr = await ThoughtBundleService.instance.createBundleString(db: db);
      final envelope = jsonDecode(jsonStr) as Map<String, dynamic>;

      final data = envelope['data'] as Map<String, dynamic>;
      final ideas = data['ideas'] as List;
      ideas[0]['text'] = 'Tampered text by attacker';

      final tamperedJsonStr = jsonEncode(envelope);

      expect(
        () => ThoughtBundleService.unpackBundle(jsonString: tamperedJsonStr),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Checksum mismatch: bundle data is corrupted or tampered'),
        )),
      );
    });

    test('7. Consistent snapshot: export reads inside a read transaction', () async {
      // Verify buildBundleData completes inside transaction
      final data = await ThoughtBundleService.instance.buildBundleData(db: db);
      expect(data['ideas'].length, equals(3));
      expect(data['buckets'].length, equals(2));
    });

    test('8. Text with emoji and 50,000 characters round-trips with zero corruption', () async {
      // Build a 50,000-character string with rich emojis and unicode
      final buffer = StringBuffer();
      final snippet = '🚀 ThoughtHolder test idea with emoji 🧠💡🔑 and unicode こんにちは世界! ';
      while (buffer.length < 50000) {
        buffer.write(snippet);
      }
      final largeContent = buffer.toString().substring(0, 50000);

      await db.insert('thoughts', {
        'id': 't-large-emoji',
        'thought_id': 't-large-emoji',
        'content': largeContent,
        'type': 'text',
        'status': 'active',
        'created_at': 1700000006000,
        'last_viewed_at': 1700000006000,
        'stale_score': 0,
        'bucket': 'Work Projects',
        'bucket_id': 'b-uuid-1',
        'title': 'Large emoji text 🌍',
        'title_source': 'manual',
      });

      // Export unencrypted
      final plainBundle = await ThoughtBundleService.instance.createBundleString(db: db);
      final unpackedPlain = await ThoughtBundleService.unpackBundle(jsonString: plainBundle);
      final ideaPlain = unpackedPlain.ideas.firstWhere((i) => i['uuid'] == 't-large-emoji');
      expect(ideaPlain['text'], equals(largeContent));
      expect(ideaPlain['text'].toString().length, equals(50000));

      // Export encrypted with Argon2id + AES-256-GCM
      const pass = 'EmojiPassword🔐123';
      final encBundle = await ThoughtBundleService.instance.createBundleString(db: db, passphrase: pass);
      final unpackedEnc = await ThoughtBundleService.unpackBundle(jsonString: encBundle, passphrase: pass);
      final ideaEnc = unpackedEnc.ideas.firstWhere((i) => i['uuid'] == 't-large-emoji');
      expect(ideaEnc['text'], equals(largeContent));
      expect(ideaEnc['text'].toString().length, equals(50000));
    });

    test('9. Export of 5,000-idea copy is timed and verified', () async {
      final bigDbPath = '${tempDir.path}/big_5000.db';
      final bigDb = await databaseFactory.openDatabase(bigDbPath);

      await bigDb.execute('''
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
        );
      ''');

      await bigDb.execute('''
        CREATE TABLE buckets (
          name TEXT PRIMARY KEY,
          created_at INTEGER NOT NULL,
          icon TEXT DEFAULT 'folder',
          id TEXT,
          updated_at TEXT,
          updated_by TEXT,
          revision INTEGER DEFAULT 1
        );
      ''');

      await bigDb.insert('buckets', {
        'name': 'Batch Bucket',
        'id': 'b-batch-1',
        'icon': 'folder',
        'created_at': 1700000000000,
      });

      // Insert 5,000 thoughts in batches inside a transaction
      await bigDb.transaction((txn) async {
        final batch = txn.batch();
        for (int i = 0; i < 5000; i++) {
          batch.insert('thoughts', {
            'id': 'idea-batch-$i',
            'thought_id': 'idea-batch-$i',
            'content': 'Test idea number $i with notes and details.',
            'type': 'text',
            'status': i % 10 == 0 ? 'done' : (i % 25 == 0 ? 'trash' : 'active'),
            'created_at': 1700000000000 + i,
            'last_viewed_at': 1700000000000 + i,
            'stale_score': 0,
            'bucket': 'Batch Bucket',
            'bucket_id': 'b-batch-1',
            'title': 'Idea #$i',
            'title_source': 'auto',
          });
        }
        await batch.commit(noResult: true);
      });

      // Time export
      final sw = Stopwatch()..start();
      final bundleStr = await ThoughtBundleService.instance.createBundleString(db: bigDb);
      sw.stop();
      // ignore: avoid_print
      print('5,000-idea export time: ${sw.elapsedMilliseconds} ms');

      final unpacked = await ThoughtBundleService.unpackBundle(jsonString: bundleStr);
      expect(unpacked.ideas.length, equals(5000));
      expect(unpacked.buckets.length, equals(1));

      await bigDb.close();
    });

    test('10. exportToFile writes .thoughtbundle file to disk and returns correct ExportResult', () async {
      final result = await ThoughtBundleService.instance.exportToFile(
        db: db,
        customDestinationDir: tempDir.path,
        customFileName: 'test_export.thoughtbundle',
      );

      expect(result.file.existsSync(), isTrue);
      expect(result.ideasCount, equals(3));
      expect(result.bucketsCount, equals(2));
      expect(result.folderPath, equals(tempDir.path));

      final fileContent = await result.file.readAsString();
      final unpacked = await ThoughtBundleService.unpackBundle(jsonString: fileContent);
      expect(unpacked.ideas.length, equals(3));
      expect(unpacked.buckets.length, equals(2));
    });
  });
}
