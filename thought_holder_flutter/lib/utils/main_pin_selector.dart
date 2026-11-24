import 'dart:math';

/// Pure selection logic for the single reserved "Main" board card.
class MainPinSelector {
  static const String modeShuffle = 'shuffle';
  static const String modeChoose = 'choose';

  static bool isIncomplete(Map<String, dynamic> thought) {
    return (thought['done'] as num?)?.toInt() != 1 &&
        thought['status'] != 'completed';
  }

  static List<Map<String, dynamic>> incompleteMain(
      List<Map<String, dynamic>> mainThoughts) {
    return mainThoughts.where(isIncomplete).toList();
  }

  static Map<String, dynamic>? pick({
    required List<Map<String, dynamic>> mainThoughts,
    required String mode,
    String? chosenId,
    String? savedDate,
    String? savedId,
    required String today,
    DateTime? now,
  }) {
    final incomplete = incompleteMain(mainThoughts);
    if (incomplete.isEmpty) return null;

    if (mode == modeChoose) {
      if (chosenId != null) {
        final match = _find(incomplete, chosenId);
        if (match != null) return match;
      }
      return incomplete.first;
    }

    if (savedDate == today && savedId != null) {
      final match = _find(incomplete, savedId);
      if (match != null) return match;
    }

    final day = now ?? DateTime.now();
    final seed = day.year * 10000 + day.month * 100 + day.day;
    final sorted = List<Map<String, dynamic>>.from(incomplete)
      ..sort((a, b) =>
          (a['id'] as String? ?? '').compareTo(b['id'] as String? ?? ''));
    return sorted[seed % sorted.length];
  }

  static Map<String, dynamic>? reshuffle({
    required List<Map<String, dynamic>> mainThoughts,
    String? currentId,
    Random? random,
  }) {
    final incomplete = incompleteMain(mainThoughts);
    if (incomplete.isEmpty) return null;
    final candidates = incomplete
        .where((t) => t['id'] != currentId)
        .toList(growable: false);
    final pool = candidates.isNotEmpty ? candidates : incomplete;
    final rng = random ?? Random();
    return pool[rng.nextInt(pool.length)];
  }

  static Map<String, dynamic>? _find(
      List<Map<String, dynamic>> list, String id) {
    for (final t in list) {
      if (t['id'] == id) return t;
    }
    return null;
  }
}
