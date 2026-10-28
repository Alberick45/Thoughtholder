import 'package:flutter/material.dart';
import 'database_helper.dart';

class RankingEngine {
  static const Map<String, double> whenWeights = {
    'Today': 3.0,
    'Soon': 2.0,
    'Later': 1.0,
  };

  static const Map<String, double> timeWeights = {
    'Quick': 1.0,
    'Medium': 2.0,
    'Long': 3.0,
  };

  /// Single function calculating priority score:
  /// score = when_value / time_value
  /// when_value: Today=3, Soon=2, Later=1
  /// time_value: Quick=1, Medium=2, Long=3
  /// Extensible so user can add factors later (near-done boost, energy fit, waiting penalty).
  static double calculateScore(Map<String, dynamic> thought) {
    final whenStr = (thought['when_val'] as String?)?.trim() ?? 'Soon';
    final timeStr = (thought['time_val'] as String?)?.trim() ?? 'Medium';

    final whenVal = whenWeights[whenStr] ?? 2.0;
    final timeVal = timeWeights[timeStr] ?? 2.0;

    double score = whenVal / timeVal;

    // Hook for future factors:
    // score += nearDoneBoost(thought);
    // score += energyFit(thought);
    // score -= waitingPenalty(thought);

    return score;
  }

  /// Sort descending by score, tie-break oldest first
  static int compareRanked(Map<String, dynamic> a, Map<String, dynamic> b) {
    final scoreA = calculateScore(a);
    final scoreB = calculateScore(b);
    if ((scoreB - scoreA).abs() > 0.0001) {
      return scoreB.compareTo(scoreA); // descending
    }
    final int createdA = (a['created_at'] as num?)?.toInt() ?? 0;
    final int createdB = (b['created_at'] as num?)?.toInt() ?? 0;
    return createdA.compareTo(createdB); // oldest first
  }

  /// Plain-language reason for ranking
  static String getReason(Map<String, dynamic> thought) {
    final whenStr = (thought['when_val'] as String?)?.trim() ?? 'Soon';
    final timeStr = (thought['time_val'] as String?)?.trim() ?? 'Medium';

    String timePart;
    switch (timeStr) {
      case 'Quick':
        timePart = 'Quick to finish';
        break;
      case 'Medium':
        timePart = 'Moderate time';
        break;
      case 'Long':
        timePart = 'Needs focus';
        break;
      default:
        timePart = 'Quick to finish';
    }

    String whenPart;
    switch (whenStr) {
      case 'Today':
        whenPart = 'due today';
        break;
      case 'Soon':
        whenPart = 'due soon';
        break;
      case 'Later':
        whenPart = 'for later';
        break;
      default:
        whenPart = 'due soon';
    }

    return '$timePart · $whenPart';
  }
}

class ThoughtProvider with ChangeNotifier {
  List<Map<String, dynamic>> _thoughts = [];
  List<String> _buckets = [];

  List<Map<String, dynamic>> get thoughts => _thoughts;
  List<String> get buckets => _buckets;

  ThoughtProvider() {
    loadAll();
  }

  Future<void> loadAll() async {
    await Future.wait([
      loadThoughts(),
      loadBuckets(),
    ]);
  }

  Future<void> loadThoughts() async {
    _thoughts = await DatabaseHelper.instance.fetchAllThoughts();
    notifyListeners();
  }

  Future<void> loadBuckets() async {
    _buckets = await DatabaseHelper.instance.fetchBuckets();
    notifyListeners();
  }

  // --- Classification Filters ---

  bool isDone(Map<String, dynamic> t) =>
      t['done'] == 1 || t['done'] == true || t['status'] == 'completed';

  bool isTrashed(Map<String, dynamic> t) =>
      t['trashed'] == 1 ||
      t['trashed'] == true ||
      t['status'] == 'vaulted_trash';

  bool isUnsorted(Map<String, dynamic> t) {
    if (isDone(t) || isTrashed(t)) return false;
    final b = t['bucket'];
    return b == null || (b is String && b.trim().isEmpty);
  }

  bool isSorted(Map<String, dynamic> t) {
    if (isDone(t) || isTrashed(t)) return false;
    final b = t['bucket'];
    return b != null && (b is String && b.trim().isNotEmpty);
  }

  List<Map<String, dynamic>> get unsortedThoughts =>
      _thoughts.where(isUnsorted).toList();

  List<Map<String, dynamic>> get sortedThoughts {
    final list = _thoughts.where(isSorted).toList();
    list.sort(RankingEngine.compareRanked);
    return list;
  }

  List<Map<String, dynamic>> get doneThoughts =>
      _thoughts.where(isDone).toList();

  List<Map<String, dynamic>> get trashedThoughts =>
      _thoughts.where(isTrashed).toList();

  int get unsortedCount => unsortedThoughts.length;
  int get sortedCount => sortedThoughts.length;
  int get doneCount => doneThoughts.length;
  int get trashCount => trashedThoughts.length;

  /// Single best next idea across all buckets
  Map<String, dynamic>? get bestNextThought {
    final sorted = sortedThoughts;
    return sorted.isNotEmpty ? sorted.first : null;
  }

  /// Ideas for a specific bucket, ranked best-first
  List<Map<String, dynamic>> getThoughtsForBucket(String bucketName) {
    final list = _thoughts.where((t) {
      if (isDone(t) || isTrashed(t)) return false;
      return (t['bucket'] as String?)?.trim() == bucketName.trim();
    }).toList();
    list.sort(RankingEngine.compareRanked);
    return list;
  }

  // --- Actions ---

  Future<void> addThought(
    String content,
    String type, {
    String tags = '',
    String? bucket,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final thought = {
      'id': UniqueKey().toString(),
      'thought_id': 'LOG-${now % 10000}',
      'content': content,
      'type': type,
      'status': 'active',
      'tags': tags,
      'summary': '',
      'created_at': now,
      'last_viewed_at': now,
      'stale_score': 0,
      'linked_thoughts': '[]',
      'bucket': bucket,
      'when_val': 'Soon',
      'time_val': 'Medium',
      'done': 0,
      'trashed': 0,
    };

    await DatabaseHelper.instance.insertThought(thought);
    await loadThoughts();
  }

  Future<void> fileThought(String id, String bucket) async {
    await DatabaseHelper.instance.updateThoughtBucket(id, bucket);
    await loadThoughts();
  }

  Future<void> unfileThought(String id) async {
    await DatabaseHelper.instance.updateThoughtBucket(id, null);
    await loadThoughts();
  }

  Future<void> cycleWhen(String id) async {
    final index = _thoughts.indexWhere((t) => t['id'] == id);
    if (index == -1) return;
    final current = (_thoughts[index]['when_val'] as String?) ?? 'Soon';

    String next;
    switch (current) {
      case 'Today':
        next = 'Soon';
        break;
      case 'Soon':
        next = 'Later';
        break;
      case 'Later':
      default:
        next = 'Today';
        break;
    }

    await DatabaseHelper.instance.updateThoughtRanking(id, whenVal: next);
    await loadThoughts();
  }

  Future<void> cycleTime(String id) async {
    final index = _thoughts.indexWhere((t) => t['id'] == id);
    if (index == -1) return;
    final current = (_thoughts[index]['time_val'] as String?) ?? 'Medium';

    String next;
    switch (current) {
      case 'Quick':
        next = 'Medium';
        break;
      case 'Medium':
        next = 'Long';
        break;
      case 'Long':
      default:
        next = 'Quick';
        break;
    }

    await DatabaseHelper.instance.updateThoughtRanking(id, timeVal: next);
    await loadThoughts();
  }

  Future<void> markDone(String id, bool done) async {
    await DatabaseHelper.instance.updateThoughtDone(id, done);
    await loadThoughts();
  }

  Future<void> moveToTrash(String id) async {
    await DatabaseHelper.instance.updateThoughtTrashed(id, true);
    await loadThoughts();
  }

  Future<void> restoreFromTrash(String id) async {
    await DatabaseHelper.instance.updateThoughtTrashed(id, false);
    await loadThoughts();
  }

  Future<void> deleteForever(String id) async {
    await DatabaseHelper.instance.deleteThought(id);
    await loadThoughts();
  }

  Future<void> updateStatus(String id, String status) async {
    await DatabaseHelper.instance.updateThoughtStatus(id, status);
    await loadThoughts();
  }

  Future<void> updateContent(String id, String content) async {
    await DatabaseHelper.instance.updateThoughtContent(id, content);
    await loadThoughts();
  }

  Future<void> addBucket(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await DatabaseHelper.instance.insertBucket(trimmed);
    await loadBuckets();
  }

  // --- LOG-149 Split Helper ---

  Map<String, dynamic>? findLog149() {
    try {
      return _thoughts.firstWhere(
        (t) =>
            t['thought_id'] == 'LOG-149' ||
            (t['content'] as String? ?? '').contains('LOG-149'),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> splitNoteIntoIdeas(
      String noteId, Map<String, List<String>> bucketedItems) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    int offset = 0;

    for (final entry in bucketedItems.entries) {
      final bucketName = entry.key;
      await addBucket(bucketName);

      for (final itemText in entry.value) {
        if (itemText.trim().isEmpty) continue;
        final thought = {
          'id': UniqueKey().toString(),
          'thought_id': 'LOG-${(now + offset) % 10000}',
          'content': itemText.trim(),
          'type': 'task',
          'status': 'active',
          'tags': 'split-from-$noteId',
          'summary': '',
          'created_at': now + offset,
          'last_viewed_at': now + offset,
          'stale_score': 0,
          'linked_thoughts': '[]',
          'bucket': bucketName,
          'when_val': 'Soon',
          'time_val': 'Medium',
          'done': 0,
          'trashed': 0,
        };
        await DatabaseHelper.instance.insertThought(thought);
        offset++;
      }
    }

    await loadAll();
  }
}
