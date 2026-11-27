import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'services/gamification_service.dart';
import 'settings_service.dart';
import 'sync_identity.dart';
import 'utils/main_pin_selector.dart';
import 'utils/title_generator.dart';

class RankingEngine {
  /// When values: 1 Later, 2 Soon, 3 Today
  static const Map<String, double> whenWeights = {
    'Today': 3.0,
    'Soon': 2.0,
    'Later': 1.0,
  };

  /// Time values: 1 Quick, 2 Medium, 3 Long
  static const Map<String, double> timeWeights = {
    'Quick': 1.0,
    'Medium': 2.0,
    'Long': 3.0,
  };

  /// Single function calculating priority score:
  /// score = when / time. Higher is better.
  /// Ties: oldest idea first.
  /// Extensible so user can add factors later (near-done boost, energy fit, waiting penalty, staleness bump).
  static double calculateScore(Map<String, dynamic> thought) {
    final whenStr = (thought['when_val'] as String?)?.trim() ?? 'Soon';
    final timeStr = (thought['time_val'] as String?)?.trim() ?? 'Medium';

    final whenVal = whenWeights[whenStr] ?? 2.0;
    final timeVal = timeWeights[timeStr] ?? 2.0;

    double score = whenVal / timeVal;

    // Extensible factors can be hooked here:
    // score += nearDoneBoost(thought);
    // score += energyFit(thought);
    // score -= waitingPenalty(thought);
    // score += stalenessBump(thought);

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

  /// Plain reason under ranked idea:
  /// e.g. "Quick to finish · due soon", "Takes a while · due today", "Medium effort · no rush"
  static String getReason(Map<String, dynamic> thought) {
    final whenStr = (thought['when_val'] as String?)?.trim() ?? 'Soon';
    final timeStr = (thought['time_val'] as String?)?.trim() ?? 'Medium';

    String timePart;
    switch (timeStr) {
      case 'Quick':
        timePart = 'Quick to finish';
        break;
      case 'Long':
        timePart = 'Takes a while';
        break;
      case 'Medium':
      default:
        timePart = 'Medium effort';
        break;
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
      default:
        whenPart = 'no rush';
        break;
    }

    return '$timePart · $whenPart';
  }
}

class SplitResult {
  final int createdCount;
  final int pinnedCount;
  final String? bucketName;

  const SplitResult({
    required this.createdCount,
    required this.pinnedCount,
    this.bucketName,
  });
}

class ThoughtProvider with ChangeNotifier {
  List<Map<String, dynamic>> _thoughts = [];
  List<Map<String, dynamic>> _buckets = [];
  SettingsService? _settings;
  final List<String> _sessionSkippedIds = [];

  List<Map<String, dynamic>> get thoughts => _thoughts;
  List<Map<String, dynamic>> get buckets => _buckets;
  List<String> get bucketNames =>
      _buckets.map((b) => b['name'] as String).toList();

  void updateSettings(SettingsService settings) {
    _settings = settings;
    notifyListeners();
  }

  void skipThoughtForSession(String id) {
    if (!_sessionSkippedIds.contains(id)) {
      _sessionSkippedIds.add(id);
      notifyListeners();
    }
  }

  void unskipThought(String id) {
    if (_sessionSkippedIds.remove(id)) {
      notifyListeners();
    }
  }

  void clearSessionSkips() {
    _sessionSkippedIds.clear();
    notifyListeners();
  }

  String getBucketIcon(String bucketName) {
    try {
      final b = _buckets.firstWhere((item) => item['name'] == bucketName);
      return (b['icon'] as String?) ?? 'folder';
    } catch (_) {
      return 'folder';
    }
  }

  ThoughtProvider() {
    loadAll();
  }

  Future<void> loadAll() async {
    await Future.wait([
      loadThoughts(),
      loadBuckets(),
    ]);
    populateMissingTitlesInBackground();
  }

  Future<void> loadThoughts() async {
    final raw = await DatabaseHelper.instance.fetchAllThoughts();
    _thoughts = raw.map((t) {
      final m = Map<String, dynamic>.from(t);
      if (m['edited_at'] != null && m['editedAt'] == null) {
        m['editedAt'] = m['edited_at'];
      }
      return m;
    }).toList();
    await checkAndResetRecurrence();
    notifyListeners();
  }

  /// Automatic reset for Main and Sides items based on recurrence (daily/weekly).
  Future<int> checkAndResetRecurrence() async {
    final now = DateTime.now();
    final startOfTodayMs = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final startOfWeekMs = DateTime(monday.year, monday.month, monday.day).millisecondsSinceEpoch;

    int resetCount = 0;
    for (int i = 0; i < _thoughts.length; i++) {
      final t = _thoughts[i];
      final isTaskDone = (t['done'] as num?)?.toInt() == 1 || t['status'] == 'completed';
      if (!isTaskDone) continue;

      final recurrence = (t['recurrence'] as String?)?.toLowerCase();
      final bucket = (t['bucket'] as String?)?.toLowerCase();
      final effectiveRecurrence = recurrence ??
          ((bucket == 'main' || bucket == 'sides') ? 'daily' : null);
      if (effectiveRecurrence == null) continue;

      final lastCompleted = (t['last_completed_at'] as num?)?.toInt() ??
          (t['done_at'] as num?)?.toInt() ??
          0;

      bool shouldReset = false;
      if (effectiveRecurrence == 'daily' && lastCompleted < startOfTodayMs) {
        shouldReset = true;
      } else if (effectiveRecurrence == 'weekly' && lastCompleted < startOfWeekMs) {
        shouldReset = true;
      }

      if (shouldReset) {
        await DatabaseHelper.instance.updateThoughtDone(t['id'] as String, false);
        _thoughts[i]['done'] = 0;
        _thoughts[i]['status'] = 'active';
        _thoughts[i]['done_at'] = null;
        resetCount++;
      }
    }
    return resetCount;
  }

  // --- Main, Sides, and Raw Getters & Progress ---

  List<Map<String, dynamic>> get mainThoughts => _thoughts
      .where((t) =>
          (t['bucket'] ?? '').toString().trim().toLowerCase() == 'main' &&
          (t['trashed'] as num?)?.toInt() != 1 &&
          t['status'] != 'vaulted_trash')
      .toList();

  List<Map<String, dynamic>> get sidesThoughts => _thoughts
      .where((t) =>
          (t['bucket'] ?? '').toString().trim().toLowerCase() == 'sides' &&
          (t['trashed'] as num?)?.toInt() != 1 &&
          t['status'] != 'vaulted_trash')
      .toList();

  List<Map<String, dynamic>> get rawThoughts => _thoughts
      .where((t) =>
          (t['bucket'] ?? '').toString().trim().toLowerCase() == 'raw' &&
          (t['trashed'] as num?)?.toInt() != 1 &&
          t['status'] != 'vaulted_trash')
      .toList();

  int get mainCompletedCount =>
      mainThoughts.where((t) => (t['done'] as num?)?.toInt() == 1 || t['status'] == 'completed').length;

  int get sidesCompletedCount =>
      sidesThoughts.where((t) => (t['done'] as num?)?.toInt() == 1 || t['status'] == 'completed').length;

  bool get isAllMainDone =>
      mainThoughts.isNotEmpty && mainCompletedCount == mainThoughts.length;

  String get mainProgressString =>
      "${mainCompletedCount}/${mainThoughts.length} Main done today";

  String get sidesProgressString =>
      "${sidesCompletedCount}/${sidesThoughts.length} Sides done";

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

  // UPDATE 6 - Section A:
  // Unsorted shows ideas newest first by default.
  // "Skip for now" sends the idea to the end of the Unsorted queue for this session.
  List<Map<String, dynamic>> get unsortedThoughts {
    final list = _thoughts.where(isUnsorted).toList();
    final order = _settings?.unsortedOrder ?? 'newest';

    if (order == 'oldest') {
      list.sort((a, b) {
        final int cA = (a['created_at'] as num?)?.toInt() ?? 0;
        final int cB = (b['created_at'] as num?)?.toInt() ?? 0;
        return cA.compareTo(cB); // oldest first
      });
    } else {
      list.sort((a, b) {
        final int cA = (a['created_at'] as num?)?.toInt() ?? 0;
        final int cB = (b['created_at'] as num?)?.toInt() ?? 0;
        return cB.compareTo(cA); // newest first (default)
      });
    }

    final unskipped =
        list.where((t) => !_sessionSkippedIds.contains(t['id'])).toList();
    final skipped = <Map<String, dynamic>>[];
    for (final id in _sessionSkippedIds) {
      final found = list.firstWhere(
        (t) => t['id'] == id,
        orElse: () => {},
      );
      if (found.isNotEmpty) {
        skipped.add(found);
      }
    }

    return [...unskipped, ...skipped];
  }

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

  /// Single highest-scoring live idea across all buckets
  Map<String, dynamic>? get bestNextThought {
    final sorted = sortedThoughts;
    return sorted.isNotEmpty ? sorted.first : null;
  }

  /// Highest-scoring unpinned idea across all buckets
  Map<String, dynamic>? get bestNextUnpinnedThought {
    for (final t in sortedThoughts) {
      if (!isPinned(t)) return t;
    }
    return null;
  }

  /// Ideas for a specific bucket, ranked best-first
  List<Map<String, dynamic>> getThoughtsForBucket(String bucketName) {
    final target = bucketName.trim().toLowerCase();
    final list = _thoughts.where((t) {
      if (isDone(t) || isTrashed(t)) return false;
      return (t['bucket'] as String?)?.trim().toLowerCase() == target;
    }).toList();
    list.sort(RankingEngine.compareRanked);
    return list;
  }

  int getIdeaCountForBucket(String bucketName) {
    final target = bucketName.trim().toLowerCase();
    return _thoughts.where((t) {
      if (isDone(t) || isTrashed(t)) return false;
      return (t['bucket'] as String?)?.trim().toLowerCase() == target;
    }).length;
  }

  List<Map<String, dynamic>> getOrderedBuckets(String orderPreference) {
    final list = List<Map<String, dynamic>>.from(_buckets);
    if (orderPreference == 'ideas') {
      list.sort((a, b) {
        final countA = getIdeaCountForBucket(a['name'] as String);
        final countB = getIdeaCountForBucket(b['name'] as String);
        if (countB != countA) {
          return countB.compareTo(countA); // most ideas first
        }
        return (a['name'] as String).compareTo(b['name'] as String);
      });
    } else {
      list.sort((a, b) {
        final int cA = (a['created_at'] as num?)?.toInt() ?? 0;
        final int cB = (b['created_at'] as num?)?.toInt() ?? 0;
        return cA.compareTo(cB); // creation order
      });
    }
    return list;
  }

  // --- Actions ---

  Future<Map<String, dynamic>> addThought(
    String content,
    String type, {
    String tags = '',
    String? bucket,
    String? recurrence,
    int? reminderAt,
    int? dueAt,
    String? actionText,
    String? measureText,
    int? deadlineAt,
    String? triggerText,
    String? intentType,
    double? intentConfidence,
    String? subStepsJson,
    int? nextSubStepIndex,
    int? goalTarget,
    String? goalUnit,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final deviceId = _settings != null ? SyncIdentity.getDeviceId(_settings!) : DatabaseHelper.currentDeviceId;
    final id = SyncIdentity.newUuid();

    // Quick capture: no required fields, default if empty
    final effectiveContent = content.trim().isEmpty ? 'Quick Note' : content.trim();

    String? bucketId;
    if (bucket != null && bucket.trim().isNotEmpty) {
      final bMatch = _buckets.firstWhere(
        (b) => (b['name'] as String).trim().toLowerCase() == bucket.trim().toLowerCase(),
        orElse: () => {},
      );
      if (bMatch.isNotEmpty) {
        bucketId = bMatch['id'] as String?;
      }
    }

    final autoTitle = TitleGenerator.generate(effectiveContent);
    final thought = {
      'id': id,
      'thought_id': 'LOG-${now % 10000}',
      'content': effectiveContent,
      'title': autoTitle,
      'title_source': 'auto',
      'type': type,
      'status': 'active',
      'tags': tags,
      'summary': '',
      'created_at': now,
      'last_viewed_at': now,
      'stale_score': 0,
      'linked_thoughts': '[]',
      'bucket': bucket,
      'bucket_id': bucketId,
      'when_val': 'Soon',
      'time_val': 'Medium',
      'done': 0,
      'trashed': 0,
      'edited_at': null,
      // 'editedAt' column does not exist in the schema; keep for legacy compatibility only in read path
      'updated_at': Hlc.now(deviceId).toString(),
      'updated_by': deviceId,
      'revision': 1,
      'recurrence': recurrence,
      'last_completed_at': null,
      'reminder_at': reminderAt,
      'due_at': dueAt,
      'action_text': actionText,
      'measure_text': measureText,
      'deadline_at': deadlineAt,
      'trigger_text': triggerText,
      'intent_type': intentType ?? 'unknown',
      'sub_steps': subStepsJson,
      'next_sub_step_index': nextSubStepIndex ?? 0,
      'goal_target': goalTarget,
      'goal_unit': goalUnit,
      'intent_confidence': intentConfidence ?? 0.0,
    };

    _sessionSkippedIds.remove(thought['id']);
    await DatabaseHelper.instance.insertThought(thought, deviceId: deviceId);
    await loadThoughts();
    return thought;
  }

  Future<void> setDueDate(String id, DateTime? due) async {
    await DatabaseHelper.instance
        .updateThoughtDueAt(id, due?.millisecondsSinceEpoch);
    await loadThoughts();
  }

  Future<void> setRecurrence(String id, String? recurrence) async {
    await DatabaseHelper.instance.updateThoughtRecurrence(id, recurrence);
    await loadThoughts();
  }

  Future<void> setReminder(String id, DateTime? reminder) async {
    await DatabaseHelper.instance
        .updateThoughtReminder(id, reminder?.millisecondsSinceEpoch);
    await loadThoughts();
  }

  Future<void> updateActionPlan(
    String id, {
    String? actionText,
    String? measureText,
    DateTime? deadlineAt,
    bool clearDeadline = false,
    String? triggerText,
    String? intentType,
    double? intentConfidence,
    String? subStepsJson,
    int? nextSubStepIndex,
    int? goalTarget,
    bool clearGoalTarget = false,
    String? goalUnit,
    bool clearGoalUnit = false,
  }) async {
    await DatabaseHelper.instance.updateThoughtActionPlan(
      id,
      actionText: actionText,
      measureText: measureText,
      deadlineAt: deadlineAt?.millisecondsSinceEpoch,
      clearDeadline: clearDeadline,
      triggerText: triggerText,
      intentType: intentType,
      intentConfidence: intentConfidence,
      subStepsJson: subStepsJson,
      nextSubStepIndex: nextSubStepIndex,
      goalTarget: goalTarget,
      clearGoalTarget: clearGoalTarget,
      goalUnit: goalUnit,
      clearGoalUnit: clearGoalUnit,
    );
    await loadThoughts();
  }

  Future<void> updateThoughtTitle(String id, String title,
      {String titleSource = 'user'}) async {
    await DatabaseHelper.instance
        .updateThoughtTitle(id, title, titleSource: titleSource);
    await loadThoughts();
  }

  bool _isPopulatingTitles = false;
  Future<void> populateMissingTitlesInBackground() async {
    if (_isPopulatingTitles) return;
    _isPopulatingTitles = true;
    Future.microtask(() async {
      try {
        while (true) {
          final count =
              await DatabaseHelper.instance.populateMissingTitlesBatch(batchSize: 200);
          if (count == 0) break;
          await loadThoughts();
          await Future.delayed(const Duration(milliseconds: 50));
        }
      } catch (_) {
      } finally {
        _isPopulatingTitles = false;
      }
    });
  }

  Future<void> fileThought(String id, String bucket) async {
    _sessionSkippedIds.remove(id);
    final lower = bucket.trim().toLowerCase();
    await DatabaseHelper.instance.updateThoughtBucket(id, bucket);
    if (lower != 'main' && lower != 'sides') {
      await DatabaseHelper.instance.updateThoughtRecurrence(id, null);
    }
    if (lower != 'raw') {
      await DatabaseHelper.instance.updateThoughtDueAt(id, null);
    }
    await loadThoughts();
  }

  Future<void> unfileThought(String id) async {
    _sessionSkippedIds.remove(id);
    await DatabaseHelper.instance.updateThoughtBucket(id, null);
    await loadThoughts();
  }

  Future<List<Map<String, dynamic>>> fetchRawDefaultRecoveryCandidates(
    int sinceCreatedAtMs,
  ) async {
    return DatabaseHelper.instance.fetchRawDefaultRecoveryCandidates(
      sinceCreatedAtMs: sinceCreatedAtMs,
    );
  }

  Future<int> moveRawThoughtsToUnsorted(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final deviceId = _settings != null
        ? SyncIdentity.getDeviceId(_settings!)
        : DatabaseHelper.currentDeviceId;
    final count = await DatabaseHelper.instance.moveRawThoughtsToUnsorted(
      ids,
      deviceId: deviceId,
    );
    await loadThoughts();
    return count;
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

  Future<int> markDone(String id, bool done) async {
    final tIndex = _thoughts.indexWhere((t) => t['id'] == id);
    final wasPinned =
        tIndex != -1 && ((_thoughts[tIndex]['is_pinned'] as int? ?? 0) == 1);
    final thoughtData =
        tIndex != -1 ? Map<String, dynamic>.from(_thoughts[tIndex]) : null;

    await DatabaseHelper.instance.updateThoughtDone(id, done);
    if (done && wasPinned) {
      await unpinFromBoard(id);
    }
    await loadThoughts();

    int xpEarned = 0;
    RewardEvent? rewardEvent;
    if (done && wasPinned && thoughtData != null) {
      rewardEvent = await GamificationService.instance
          .onPinnedTaskCompletedDetailed(thoughtData);
      xpEarned += rewardEvent.xpEarned;
    }
    if (done && isAllMainDone) {
      final mainEvent =
          await GamificationService.instance.onMainGoalCompletedDetailed();
      xpEarned += mainEvent.xpEarned;
      if (mainEvent.xpEarned > 0 ||
          mainEvent.coinsEarned > 0 ||
          mainEvent.dailyGoalReached ||
          mainEvent.leveledUp) {
        rewardEvent = RewardEvent(
          xpEarned: (rewardEvent?.xpEarned ?? 0) + mainEvent.xpEarned,
          coinsEarned: (rewardEvent?.coinsEarned ?? 0) + mainEvent.coinsEarned,
          dailyGoalReached:
              (rewardEvent?.dailyGoalReached ?? false) || mainEvent.dailyGoalReached,
          leveledUp: (rewardEvent?.leveledUp ?? false) || mainEvent.leveledUp,
          level: mainEvent.level,
          unlockName: mainEvent.unlockName ?? rewardEvent?.unlockName,
        );
      }
    }
    if (rewardEvent != null && (xpEarned > 0 || rewardEvent.coinsEarned > 0)) {
      GamificationService.instance.queueRewardEvent(rewardEvent);
    }
    return xpEarned;
  }

  Future<void> moveToTrash(String id) async {
    _sessionSkippedIds.remove(id);
    await DatabaseHelper.instance.updateThoughtTrashed(id, true);
    await loadThoughts();
  }

  Future<void> restoreFromTrash(String id) async {
    await DatabaseHelper.instance.updateThoughtTrashed(id, false);
    await loadThoughts();
  }

  Future<void> deleteForever(String id) async {
    _sessionSkippedIds.remove(id);
    await DatabaseHelper.instance.deleteThought(id);
    await loadThoughts();
  }

  Future<void> updateStatus(String id, String status) async {
    await DatabaseHelper.instance.updateThoughtStatus(id, status);
    await loadThoughts();
  }

  Future<void> updateContent(String id, String content, {int? editedAt}) async {
    final now = editedAt ?? DateTime.now().millisecondsSinceEpoch;
    await DatabaseHelper.instance.updateThoughtContent(id, content, editedAt: now);
    await loadThoughts();
  }

  Future<String> addBucket(String name, {String icon = 'folder'}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final existing = _buckets.firstWhere(
      (b) =>
          (b['name'] as String).trim().toLowerCase() == trimmed.toLowerCase(),
      orElse: () => {},
    );
    if (existing.isNotEmpty) {
      return existing['name'] as String;
    }
    await DatabaseHelper.instance.insertBucket(trimmed, icon: icon);
    await loadBuckets();
    return trimmed;
  }

  Future<void> renameBucket(String oldName, String newName) async {
    final lower = oldName.trim().toLowerCase();
    if (lower == 'raw' || lower == 'main' || lower == 'sides') {
      return; // Protected system bucket
    }
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    await DatabaseHelper.instance.renameBucket(oldName, trimmed);
    await loadAll();
  }

  Future<void> updateBucketIcon(String name, String icon) async {
    await DatabaseHelper.instance.updateBucketIcon(name, icon);
    await loadBuckets();
  }

  Future<int> deleteBucket(String name) async {
    final lower = name.trim().toLowerCase();
    if (lower == 'raw' || lower == 'main' || lower == 'sides') {
      return 0; // Protected system bucket
    }
    final unfiledCount = await DatabaseHelper.instance.deleteBucket(name);
    await loadAll();
    return unfiledCount;
  }

  /// Promote / move an item to Main, Sides, or any bucket.
  Future<void> moveToBucket(String thoughtId, String targetBucket) async {
    await addBucket(targetBucket);
    await fileThought(thoughtId, targetBucket);
  }

  // --- Main Pin Functionality (Reserve 1 Pin on Board) ---

  /// Retrieves the current Main item to pin on the board.
  /// In 'choose' mode: picks the user-selected Main item (or first incomplete).
  /// In 'shuffle' mode: picks only incomplete Main items, stores the pick for today so it is stable per launch.
  /// When item is completed, advances to next incomplete; when all are done, returns null ("Main complete").
  Map<String, dynamic>? getMainPinThought() {
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month}-${now.day}";
    return MainPinSelector.pick(
      mainThoughts: mainThoughts,
      mode: _settings?.mainPinMode ?? MainPinSelector.modeShuffle,
      chosenId: _settings?.chosenMainPinId,
      savedDate: _settings?.dailyShufflePickDate,
      savedId: _settings?.dailyShufflePickId,
      today: todayStr,
      now: now,
    );
  }

  /// Manual reshuffle button to pick a different incomplete Main item.
  Future<void> reshuffleMainPin() async {
    final currentId = getMainPinThought()?['id'] as String?;
    final pick = MainPinSelector.reshuffle(
      mainThoughts: mainThoughts,
      currentId: currentId,
    );
    if (pick == null) return;

    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month}-${now.day}";
    await _settings?.setDailyShufflePick(todayStr, pick['id'] as String);
    notifyListeners();
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

  /// Restores database to snapshot taken before last sync (Section 5 & 8)
  Future<bool> restoreFromLatestSnapshot() async {
    final success = await DatabaseHelper.instance.restoreLatestSnapshot();
    if (success) {
      await loadAll();
    }
    return success;
  }

  // --- Pin & Board Operations (PART 1: STICKY NOTE BOARD) ---

  bool isPinned(Map<String, dynamic> t) =>
      (t['is_pinned'] == 1 || t['is_pinned'] == true) &&
      !isDone(t) &&
      !isTrashed(t);

  /// Maximum regular sticky-note cards. Slot 0 of the board is reserved for Main.
  static const int maxBoardPins = 7;

  List<Map<String, dynamic>> get pinnedThoughts {
    final list = _thoughts.where(isPinned).toList();
    list.sort((a, b) {
      final posA = (a['board_position'] as num?)?.toInt() ?? 999;
      final posB = (b['board_position'] as num?)?.toInt() ?? 999;
      if (posA != posB) return posA.compareTo(posB);
      final pinAtA = (a['pinned_at'] as num?)?.toInt() ?? 0;
      final pinAtB = (b['pinned_at'] as num?)?.toInt() ?? 0;
      return pinAtA.compareTo(pinAtB);
    });
    if (list.length > maxBoardPins) {
      return list.sublist(0, maxBoardPins);
    }
    return list;
  }

  int get pinnedCount => pinnedThoughts.length;
  bool get isBoardFull => pinnedCount >= maxBoardPins;

  Future<bool> pinToBoard(String id, {int? position}) async {
    final existing = _thoughts.firstWhere((t) => t['id'] == id, orElse: () => {});
    if (existing.isEmpty) return false;
    if (isPinned(existing)) return true;
    if (isBoardFull) return false;

    final deviceId = _settings != null ? SyncIdentity.getDeviceId(_settings!) : DatabaseHelper.currentDeviceId;
    int targetSlot = position ?? -1;
    if (targetSlot < 0 || targetSlot >= maxBoardPins) {
      final occupied = pinnedThoughts
          .map((t) => (t['board_position'] as num?)?.toInt() ?? -1)
          .where((p) => p >= 0 && p < maxBoardPins)
          .toSet();
      for (int i = 0; i < maxBoardPins; i++) {
        if (!occupied.contains(i)) {
          targetSlot = i;
          break;
        }
      }
      if (targetSlot < 0) targetSlot = 0;
    }

    await DatabaseHelper.instance.pinThought(id, position: targetSlot, deviceId: deviceId);
    await loadThoughts();
    return true;
  }

  Future<void> unpinFromBoard(String id) async {
    final deviceId = _settings != null ? SyncIdentity.getDeviceId(_settings!) : DatabaseHelper.currentDeviceId;
    await DatabaseHelper.instance.unpinThought(id, deviceId: deviceId);
    await loadThoughts();
  }

  Future<bool> togglePinToBoard(String id) async {
    final existing = _thoughts.firstWhere((t) => t['id'] == id, orElse: () => {});
    if (existing.isEmpty) return false;
    if (isPinned(existing)) {
      await unpinFromBoard(id);
      return false;
    } else {
      return await pinToBoard(id);
    }
  }

  Future<void> reorderBoard(int oldIndex, int newIndex) async {
    final current = List<Map<String, dynamic>>.from(pinnedThoughts);
    if (oldIndex < 0 || oldIndex >= current.length || newIndex < 0 || newIndex >= current.length) return;

    final item = current.removeAt(oldIndex);
    current.insert(newIndex, item);

    final positions = <String, int>{};
    for (int i = 0; i < current.length; i++) {
      positions[current[i]['id'] as String] = i;
    }

    final deviceId = _settings != null ? SyncIdentity.getDeviceId(_settings!) : DatabaseHelper.currentDeviceId;
    await DatabaseHelper.instance.updateBoardPositions(positions, deviceId: deviceId);
    await loadThoughts();
  }

  Future<Map<String, dynamic>> copyThought(String id) async {
    final existing = _thoughts.firstWhere((t) => t['id'] == id, orElse: () => {});
    if (existing.isEmpty) throw Exception('Thought not found');

    final content = existing['content'] as String? ?? '';
    final bucket = existing['bucket'] as String?;
    final newThought = await addThought(
      content,
      existing['type'] as String? ?? 'thought',
      tags: existing['tags'] as String? ?? '',
      bucket: bucket,
    );
    final title = existing['title'] as String? ?? '';
    if (title.isNotEmpty) {
      await updateThoughtTitle(newThought['id'] as String, '$title (copy)', titleSource: 'user');
    }
    await loadThoughts();
    return newThought;
  }

  Future<SplitResult> splitThought(String id, List<String> tasks, {bool keepOriginal = false}) async {
    final existing = _thoughts.firstWhere((t) => t['id'] == id, orElse: () => {});
    final bucket = existing['bucket'] as String?;
    int created = 0;
    int pinned = 0;

    for (final task in tasks) {
      final trimmed = task.trim();
      if (trimmed.isEmpty) continue;
      final newT = await addThought(
        trimmed,
        'task',
        tags: 'split-from-$id',
        bucket: bucket,
      );
      created++;
      if (!isBoardFull) {
        final success = await pinToBoard(newT['id'] as String);
        if (success) pinned++;
      }
    }

    if (!keepOriginal) {
      // Remove original from board and archive to trash
      await unpinFromBoard(id);
      await moveToTrash(id);
    } else {
      // Keep original safely in its bucket, unpin from board to make room for split tasks
      await unpinFromBoard(id);
    }

    await loadThoughts();
    return SplitResult(
      createdCount: created,
      pinnedCount: pinned,
      bucketName: bucket,
    );
  }

  /// Merges duplicate ideas, keeping the designated winner and deleting duplicates (Section 4)
  Future<void> mergeDuplicates(String keepId, List<String> duplicateIds) async {
    for (final id in duplicateIds) {
      if (id != keepId) {
        await DatabaseHelper.instance.deleteThought(id);
      }
    }
    await loadAll();
  }
}
