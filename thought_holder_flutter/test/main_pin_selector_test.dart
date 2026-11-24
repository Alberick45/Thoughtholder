import 'package:flutter_test/flutter_test.dart';
import 'package:thought_holder_flutter/utils/main_pin_selector.dart';

Map<String, dynamic> task(String id, {bool done = false, String bucket = 'Main'}) {
  return {
    'id': id,
    'title': 'Task $id',
    'bucket': bucket,
    'done': done ? 1 : 0,
    'status': done ? 'completed' : 'active',
  };
}

void main() {
  group('MainPinSelector', () {
    test('returns null when there are no incomplete Main tasks', () {
      final mains = [task('a', done: true), task('b', done: true)];
      expect(
        MainPinSelector.pick(
          mainThoughts: mains,
          mode: MainPinSelector.modeShuffle,
          today: '2026-11-24',
        ),
        isNull,
      );
    });

    test('shuffle is deterministic per day and ignores completed tasks', () {
      final mains = [task('a'), task('b'), task('c'), task('done', done: true)];
      final today = '2026-11-24';
      final first = MainPinSelector.pick(
        mainThoughts: mains,
        mode: MainPinSelector.modeShuffle,
        today: today,
        now: DateTime(2026, 11, 24),
      );
      final second = MainPinSelector.pick(
        mainThoughts: mains,
        mode: MainPinSelector.modeShuffle,
        today: today,
        now: DateTime(2026, 11, 24),
      );
      expect(first, isNotNull);
      expect(first!['id'], second!['id']);
      expect(first['id'], isNot('done'));
    });

    test('honours saved shuffle pick for the current day', () {
      final mains = [task('a'), task('b'), task('c')];
      final pick = MainPinSelector.pick(
        mainThoughts: mains,
        mode: MainPinSelector.modeShuffle,
        savedDate: '2026-11-24',
        savedId: 'c',
        today: '2026-11-24',
      );
      expect(pick!['id'], 'c');
    });

    test('ignores saved shuffle pick from a previous day', () {
      final mains = [task('a'), task('b'), task('c')];
      final pick = MainPinSelector.pick(
        mainThoughts: mains,
        mode: MainPinSelector.modeShuffle,
        savedDate: '2026-11-23',
        savedId: 'c',
        today: '2026-11-24',
        now: DateTime(2026, 11, 24),
      );
      expect(pick, isNotNull);
    });

    test('choose mode prefers chosen task, falls back to first incomplete', () {
      final mains = [task('a'), task('b'), task('c', done: true)];
      final chosen = MainPinSelector.pick(
        mainThoughts: mains,
        mode: MainPinSelector.modeChoose,
        chosenId: 'b',
        today: '2026-11-24',
      );
      expect(chosen!['id'], 'b');

      final fallback = MainPinSelector.pick(
        mainThoughts: mains,
        mode: MainPinSelector.modeChoose,
        chosenId: 'missing',
        today: '2026-11-24',
      );
      expect(fallback!['id'], 'a');
    });

    test('reshuffle avoids the current task when alternatives exist', () {
      final mains = [task('a'), task('b'), task('c')];
      final pick = MainPinSelector.reshuffle(
        mainThoughts: mains,
        currentId: 'a',
      );
      expect(pick, isNotNull);
      expect(pick!['id'], isNot('a'));
    });

    test('reshuffle returns the only task when no alternative exists', () {
      final mains = [task('a')];
      final pick = MainPinSelector.reshuffle(
        mainThoughts: mains,
        currentId: 'a',
      );
      expect(pick!['id'], 'a');
    });
  });
}
