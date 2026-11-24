import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';
import '../utils/app_logger.dart';

/// Service managing Daily Goal, XP, Levels, and Streaks for ThoughtHolder.
class GamificationService extends ChangeNotifier {
  static final GamificationService instance = GamificationService._();
  GamificationService._();

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
      _currentGoal = (int.tryParse(meta['current_goal'] ?? '') ?? 4).clamp(4, 8);
      _isGoalFixed = meta['is_goal_fixed'] == 'true';
      _fixedGoalValue = (int.tryParse(meta['fixed_goal_value'] ?? '') ?? 4).clamp(4, 8);
      _consecutiveGoalHitDays = int.tryParse(meta['consecutive_goal_hit_days'] ?? '') ?? 0;
      _streak = int.tryParse(meta['streak'] ?? '') ?? 0;
      _restDaysUsedThisWeek = int.tryParse(meta['rest_days_used_this_week'] ?? '') ?? 0;
      _weekIdentifier = meta['week_identifier'] ?? '';
      _mainGoalCompletedToday = meta[_mainGoalMetaKey] == _getTodayString();

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

  /// Sets fixed daily goal or allows auto-progression.
  Future<void> setGoalSettings({required bool isFixed, required int goalValue}) async {
    _isGoalFixed = isFixed;
    _fixedGoalValue = goalValue.clamp(4, 8);
    if (!isFixed) {
      _currentGoal = goalValue.clamp(4, 8);
    }
    await _saveMetaKey('is_goal_fixed', '$_isGoalFixed');
    await _saveMetaKey('fixed_goal_value', '$_fixedGoalValue');
    await _saveMetaKey('current_goal', '$_currentGoal');
    notifyListeners();
  }

  /// Handles completion of a pinned task.
  /// Returns XP awarded, or 0 if created and finished within a minute.
  Future<int> onPinnedTaskCompleted(Map<String, dynamic> thought) async {
    await init();
    final thoughtId = thought['id']?.toString() ?? '';
    if (thoughtId.isEmpty) return 0;

    // Check anti-gaming: "A thought that was created and finished within a minute gives no XP."
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
        xpToAdd = 10; // Medium / default
      }
    }

    _todayCompletedThoughtIds.add(thoughtId);
    final wasGoalReachedBefore = _mainGoalCompletedToday ||
        ((_todayCompletedThoughtIds.length - 1) >= currentGoal);
    final isGoalReachedNow = _mainGoalCompletedToday ||
        (_todayCompletedThoughtIds.length >= currentGoal);

    // Bonus +10 XP when the daily goal is reached for the first time today
    if (!wasGoalReachedBefore && isGoalReachedNow) {
      xpToAdd += 10;
      _consecutiveGoalHitDays++;
      _streak++;
      await _saveMetaKey('streak', '$_streak');
      await _saveMetaKey('consecutive_goal_hit_days', '$_consecutiveGoalHitDays');

      // Check progression: "after 5 days in a row of hitting it, go from 4 to 5, up to 8"
      if (!_isGoalFixed && _consecutiveGoalHitDays >= 5 && _currentGoal < 8) {
        _currentGoal = math.min(8, _currentGoal + 1);
        _consecutiveGoalHitDays = 0; // reset for next tier
        await _saveMetaKey('current_goal', '$_currentGoal');
        await _saveMetaKey('consecutive_goal_hit_days', '0');
      }
    }

    _totalXp += xpToAdd;
    _todayXpEarned += xpToAdd;

    await _saveMetaKey('total_xp', '$_totalXp');

    // Persist today's daily record
    try {
      final db = await DatabaseHelper.instance.database;
      final todayStr = _getTodayString();
      await db.insert(
        'daily_goals',
        {
          'date': todayStr,
          'tasks_completed': _todayCompletedThoughtIds.length,
          'goal': currentGoal,
          'xp_earned': _todayXpEarned,
          'goal_reached': isGoalReachedNow ? 1 : 0,
          'completed_thought_ids': jsonEncode(_todayCompletedThoughtIds.toList()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      AppLogger.error('GamificationService', 'Failed saving daily progress: $e');
    }

    notifyListeners();
    return xpToAdd;
  }

  /// Completing all Main items for the period counts as the daily goal in the existing game.
  Future<int> onMainGoalCompleted() async {
    await init();
    final todayStr = _getTodayString();
    if (_mainGoalCompletedToday) return 0;
    _mainGoalCompletedToday = true;
    await _saveMetaKey(_mainGoalMetaKey, todayStr);

    int xpAdded = 0;
    final wasGoalReachedBefore = todayCompletedCount >= currentGoal;
    if (!wasGoalReachedBefore) {
      xpAdded = 10;
      _totalXp += 10;
      _todayXpEarned += 10;
      _consecutiveGoalHitDays++;
      _streak++;

      await _saveMetaKey('streak', '$_streak');
      await _saveMetaKey('consecutive_goal_hit_days', '$_consecutiveGoalHitDays');
      await _saveMetaKey('total_xp', '$_totalXp');
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
          'completed_thought_ids': jsonEncode(_todayCompletedThoughtIds.toList()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      AppLogger.error('GamificationService', 'Failed saving main goal completion: $e');
    }

    notifyListeners();
    return xpAdded;
  }

  /// Summary string for end-of-day or completion toast: e.g. "4/4 done, +55 XP, streak 6"
  String getSummaryString() {
    return "$todayCompletedCount/$currentGoal done, +$_todayXpEarned XP, streak $streak";
  }
}

