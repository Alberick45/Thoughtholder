import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thought_holder_flutter/sync_identity.dart';
import 'package:thought_holder_flutter/ble_crypto.dart';
import 'package:thought_holder_flutter/ble_merge_engine.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('UPDATE 7 - Stable Identity & HLC', () {
    test('SyncIdentity generates valid v4 UUIDs', () {
      final uuid1 = SyncIdentity.newUuid();
      final uuid2 = SyncIdentity.newUuid();

      expect(uuid1, isNot(equals(uuid2)));
      final uuidRegex = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(uuidRegex.hasMatch(uuid1), isTrue, reason: 'UUID1 $uuid1 must match RFC4122 v4 pattern');
      expect(uuidRegex.hasMatch(uuid2), isTrue, reason: 'UUID2 $uuid2 must match RFC4122 v4 pattern');
    });

    test('Hlc formatting, parsing and roundtrip', () {
      final hlc = Hlc(millis: 1730376000000, counter: 5, deviceId: 'dev_abc123');
      final serialized = hlc.toString();
      expect(serialized, '1730376000000:5:dev_abc123');

      final parsed = Hlc.parse(serialized);
      expect(parsed.millis, 1730376000000);
      expect(parsed.counter, 5);
      expect(parsed.deviceId, 'dev_abc123');
    });

    test('Hlc comparison ordering and deterministic tie-breaking', () {
      final hlcOlder = Hlc(millis: 1000, counter: 0, deviceId: 'dev_a');
      final hlcNewer = Hlc(millis: 2000, counter: 0, deviceId: 'dev_a');
      expect(hlcOlder.compareTo(hlcNewer), lessThan(0));
      expect(hlcNewer.compareTo(hlcOlder), greaterThan(0));

      final hlcSameTimeC0 = Hlc(millis: 1000, counter: 0, deviceId: 'dev_a');
      final hlcSameTimeC1 = Hlc(millis: 1000, counter: 1, deviceId: 'dev_a');
      expect(hlcSameTimeC0.compareTo(hlcSameTimeC1), lessThan(0));

      // Same time & counter: deviceId breaks tie
      final hlcDevA = Hlc(millis: 1000, counter: 0, deviceId: 'dev_a');
      final hlcDevB = Hlc(millis: 1000, counter: 0, deviceId: 'dev_b');
      expect(hlcDevA.compareTo(hlcDevB), lessThan(0));
      expect(hlcDevB.compareTo(hlcDevA), greaterThan(0));
    });

    test('Hlc updates causality monotonically on receiving remote timestamp', () {
      final localHlc = Hlc(millis: 5000, counter: 2, deviceId: 'local_device');
      final remoteHlc = Hlc(millis: 8000, counter: 1, deviceId: 'remote_device');

      final updated = localHlc.update(remoteHlc);
      expect(updated.millis, greaterThanOrEqualTo(8000));
      expect(updated.deviceId, 'local_device');
      expect(updated.compareTo(remoteHlc), greaterThan(0));
    });
  });

  group('UPDATE 7 - Pairing & Security (BleCrypto)', () {
    test('Pairing code is 6-digit numeric string', () {
      for (int i = 0; i < 20; i++) {
        final code = BleCrypto.generatePairingCode();
        expect(code.length, 6);
        expect(int.tryParse(code), isNotNull);
        expect(int.parse(code), inInclusiveRange(100000, 999999));
      }
    });

    test('BleCrypto deriveKey produces 32-byte key from code & salt', () {
      final key1 = BleCrypto.deriveKey('123456', 'salt_phone_laptop');
      final key2 = BleCrypto.deriveKey('123456', 'salt_phone_laptop');
      final keyDifferent = BleCrypto.deriveKey('654321', 'salt_phone_laptop');

      expect(base64Url.decode(key1).length, 32);
      expect(key1, equals(key2));
      expect(key1, isNot(equals(keyDifferent)));
    });

    test('BleCrypto encrypts with gzip compression and decrypts successfully', () {
      final key = BleCrypto.deriveKey('789101', 'sync_session_salt');
      final originalMap = {
        'action': 'sync_payload',
        'ideas': [
          {'id': 'uuid-1', 'content': 'Test idea content', 'status': 'unsorted'},
          {'id': 'uuid-2', 'content': 'Second test idea', 'status': 'sorted'},
        ],
        'buckets': [
          {'id': 'b-uuid-1', 'name': 'Work'},
        ],
      };
      final jsonBytes = utf8.encode(jsonEncode(originalMap));

      final encrypted = BleCrypto.encryptData(jsonBytes, key);
      expect(encrypted, isNotEmpty);

      final decryptedBytes = BleCrypto.decryptData(encrypted, key);
      final decryptedMap = jsonDecode(utf8.decode(decryptedBytes)) as Map<String, dynamic>;

      expect(decryptedMap['action'], 'sync_payload');
      expect((decryptedMap['ideas'] as List).length, 2);
      expect(decryptedMap['ideas'][0]['content'], 'Test idea content');
    });

    test('BleCrypto detects tampering and fails decryption', () {
      final key = BleCrypto.deriveKey('789101', 'sync_session_salt');
      final jsonBytes = utf8.encode('{"hello":"world"}');
      final encrypted = BleCrypto.encryptData(jsonBytes, key);

      // Tamper with the last byte
      final tampered = List<int>.from(encrypted);
      tampered[tampered.length - 1] ^= 0xFF;

      expect(() => BleCrypto.decryptData(tampered, key), throwsException);
    });
  });

  group('UPDATE 7 - Merge Engine (Field Winning, Conflicts, Deduplication, Tombstones)', () {
    test('Field-level winning: newer Hlc wins', () {
      final ideaALocal = {
        'id': 'idea-uuid-1',
        'thought_id': 'LOG-001',
        'content': 'Updated on phone',
        'bucket': 'Work',
        'bucket_id': 'bucket-uuid-1',
        'done': 0,
        'trashed': 0,
        'updated_at': '2000:0:device_phone',
        'updated_by': 'device_phone',
        'revision': 2,
        'created_at': 1000,
      };

      final ideaARemote = {
        'id': 'idea-uuid-1',
        'thought_id': 'LOG-001',
        'content': 'Older edit on laptop',
        'bucket': 'Work',
        'bucket_id': 'bucket-uuid-1',
        'done': 0,
        'trashed': 0,
        'updated_at': '1500:0:device_laptop',
        'updated_by': 'device_laptop',
        'revision': 1,
        'created_at': 1000,
      };

      final result = BleMergeEngine.mergeDatasets(
        localThoughts: [ideaALocal],
        remoteThoughts: [ideaARemote],
        localBuckets: [],
        remoteBuckets: [],
        localTombstones: [],
        remoteTombstones: [],
        currentDeviceId: 'device_phone',
      );

      expect(result.mergedThoughts.length, 1);
      expect(result.mergedThoughts.first['content'], 'Updated on phone');
      expect(result.mergedThoughts.first['updated_by'], 'device_phone');
    });

    test('Concurrent text conflict creates Conflict copy in Unsorted', () {
      final ideaLocal = {
        'id': 'idea-uuid-conflict',
        'thought_id': 'LOG-005',
        'content': 'Phone version of grocery list: Apples, Bananas',
        'bucket': 'Groceries',
        'bucket_id': 'b-uuid-groc',
        'done': 0,
        'trashed': 0,
        'updated_at': '3000:0:device_b', // Higher HLC wins
        'updated_by': 'device_b',
        'revision': 3,
        'edited_at': 2500,
        'created_at': 1000,
      };

      final ideaRemote = {
        'id': 'idea-uuid-conflict',
        'thought_id': 'LOG-005',
        'content': 'Laptop version of grocery list: Apples, Oranges, Milk',
        'bucket': 'Groceries',
        'bucket_id': 'b-uuid-groc',
        'done': 0,
        'trashed': 0,
        'updated_at': '2500:0:device_a', // Lower HLC loses
        'updated_by': 'device_a',
        'revision': 2,
        'edited_at': 2000,
        'created_at': 1000,
      };

      final result = BleMergeEngine.mergeDatasets(
        localThoughts: [ideaLocal],
        remoteThoughts: [ideaRemote],
        localBuckets: [],
        remoteBuckets: [],
        localTombstones: [],
        remoteTombstones: [],
        currentDeviceId: 'device_b',
      );

      // Should contain 2 ideas: the winning idea and the conflict copy
      expect(result.mergedThoughts.length, 2);

      final winner = result.mergedThoughts.firstWhere((t) => t['id'] == 'idea-uuid-conflict');
      expect(winner['content'], 'Phone version of grocery list: Apples, Bananas');

      final conflictCopy = result.mergedThoughts.firstWhere((t) => t['id'] != 'idea-uuid-conflict');
      expect(conflictCopy['content'], startsWith('Conflict copy: Laptop version of grocery list: Apples, Oranges, Milk'));
      expect(conflictCopy['bucket'], isNull); // Saved to Unsorted
      expect(conflictCopy['bucket_id'], isNull);
    });

    test('Bucket deduplication merges same-named buckets into one', () {
      final b1 = {
        'id': 'b-uuid-1',
        'name': 'Tasks',
        'created_at': 1000,
        'updated_at': '1000:0:dev_a',
        'updated_by': 'dev_a',
        'revision': 1,
      };
      final b2 = {
        'id': 'b-uuid-2',
        'name': '  tasks  ', // same name different case/space
        'created_at': 2000,
        'updated_at': '2000:0:dev_b',
        'updated_by': 'dev_b',
        'revision': 1,
      };

      final thoughtForB2 = {
        'id': 'thought-1',
        'thought_id': 'LOG-001',
        'content': 'Do this task',
        'bucket': '  tasks  ',
        'bucket_id': 'b-uuid-2',
        'done': 0,
        'trashed': 0,
        'updated_at': '2000:0:dev_b',
        'updated_by': 'dev_b',
        'revision': 1,
        'created_at': 2000,
      };

      final result = BleMergeEngine.mergeDatasets(
        localThoughts: [],
        remoteThoughts: [thoughtForB2],
        localBuckets: [b1],
        remoteBuckets: [b2],
        localTombstones: [],
        remoteTombstones: [],
        currentDeviceId: 'dev_a',
      );

      // Buckets merged into 1 (b-uuid-1 kept because older created_at)
      expect(result.mergedBuckets.length, 1);
      expect(result.mergedBuckets.first['id'], 'b-uuid-1');
      expect(result.mergedBuckets.first['name'], 'Tasks');

      // Alias recorded
      expect(result.bucketAliases['b-uuid-2'], 'b-uuid-1');

      // Thought pointing to b2 repointed to b1
      expect(result.mergedThoughts.first['bucket_id'], 'b-uuid-1');
      expect(result.mergedThoughts.first['bucket'], 'Tasks');
      expect(result.bucketsMergedCount, 1);
    });

    test('Tombstones propagate and exclude deleted records', () {
      final activeIdea = {
        'id': 'idea-to-delete',
        'thought_id': 'LOG-001',
        'content': 'I was deleted forever on the other device',
        'bucket': null,
        'done': 0,
        'trashed': 0,
        'updated_at': '1000:0:dev_a',
        'updated_by': 'dev_a',
        'revision': 1,
        'created_at': 1000,
      };

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final tombstone = {
        'id': 'idea-to-delete',
        'record_type': 'thought',
        'deleted_at': nowMs,
        'updated_at': '1500:0:dev_b',
        'updated_by': 'dev_b',
      };

      final result = BleMergeEngine.mergeDatasets(
        localThoughts: [activeIdea],
        remoteThoughts: [],
        localTombstones: [],
        remoteTombstones: [tombstone],
        localBuckets: [],
        remoteBuckets: [],
        currentDeviceId: 'dev_a',
      );

      expect(result.mergedThoughts.any((t) => t['id'] == 'idea-to-delete'), isFalse);
      expect(result.mergedTombstones.any((t) => t['id'] == 'idea-to-delete'), isTrue);
    });

    test('Pre-update duplicates with same text within 2 minutes deduplicate to 1 copy', () {
      final copy1 = {
        'id': 'uuid-dup-1',
        'thought_id': 'LOG-001',
        'content': 'Identical note created from old one-way sync',
        'bucket': 'Work',
        'done': 0,
        'trashed': 0,
        'created_at': 1700000000000, // Time T
        'updated_at': '1700000000000:0:dev_a',
        'updated_by': 'dev_a',
        'revision': 1,
      };

      final copy2 = {
        'id': 'uuid-dup-2',
        'thought_id': 'LOG-002',
        'content': 'Identical note created from old one-way sync',
        'bucket': 'Work',
        'done': 0,
        'trashed': 0,
        'created_at': 1700000060000, // Time T + 60s (within 120s)
        'updated_at': '1700000060000:0:dev_b',
        'updated_by': 'dev_b',
        'revision': 1,
      };

      final result = BleMergeEngine.mergeDatasets(
        localThoughts: [copy1],
        remoteThoughts: [copy2],
        localBuckets: [],
        remoteBuckets: [],
        localTombstones: [],
        remoteTombstones: [],
        currentDeviceId: 'dev_a',
      );

      expect(result.mergedThoughts.length, 1);
      expect(result.mergedThoughts.first['content'], 'Identical note created from old one-way sync');
    });

    test('Plain-words summary generated without technical jargon', () {
      final summary = BleMergeEngine.formatSummary(
        addedCount: 3,
        updatedCount: 2,
        trashedCount: 1,
        mergedBucketNames: ['Projects', 'Tasks'],
      );

      expect(summary, contains('Added 3 ideas.'));
      expect(summary, contains('Updated 2.'));
      expect(summary, contains('Moved 1 to Trash.'));
      expect(summary, contains('Merged 2 buckets (Projects, Tasks).'));
    });
  });
}
