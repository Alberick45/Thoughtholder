import 'package:flutter_test/flutter_test.dart';
import 'package:thought_holder_flutter/stream_screen.dart';

void main() {
  group('STEP 3: The Bucket Page (Focus Mode) - Filtering & Logic Tests', () {
    final t1 = {
      'id': '1',
      'title': 'Alpha task',
      'text': 'Buy groceries at the market',
      'created_at': DateTime(2026, 10, 15, 10, 0).millisecondsSinceEpoch,
      'when_val': 'today',
      'time_val': 'quick',
      'bucket': 'Work',
    };

    final t2 = {
      'id': '2',
      'title': 'Beta idea',
      'text': 'Read novel in the evening',
      'created_at': DateTime(2026, 10, 20, 14, 0).millisecondsSinceEpoch,
      'when_val': 'soon',
      'time_val': 'medium',
      'bucket': 'Work',
    };

    final t3 = {
      'id': '3',
      'title': 'Gamma project',
      'text': 'Plan market strategy and novel approach',
      'created_at': DateTime(2026, 9, 5, 8, 0).millisecondsSinceEpoch,
      'when_val': 'later',
      'time_val': 'long',
      'bucket': 'Work',
    };

    final placeholder1 = {
      'id': 'p1',
      'title': 'Placeholder zero',
      'text': 'Old imported thought',
      'created_at': 0,
      'when_val': null,
      'time_val': null,
      'bucket': 'Work',
    };

    final placeholder2 = {
      'id': 'p2',
      'title': 'Placeholder 2023',
      'text': 'Ancient note before 2 Jan 2024',
      'created_at': DateTime(2023, 12, 31).millisecondsSinceEpoch,
      'when_val': null,
      'time_val': null,
      'bucket': 'Work',
    };

    final allIdeas = [t1, t2, t3, placeholder1, placeholder2];

    test('1. Search matches idea name and text, any word, case-insensitive', () {
      // Matches "groceries" in text
      final r1 = StreamScreenTestHelper.applyBucketFilters(
        allIdeas: allIdeas,
        searchQuery: 'groceries',
        date: 'All time',
        month: null,
        year: null,
        dateUnknown: false,
        sort: 'Best first',
        when: 'Any',
        time: 'Any',
      );
      expect(r1.length, 1);
      expect(r1.first['id'], '1');

      // Matches "novel" (t2 in text, t3 in text)
      final r2 = StreamScreenTestHelper.applyBucketFilters(
        allIdeas: allIdeas,
        searchQuery: 'NOVEL',
        date: 'All time',
        month: null,
        year: null,
        dateUnknown: false,
        sort: 'Best first',
        when: 'Any',
        time: 'Any',
      );
      expect(r2.length, 2);
      expect(r2.map((e) => e['id']), containsAll(['2', '3']));

      // "any word": "Alpha evening" matches t1 (Alpha) and t2 (evening)
      final r3 = StreamScreenTestHelper.applyBucketFilters(
        allIdeas: allIdeas,
        searchQuery: 'Alpha evening',
        date: 'All time',
        month: null,
        year: null,
        dateUnknown: false,
        sort: 'Best first',
        when: 'Any',
        time: 'Any',
      );
      expect(r3.length, 2);
      expect(r3.map((e) => e['id']), containsAll(['1', '2']));
    });

    test('2. Placeholders detection and exclusion from date range filters', () {
      expect(StreamScreenTestHelper.isPlaceholder(placeholder1), isTrue);
      expect(StreamScreenTestHelper.isPlaceholder(placeholder2), isTrue);
      expect(StreamScreenTestHelper.isPlaceholder(t1), isFalse);

      // Filtering for "Date unknown"
      final unknownResult = StreamScreenTestHelper.applyBucketFilters(
        allIdeas: allIdeas,
        searchQuery: '',
        date: 'Pick a month',
        month: null,
        year: null,
        dateUnknown: true,
        sort: 'Best first',
        when: 'Any',
        time: 'Any',
      );
      expect(unknownResult.length, 2);
      expect(unknownResult.map((e) => e['id']), containsAll(['p1', 'p2']));

      // "This year" (2026) excludes placeholders
      final thisYearResult = StreamScreenTestHelper.applyBucketFilters(
        allIdeas: allIdeas,
        searchQuery: '',
        date: 'This year',
        month: null,
        year: null,
        dateUnknown: false,
        sort: 'Best first',
        when: 'Any',
        time: 'Any',
      );
      expect(thisYearResult.any((e) => e['id'] == 'p1' || e['id'] == 'p2'), isFalse);
    });

    test('3. Pick a month filter', () {
      // October 2026
      final octResult = StreamScreenTestHelper.applyBucketFilters(
        allIdeas: allIdeas,
        searchQuery: '',
        date: 'Pick a month',
        month: 10,
        year: 2026,
        dateUnknown: false,
        sort: 'Best first',
        when: 'Any',
        time: 'Any',
      );
      expect(octResult.length, 2);
      expect(octResult.map((e) => e['id']), containsAll(['1', '2']));

      // September 2026
      final sepResult = StreamScreenTestHelper.applyBucketFilters(
        allIdeas: allIdeas,
        searchQuery: '',
        date: 'Pick a month',
        month: 9,
        year: 2026,
        dateUnknown: false,
        sort: 'Best first',
        when: 'Any',
        time: 'Any',
      );
      expect(sepResult.length, 1);
      expect(sepResult.first['id'], '3');
    });

    test('4. When and Time filters', () {
      // When: today
      final whenResult = StreamScreenTestHelper.applyBucketFilters(
        allIdeas: allIdeas,
        searchQuery: '',
        date: 'All time',
        month: null,
        year: null,
        dateUnknown: false,
        sort: 'Best first',
        when: 'Today',
        time: 'Any',
      );
      expect(whenResult.length, 1);
      expect(whenResult.first['id'], '1');

      // Time: medium
      final timeResult = StreamScreenTestHelper.applyBucketFilters(
        allIdeas: allIdeas,
        searchQuery: '',
        date: 'All time',
        month: null,
        year: null,
        dateUnknown: false,
        sort: 'Best first',
        when: 'Any',
        time: 'Medium',
      );
      expect(timeResult.length, 1);
      expect(timeResult.first['id'], '2');
    });

    test('5. Sort order Newest first and Oldest first', () {
      final newest = StreamScreenTestHelper.applyBucketFilters(
        allIdeas: [t1, t2, t3],
        searchQuery: '',
        date: 'All time',
        month: null,
        year: null,
        dateUnknown: false,
        sort: 'Newest first',
        when: 'Any',
        time: 'Any',
      );
      // t2 is Oct 20, t1 is Oct 15, t3 is Sep 5
      expect(newest.map((e) => e['id']).toList(), ['2', '1', '3']);

      final oldest = StreamScreenTestHelper.applyBucketFilters(
        allIdeas: [t1, t2, t3],
        searchQuery: '',
        date: 'All time',
        month: null,
        year: null,
        dateUnknown: false,
        sort: 'Oldest first',
        when: 'Any',
        time: 'Any',
      );
      expect(oldest.map((e) => e['id']).toList(), ['3', '1', '2']);
    });
  });
}
