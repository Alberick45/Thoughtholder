import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';
import '../utils/app_logger.dart';
import 'economy_config.dart';

class RewardEvent {
  final int xpEarned;
  final int coinsEarned;
  final bool dailyGoalReached;
  final bool leveledUp;
  final int level;
  final String? unlockName;

  const RewardEvent({
    this.xpEarned = 0,
    this.coinsEarned = 0,
    this.dailyGoalReached = false,
    this.leveledUp = false,
    required this.level,
    this.unlockName,
  });
}

class LevelReward {
  final int level;
  final String name;
  final String type; // cosmetic_title, note_color, pin_style
  final String description;
  final int coinCost;

  const LevelReward({
    required this.level,
    required this.name,
    required this.type,
    required this.description,
    required this.coinCost,
  });
}

/// Service managing Daily Goal, XP, Levels, Streaks, and Coins.
class GamificationService extends ChangeNotifier {
  static final GamificationService instance = GamificationService._();
  GamificationService._();

  static const int dailyGoalCoinReward = EconomyConfig.dailyGoalCoinReward;
  static const int levelUpCoinReward = EconomyConfig.levelUpCoinReward;

  static const List<LevelReward> levelRewards = [
    LevelReward(level: 1, name: 'Starter', type: 'cosmetic_title', description: 'Default title', coinCost: 0),
    LevelReward(level: 2, name: 'Focused', type: 'cosmetic_title', description: 'Focused title badge', coinCost: 20),
    LevelReward(level: 3, name: 'Lemon Note', type: 'note_color', description: 'Unlock lemon note color', coinCost: 30),
    LevelReward(level: 4, name: 'Mint Note', type: 'note_color', description: 'Unlock mint note color', coinCost: 30),
    LevelReward(level: 5, name: 'Gold Pin', type: 'pin_style', description: 'Unlock gold pin style', coinCost: 50),
    LevelReward(level: 6, name: 'Sky Note', type: 'note_color', description: 'Unlock sky note color', coinCost: 40),
    LevelReward(level: 7, name: 'Planner', type: 'cosmetic_title', description: 'Planner title badge', coinCost: 60),
    LevelReward(level: 8, name: 'Lavender Note', type: 'note_color', description: 'Unlock lavender note color', coinCost: 50),
    LevelReward(level: 9, name: 'Silver Pin', type: 'pin_style', description: 'Unlock silver pin style', coinCost: 75),
    LevelReward(level: 10, name: 'Master Finisher', type: 'cosmetic_title', description: 'Master Finisher title', coinCost: 100),
  ];

  int _totalXp = 0;
  int _currentGoal = 4;
  bool _isGoalFixed = false;
  int _fixedGoalValue = 4;
  int _consecutiveGoalHitDays = 0;
  int _streak = 0;
  int _restDaysUsedThisWeek = 0;
  String _weekIdentifier = '';
  Set<String> _todayCompletedThoughtIds = {};
  int _todayXpEarned = 0;
  bool _initialized = false;
  bool _mainGoalCompletedToday = false;
  static const String _mainGoalMetaKey = 'main_goal_completed_date';
  int _coinBalance = 0;
  final Set<String> _coinAwardsGranted = {};

  int get totalXp => _totalXp;
  int get currentGoal => _isGoalFixed ? _fixedGoalValue : _currentGoal;
  bool get isGoalFixed => _isGoalFixed;
  int get fixedGoalValue => _fixedGoalValue;
  int get streak => _streak;
  int get todayCompletedCount => _todayCompletedThoughtIds.length;
  int get todayXpEarned => _todayXpEarned;
  bool get isMainGoalCompletedToday => _mainGoalCompletedToday;
  bool get isDailyGoalReached =>
      todayCompletedCount >= currentGoal || _mainGoalCompletedToday;
  int get restDaysUsedThisWeek => _restDaysUsedThisWeek;
  int get coinBalance => _coinBalance;

  RewardEvent? _pendingRewardEvent;
  RewardEvent? consumePendingRewardEvent() {
    final e = _pendingRewardEvent;
    _pendingRewardEvent = null;
    return e;
  }

  void queueRewardEvent(RewardEvent event) {
    _pendingRewardEvent = event;
  }

  LevelReward? rewardForLevel(int lvl) {
    for (final r in levelRewards) {
      if (r.level == lvl) return r;
    }
    return null;
  }

  bool isRewardUnlocked(int lvl) => level >= lvl;

  static const String _ownedUnlocksKey = 'owned_unlocks';
  static const String _selectedTitleKey = 'selected_title';
  static const String _selectedNoteColorKey = 'selected_note_color';
  static const String _selectedPinStyleKey = 'selected_pin_style';

  Set<String> _ownedUnlocks = {'Starter'};
  String _selectedTitle = 'Starter';
  String _selectedNoteColor = 'default';
  String _selectedPinStyle = 'default';

  Set<String> get ownedUnlocks => _ownedUnlocks;
  String get selectedTitle => _selectedTitle;
  String get selectedNoteColor => _selectedNoteColor;
  String get selectedPinStyle => _selectedPinStyle;

  bool isUnlockOwned(String name) => _ownedUnlocks.contains(name);
  bool canUseUnlock(String name) {
    final r = levelRewards.where((e) => e.name == name).toList();
    if (r.isEmpty) return false;
    return isRewardUnlocked(r.first.level) && isUnlockOwned(name);
  }

  Future<void> _loadUnlocks(Map<String, String> meta) async {
    _ownedUnlocks = {'Starter'};
    final raw = meta[_ownedUnlocksKey] ?? '';
    if (raw.isNotEmpty) {
      try { final d = jsonDecode(raw); if (d is List) _ownedUnlocks.addAll(d.map((e)=>e.toString())); } catch (_) {}
    }
    for (final r in levelRewards) { if (level >= r.level) _ownedUnlocks.add(r.name); }
    _selectedTitle = meta[_selectedTitleKey] ?? 'Starter';
    _selectedNoteColor = meta[_selectedNoteColorKey] ?? 'default';
    _selectedPinStyle = meta[_selectedPinStyleKey] ?? 'default';
    if (!canUseUnlock(_selectedTitle)) _selectedTitle = 'Starter';
  }

  Future<void> selectUnlock(String name) async {
    final r = levelRewards.where((e)=>e.name==name).toList();
    if (r.isEmpty || !canUseUnlock(name)) return;
    final reward = r.first;
    if (reward.type == 'cosmetic_title') _selectedTitle = name;
    if (reward.type == 'note_color') _selectedNoteColor = name;
    if (reward.type == 'pin_style') _selectedPinStyle = name;
    await _saveMetaKey(_selectedTitleKey, _selectedTitle);
    await _saveMetaKey(_selectedNoteColorKey, _selectedNoteColor);
    await _saveMetaKey(_selectedPinStyleKey, _selectedPinStyle);
    await _saveMetaKey(_ownedUnlocksKey, jsonEncode(_ownedUnlocks.toList()));
    notifyListeners();
  }

  /// Calculates level based on XP.
  /// Level 1: 0-50 XP
  /// Level 2: 51-150 XP (+100)
  /// Level 3: 151-300 XP (+150)
  /// Level 4: 301-500 XP (+200)
  /// Level N: requires 50 * N XP to complete
  int get level {
    int xp = _totalXp;
    int lvl = 1;
    while (true) {
      final req = xpRequiredForLevel(lvl);
      if (xp >= req) {
        xp -= req;
        lvl++;
      } else {
        break;
      }
    }
    return lvl;
  }

  /// XP required to advance from [lvl] to [lvl + 1].
  int xpRequiredForLevel(int lvl) {
    return 50 * lvl;
  }

  /// Current progress towards the next level [0.0 to 1.0].
  double get levelProgress {
    int xp = _totalXp;
    int lvl = 1;
    while (true) {
      final req = xpRequiredForLevel(lvl);
      if (xp >= req) {
        xp -= req;
        lvl++;
      } else {
        return (xp / req).clamp(0.0, 1.0);
      }
    }
  }

  /// XP earned within the current level.
  int get currentLevelXp {
    int xp = _totalXp;
    int lvl = 1;
    while (true) {
      final req = xpRequiredForLevel(lvl);
      if (xp >= req) {
        xp -= req;
        lvl++;
      } else {
        return xp;
      }
    }
  }

  /// Total XP needed for next level.
  int get nextLevelTargetXp => xpRequiredForLevel(level);

  String _getTodayString() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  String _getWeekIdentifier(DateTime dt) {
    // Determine Monday-based week identifier: "YYYY-Wxx"
    final dayOfWeek = dt.weekday; // 1 = Monday
    final monday = dt.subtract(Duration(days: dayOfWeek - 1));
    return "${monday.year}-${monday.month}-${monday.day}";
  }

  Future<void> init() async {
    if (_initialized) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final metaRows = await db.query('gamification_meta');
      final meta = <String, String>{};
      for (final r in metaRows) {
        meta[r['key'] as String] = r['value']?.toString() ?? '';
      }

      _totalXp = int.tryParse(meta['total_xp'] ?? '') ?? 0;
      _currentGoal = (int.tryParse(meta['current_goal'] ?? '') ?? 4).clamp(1, 20);
      _isGoalFixed = meta['is_goal_fixed'] == 'true';
      _fixedGoalValue = (int.tryParse(meta['fixed_goal_value'] ?? '') ?? 4).clamp(1, 20);
      _consecutiveGoalHitDays = int.tryParse(meta['consecutive_goal_hit_days'] ?? '') ?? 0;
      _streak = int.tryParse(meta['streak'] ?? '') ?? 0;
      _restDaysUsedThisWeek = int.tryParse(meta['rest_days_used_this_week'] ?? '') ?? 0;
      _weekIdentifier = meta['week_identifier'] ?? '';
      _mainGoalCompletedToday = meta[_mainGoalMetaKey] == _getTodayString();
      _coinBalance = await DatabaseHelper.instance.fetchCoinBalance(db: db);
      _coinAwardsGranted.clear();
      final awardsRaw = meta['coin_awards_granted'] ?? '';
      if (awardsRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(awardsRaw);
          if (decoded is List) {
            _coinAwardsGranted.addAll(decoded.map((e) => e.toString()));
          }
        } catch (_) {}
      }
      await _loadUnlocks(meta);

      final now = DateTime.now();
      final currentWeek = _getWeekIdentifier(now);
      if (_weekIdentifier != currentWeek) {
        _weekIdentifier = currentWeek;
        _restDaysUsedThisWeek = 0;
        await _saveMetaKey('week_identifier', _weekIdentifier);
        await _saveMetaKey('rest_days_used_this_week', '0');
      }

      final todayStr = _getTodayString();
      final todayRows = await db.query(
        'daily_goals',
        where: 'date = ?',
        whereArgs: [todayStr],
      );

      if (todayRows.isNotEmpty) {
        final row = todayRows.first;
        final idsStr = row['completed_thought_ids']?.toString() ?? '';
        if (idsStr.isNotEmpty) {
          try {
            final decoded = jsonDecode(idsStr);
            if (decoded is List) {
              _todayCompletedThoughtIds = decoded.map((e) => e.toString()).toSet();
            }
          } catch (_) {}
        }
        _todayXpEarned = (row['xp_earned'] as num?)?.toInt() ?? 0;
      } else {
        _todayCompletedThoughtIds = {};
        _todayXpEarned = 0;
        // Check yesterday's goal to maintain or update streak
        await _checkYesterdayStreak(db, now);
      }

      _initialized = true;
      notifyListeners();
    } catch (e, stack) {
      AppLogger.error('GamificationService', 'Init error: $e\n$stack');
    }
  }

  Future<void> _checkYesterdayStreak(Database db, DateTime now) async {
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";
    final rows = await db.query('daily_goals', where: 'date = ?', whereArgs: [yesterdayStr]);

    if (rows.isNotEmpty) {
      final yRow = rows.first;
      final reached = (yRow['goal_reached'] as int? ?? 0) == 1;
      if (!reached) {
        // Missed yesterday - check if rest day is available (1 rest day per week)
        if (_restDaysUsedThisWeek < 1) {
          _restDaysUsedThisWeek++;
          await _saveMetaKey('rest_days_used_this_week', '$_restDaysUsedThisWeek');
          await db.update('daily_goals', {'rest_day': 1}, where: 'date = ?', whereArgs: [yesterdayStr]);
          // Streak is preserved!
        } else {
          // Streak resets
          _streak = 0;
          _consecutiveGoalHitDays = 0;
          await _saveMetaKey('streak', '0');
          await _saveMetaKey('consecutive_goal_hit_days', '0');
        }
      }
    }
  }

  Future<void> _saveMetaKey(String key, String value) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.insert(
        'gamification_meta',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<void> _grantCoinsOnce(String awardKey, int amount, String reason) async {
    if (amount <= 0 || _coinAwardsGranted.contains(awardKey)) return;
    _coinBalance = await DatabaseHelper.instance.awardCoins(
      amount: amount,
      reason: reason,
      refId: awardKey,
    );
    _coinAwardsGranted.add(awardKey);
    final trimmed = _coinAwardsGranted.toList()
      ..sort()
      ..removeWhere((_) => false);
    // keep recent keys to avoid unbounded growth
    final keep = trimmed.length > 200 ? trimmed.sublist(trimmed.length - 200) : trimmed;
    _coinAwardsGranted
      ..clear()
      ..addAll(keep);
    await _saveMetaKey('coin_awards_granted', jsonEncode(keep));
  }

  Future<bool> spendCoins(int amount, String reason, {String? refId}) async {
    await init();
    try {
      _coinBalance = await DatabaseHelper.instance.spendCoins(
        amount: amount,
        reason: reason,
        refId: refId,
      );
      notifyListeners();
      return true;
    } catch (_) {
      _coinBalance = await DatabaseHelper.instance.fetchCoinBalance();
      notifyListeners();
      return false;
    }
  }

  /// Sets daily goal target. Part 1: user-settable per-day target (1-20).
  Future<void> setGoalSettings({required bool isFixed, required int goalValue}) async {
    _isGoalFixed = isFixed;
    _fixedGoalValue = goalValue.clamp(1, 20);
    _currentGoal = goalValue.clamp(1, 20);
    await _saveMetaKey('is_goal_fixed', '$_isGoalFixed');
    await _saveMetaKey('fixed_goal_value', '$_fixedGoalValue');
    await _saveMetaKey('current_goal', '$_currentGoal');
    notifyListeners();
  }

  /// Handles completion of a pinned task. Returns XP awarded.
  Future<int> onPinnedTaskCompleted(Map<String, dynamic> thought) async {
    final event = await onPinnedTaskCompletedDetailed(thought);
    return event.xpEarned;
  }

  Future<RewardEvent> onPinnedTaskCompletedDetailed(
    Map<String, dynamic> thought,
  ) async {
    await init();
    final thoughtId = thought['id']?.toString() ?? '';
    if (thoughtId.isEmpty) return RewardEvent(level: level);

    final createdAtRaw = thought['created_at'];
    final createdAt = createdAtRaw is num
        ? createdAtRaw.toInt()
        : (int.tryParse(createdAtRaw?.toString() ?? '') ?? 0);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final isWithinMinute = (nowMs - createdAt) < 60 * 1000;

    int xpToAdd = 0;
    if (!isWithinMinute) {
      final timeVal = (thought['time_val']?.toString() ?? '').toLowerCase();
      if (timeVal == 'big') {
        xpToAdd = 20;
      } else if (timeVal == 'quick') {
        xpToAdd = 5;
      } else {
        xpToAdd = 10;
      }
    }

    final prevLevel = level;
    _todayCompletedThoughtIds.add(thoughtId);
    final wasGoalReachedBefore = _mainGoalCompletedToday ||
        ((_todayCompletedThoughtIds.length - 1) >= currentGoal);
    final isGoalReachedNow = _mainGoalCompletedToday ||
        (_todayCompletedThoughtIds.length >= currentGoal);
    var dailyGoalJustReached = false;
    var coinsEarned = 0;

    if (!wasGoalReachedBefore && isGoalReachedNow) {
      dailyGoalJustReached = true;
      xpToAdd += 10;
      _consecutiveGoalHitDays++;
      _streak++;
      await _saveMetaKey('streak', '$_streak');
      await _saveMetaKey(
        'consecutive_goal_hit_days',
        '$_consecutiveGoalHitDays',
      );
      if (!_isGoalFixed && _consecutiveGoalHitDays >= 5 && _currentGoal < 20) {
        _currentGoal = math.min(20, _currentGoal + 1);
        _consecutiveGoalHitDays = 0;
        await _saveMetaKey('current_goal', '$_currentGoal');
        await _saveMetaKey('fixed_goal_value', '$_currentGoal');
        await _saveMetaKey('consecutive_goal_hit_days', '0');
      }
    }

    _totalXp += xpToAdd;
    _todayXpEarned += xpToAdd;
    await _saveMetaKey('total_xp', '$_totalXp');

    final newLevel = level;
    final leveledUp = newLevel > prevLevel;
    final todayStr = _getTodayString();
    if (dailyGoalJustReached) {
      await _grantCoinsOnce(
        'daily_goal:$todayStr',
        dailyGoalCoinReward,
        'daily_goal_complete',
      );
      coinsEarned += dailyGoalCoinReward;
    }
    if (leveledUp) {
      await _grantCoinsOnce(
        'level_up:$newLevel:$todayStr',
        levelUpCoinReward,
        'level_up',
      );
      coinsEarned += levelUpCoinReward;
    }

    try {
      final db = await DatabaseHelper.instance.database;
      await db.insert(
        'daily_goals',
        {
          'date': todayStr,
          'tasks_completed': _todayCompletedThoughtIds.length,
          'goal': currentGoal,
          'xp_earned': _todayXpEarned,
          'goal_reached': isGoalReachedNow ? 1 : 0,
          'completed_thought_ids':
              jsonEncode(_todayCompletedThoughtIds.toList()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      AppLogger.error('GamificationService', 'Failed saving daily progress: $e');
    }

    final event = RewardEvent(
      xpEarned: xpToAdd,
      coinsEarned: coinsEarned,
      dailyGoalReached: dailyGoalJustReached,
      leveledUp: leveledUp,
      level: newLevel,
      unlockName: leveledUp ? rewardForLevel(newLevel)?.name : null,
    );
    notifyListeners();
    return event;
  }

  /// Completing all Main items for the period counts as the daily goal.
  Future<int> onMainGoalCompleted() async {
    final event = await onMainGoalCompletedDetailed();
    return event.xpEarned;
  }

  Future<RewardEvent> onMainGoalCompletedDetailed() async {
    await init();
    final todayStr = _getTodayString();
    if (_mainGoalCompletedToday) return RewardEvent(level: level);
    _mainGoalCompletedToday = true;
    await _saveMetaKey(_mainGoalMetaKey, todayStr);

    final prevLevel = level;
    int xpAdded = 0;
    var dailyGoalJustReached = false;
    var coinsEarned = 0;
    final wasGoalReachedBefore = todayCompletedCount >= currentGoal;
    if (!wasGoalReachedBefore) {
      dailyGoalJustReached = true;
      xpAdded = 10;
      _totalXp += 10;
      _todayXpEarned += 10;
      _consecutiveGoalHitDays++;
      _streak++;
      await _saveMetaKey('streak', '$_streak');
      await _saveMetaKey(
        'consecutive_goal_hit_days',
        '$_consecutiveGoalHitDays',
      );
      await _saveMetaKey('total_xp', '$_totalXp');
    }

    final newLevel = level;
    final leveledUp = newLevel > prevLevel;
    if (dailyGoalJustReached) {
      await _grantCoinsOnce(
        'daily_goal:$todayStr',
        dailyGoalCoinReward,
        'daily_goal_complete',
      );
      coinsEarned += dailyGoalCoinReward;
    }
    if (leveledUp) {
      await _grantCoinsOnce(
        'level_up:$newLevel:$todayStr',
        levelUpCoinReward,
        'level_up',
      );
      coinsEarned += levelUpCoinReward;
      final reward = rewardForLevel(newLevel);
      if (reward != null) { _ownedUnlocks.add(reward.name); await _saveMetaKey(_ownedUnlocksKey, jsonEncode(_ownedUnlocks.toList())); }
    }

    try {
      final db = await DatabaseHelper.instance.database;
      await db.insert(
        'daily_goals',
        {
          'date': todayStr,
          'tasks_completed': _todayCompletedThoughtIds.length,
          'goal': currentGoal,
          'xp_earned': _todayXpEarned,
          'goal_reached': 1,
          'completed_thought_ids':
              jsonEncode(_todayCompletedThoughtIds.toList()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      AppLogger.error('GamificationService', 'Failed saving main goal completion: $e');
    }

    final event = RewardEvent(
      xpEarned: xpAdded,
      coinsEarned: coinsEarned,
      dailyGoalReached: dailyGoalJustReached,
      leveledUp: leveledUp,
      level: newLevel,
      unlockName: leveledUp ? rewardForLevel(newLevel)?.name : null,
    );
    notifyListeners();
    return event;
  }

  /// Summary string for end-of-day or completion toast: e.g. "4/4 done, +55 XP, streak 6"
  String getSummaryString() {
    return "$todayCompletedCount/$currentGoal done, +$_todayXpEarned XP, streak $streak";
  }
}

