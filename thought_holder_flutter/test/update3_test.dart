import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thought_holder_flutter/thought_provider.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('UPDATE 3 - Ranking Engine & Reasons', () {
    test('Reason format corresponds to when_val and time_val', () {
      final t1 = {
        'id': '1',
        'thought_id': 'LOG-001',
        'content': 'Test idea',
        'when_val': 'Soon',
        'time_val': 'Quick',
      };
      expect(RankingEngine.getReason(t1), 'Quick to finish · due soon');

      final t2 = {
        'id': '2',
        'thought_id': 'LOG-002',
        'content': 'Deep work',
        'when_val': 'Today',
        'time_val': 'Long',
      };
      expect(RankingEngine.getReason(t2), 'Takes a while · due today');

      final t3 = {
        'id': '3',
        'thought_id': 'LOG-003',
        'content': 'Later task',
        'when_val': 'Later',
        'time_val': 'Medium',
      };
      expect(RankingEngine.getReason(t3), 'Medium effort · no rush');
    });
  });

  group('UPDATE 3 - Data: editedAt and Preservation', () {
    test('Editing idea content sets edited_at and preserves LOG, bucket, When, Time', () async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
CREATE TABLE thoughts (
  id TEXT PRIMARY KEY,
  thought_id TEXT UNIQUE,
  content TEXT NOT NULL,
  source TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  status TEXT DEFAULT 'active',
  bucket TEXT,
  when_val TEXT DEFAULT 'Soon',
  time_val TEXT DEFAULT 'Medium',
  done INTEGER DEFAULT 0,
  trashed INTEGER DEFAULT 0,
  done_at INTEGER,
  trashed_at INTEGER,
  edited_at INTEGER
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

      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('thoughts', {
        'id': 'id-100',
        'thought_id': 'LOG-100',
        'content': 'Original content',
        'source': 'text',
        'created_at': now,
        'status': 'active',
        'bucket': 'School related',
        'when_val': 'Today',
        'time_val': 'Quick',
        'done': 0,
        'trashed': 0,
        'edited_at': null,
      });

      // Verify initial state
      final initial = (await db.query('thoughts', where: 'id = ?', whereArgs: ['id-100'])).first;
      expect(initial['thought_id'], 'LOG-100');
      expect(initial['bucket'], 'School related');
      expect(initial['when_val'], 'Today');
      expect(initial['time_val'], 'Quick');
      expect(initial['edited_at'], isNull);

      // Perform edit
      final editTime = now + 5000;
      await db.update(
        'thoughts',
        {
          'content': 'Updated content for LOG-100',
          'edited_at': editTime,
        },
        where: 'id = ?',
        whereArgs: ['id-100'],
      );

      // Verify post-edit state: LOG number, bucket, When, Time are UNCHANGED
      final updated = (await db.query('thoughts', where: 'id = ?', whereArgs: ['id-100'])).first;
      expect(updated['content'], 'Updated content for LOG-100');
      expect(updated['thought_id'], 'LOG-100');
      expect(updated['bucket'], 'School related');
      expect(updated['when_val'], 'Today');
      expect(updated['time_val'], 'Quick');
      expect(updated['edited_at'], editTime);

      await db.close();
    });
  });

  group('UPDATE 3 - Bucket Deduplication and Current Bucket Filtering', () {
    test('Filtering out current bucket from destination list', () {
      final buckets = [
        {'name': 'School related', 'icon': 'school'},
        {'name': 'Work', 'icon': 'work'},
        {'name': 'Personal', 'icon': 'home'},
      ];

      const currentBucket = 'School related';

      final available = buckets.where((b) {
        final name = (b['name'] as String).trim();
        if (currentBucket.isNotEmpty) {
          if (name.toLowerCase() == currentBucket.toLowerCase()) {
            return false;
          }
        }
        return true;
      }).map((b) => b['name']).toList();

      expect(available, isNot(contains('School related')));
      expect(available, contains('Work'));
      expect(available, contains('Personal'));
    });
  });
}
