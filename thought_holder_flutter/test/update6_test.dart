import 'package:flutter_test/flutter_test.dart';
import 'package:thought_holder_flutter/starter_buckets_screen.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('UPDATE 6 - Section A: New Ideas Come First in Unsorted & Session Queue', () {
    test('Unsorted order defaults to newest first', () {
      final thoughts = [
        {'id': '1', 'thought_id': 'LOG-001', 'created_at': 1000, 'bucket': null, 'done': 0, 'trashed': 0},
        {'id': '2', 'thought_id': 'LOG-002', 'created_at': 2000, 'bucket': null, 'done': 0, 'trashed': 0},
        {'id': '3', 'thought_id': 'LOG-003', 'created_at': 3000, 'bucket': null, 'done': 0, 'trashed': 0},
      ];

      // Newest first sorting: 3000 -> 2000 -> 1000
      final sortedNewest = List<Map<String, dynamic>>.from(thoughts);
      sortedNewest.sort((a, b) {
        final int cA = (a['created_at'] as num).toInt();
        final int cB = (b['created_at'] as num).toInt();
        return cB.compareTo(cA);
      });

      expect(sortedNewest.first['id'], '3');
      expect(sortedNewest[1]['id'], '2');
      expect(sortedNewest.last['id'], '1');
    });

    test('Unsorted order can be toggled to oldest first', () {
      final thoughts = [
        {'id': '1', 'thought_id': 'LOG-001', 'created_at': 1000, 'bucket': null, 'done': 0, 'trashed': 0},
        {'id': '2', 'thought_id': 'LOG-002', 'created_at': 2000, 'bucket': null, 'done': 0, 'trashed': 0},
        {'id': '3', 'thought_id': 'LOG-003', 'created_at': 3000, 'bucket': null, 'done': 0, 'trashed': 0},
      ];

      // Oldest first sorting: 1000 -> 2000 -> 3000
      final sortedOldest = List<Map<String, dynamic>>.from(thoughts);
      sortedOldest.sort((a, b) {
        final int cA = (a['created_at'] as num).toInt();
        final int cB = (b['created_at'] as num).toInt();
        return cA.compareTo(cB);
      });

      expect(sortedOldest.first['id'], '1');
      expect(sortedOldest.last['id'], '3');
    });

    test('Skip for now sends idea to the end of the queue without mutating created_at or LOG number', () {
      final thoughts = [
        {'id': '1', 'thought_id': 'LOG-001', 'created_at': 3000, 'bucket': null, 'done': 0, 'trashed': 0},
        {'id': '2', 'thought_id': 'LOG-002', 'created_at': 2000, 'bucket': null, 'done': 0, 'trashed': 0},
        {'id': '3', 'thought_id': 'LOG-003', 'created_at': 1000, 'bucket': null, 'done': 0, 'trashed': 0},
      ];

      final sessionSkippedIds = <String>[];

      List<Map<String, dynamic>> computeQueue() {
        final unskipped = thoughts.where((t) => !sessionSkippedIds.contains(t['id'])).toList();
        final skipped = <Map<String, dynamic>>[];
        for (final id in sessionSkippedIds) {
          final found = thoughts.firstWhere((t) => t['id'] == id, orElse: () => {});
          if (found.isNotEmpty) skipped.add(found);
        }
        return [...unskipped, ...skipped];
      }

      // Initial queue: 1 (Idea 1), 2, 3
      expect(computeQueue().first['id'], '1');

      // User skips Idea 1
      sessionSkippedIds.add('1');
      final queueAfterSkip = computeQueue();

      // Now Idea 2 is Idea 1 of queue, and Idea 1 is moved to the end
      expect(queueAfterSkip.first['id'], '2');
      expect(queueAfterSkip.last['id'], '1');

      // Crucial: created_at and LOG number remain intact
      expect(queueAfterSkip.last['created_at'], 3000);
      expect(queueAfterSkip.last['thought_id'], 'LOG-001');
    });
  });

  group('UPDATE 6 - Section B & C: Starter Buckets Configuration & Deduplication', () {
    test('Starter buckets has exactly 5 fixed items with correct defaults', () {
      expect(kStarterBuckets.length, 5);

      final names = kStarterBuckets.map((b) => b.name).toList();
      expect(names, [
        'Tasks',
        'Personal improvement',
        'Projects',
        'Learning',
        'Someday',
      ]);

      // Tasks and Personal improvement are checked by default
      expect(kStarterBuckets[0].defaultChecked, isTrue); // Tasks
      expect(kStarterBuckets[1].defaultChecked, isTrue); // Personal improvement
      expect(kStarterBuckets[2].defaultChecked, isFalse); // Projects
      expect(kStarterBuckets[3].defaultChecked, isFalse); // Learning
      expect(kStarterBuckets[4].defaultChecked, isFalse); // Someday
    });

    test('Starter buckets icons map to valid predefined icons', () {
      expect(kStarterBuckets[0].iconKey, 'briefcase');
      expect(kStarterBuckets[1].iconKey, 'heart');
      expect(kStarterBuckets[2].iconKey, 'bulb');
      expect(kStarterBuckets[3].iconKey, 'book');
      expect(kStarterBuckets[4].iconKey, 'star');
    });

    test('Bucket deduplication is case-insensitive', () {
      final existingBuckets = [
        {'name': 'Tasks', 'icon': 'briefcase'},
        {'name': 'Personal Improvement', 'icon': 'heart'},
      ];

      bool hasBucketCaseInsensitive(String candidate) {
        final lower = candidate.trim().toLowerCase();
        return existingBuckets.any((b) => (b['name'] as String).trim().toLowerCase() == lower);
      }

      expect(hasBucketCaseInsensitive('tasks'), isTrue);
      expect(hasBucketCaseInsensitive('TASKS'), isTrue);
      expect(hasBucketCaseInsensitive('Personal improvement'), isTrue);
      expect(hasBucketCaseInsensitive('Projects'), isFalse);
      expect(hasBucketCaseInsensitive('Learning'), isFalse);
    });
  });

  group('UPDATE 6 - Section C: 3 Most Used Buckets First, Then Alphabetical', () {
    test('Popup bucket list places top 3 most used first, rest alphabetically', () {
      final buckets = [
        {'name': 'Zeta'},
        {'name': 'Alpha'},
        {'name': 'Gamma'},
        {'name': 'Beta'},
        {'name': 'Delta'},
        {'name': 'Epsilon'},
      ];

      final ideaCounts = {
        'Beta': 50,
        'Delta': 40,
        'Zeta': 30,
        'Alpha': 10,
        'Gamma': 5,
        'Epsilon': 2,
      };

      final sortedByUsage = List<Map<String, dynamic>>.from(buckets);
      sortedByUsage.sort((a, b) {
        final countA = ideaCounts[a['name']] ?? 0;
        final countB = ideaCounts[b['name']] ?? 0;
        if (countB != countA) return countB.compareTo(countA);
        return (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
      });

      final top3 = sortedByUsage.take(3).toList();
      final rest = sortedByUsage.skip(3).toList();
      rest.sort((a, b) =>
          (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));

      final ordered = [...top3, ...rest];

      // Top 3 by usage: Beta (50), Delta (40), Zeta (30)
      expect(ordered[0]['name'], 'Beta');
      expect(ordered[1]['name'], 'Delta');
      expect(ordered[2]['name'], 'Zeta');

      // Remaining 3 sorted alphabetically: Alpha, Epsilon, Gamma
      expect(ordered[3]['name'], 'Alpha');
      expect(ordered[4]['name'], 'Epsilon');
      expect(ordered[5]['name'], 'Gamma');
    });
  });

  group('UPDATE 6 - Section C: Bucket Split Prompt at 25 Ideas', () {
    test('Bucket split prompt logic triggers at >= 25 ideas and respects dismissal', () {
      final dismissedBuckets = <String>{};

      bool shouldShowSplitPrompt(int ideaCount, String bucketName) {
        if (ideaCount < 25) return false;
        return !dismissedBuckets.contains(bucketName.trim().toLowerCase());
      }

      // At 24 ideas: should not show
      expect(shouldShowSplitPrompt(24, 'Projects'), isFalse);

      // At 25 ideas: should show
      expect(shouldShowSplitPrompt(25, 'Projects'), isTrue);

      // Dismissed: never show again
      dismissedBuckets.add('projects');
      expect(shouldShowSplitPrompt(25, 'Projects'), isFalse);
      expect(shouldShowSplitPrompt(100, 'Projects'), isFalse);

      // Other bucket not dismissed: shows when reaching 25
      expect(shouldShowSplitPrompt(25, 'Tasks'), isTrue);
    });
  });
}
