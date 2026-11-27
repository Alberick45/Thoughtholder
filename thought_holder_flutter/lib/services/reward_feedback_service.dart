import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../settings_service.dart';
import '../sound_service.dart';
import '../utils/global_error_handler.dart';
import 'gamification_service.dart';

class RewardFeedbackService {
  static String _lastDailyGoalDate = '';

  static void _log(String msg) {
    debugPrint('[RewardFeedback] $msg');
  }

  static BuildContext? _rootContext(BuildContext? fallback) {
    final ctx = GlobalErrorHandler.navigatorKey.currentContext ?? fallback;
    _log('rootContext=${ctx != null} fallbackMounted=${fallback?.mounted ?? false}');
    return ctx;
  }

  static bool _reduce(SettingsService? settings, BuildContext? context) {
    if (settings?.reduceAnimations == true) return true;
    if (context != null) {
      return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    }
    return false;
  }

  static void haptic(SettingsService? settings, {bool heavy = false}) {
    if (settings?.hapticsEnabled == false) return;
    if (heavy) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  static void showTaskReward(
    BuildContext context, {
    required int xp,
    required SettingsService settings,
  }) {
    _log('showTaskReward xp=$xp');
    if (xp <= 0) {
      _log('showTaskReward skipped: xp<=0');
      return;
    }
    haptic(settings);
    SoundService.instance.play(SoundEvent.done, settings: settings);
    final root = _rootContext(context);
    final reduce = _reduce(settings, root);
    final overlay = root != null ? Overlay.maybeOf(root) : Overlay.maybeOf(context);
    _log('showTaskReward overlay=${overlay != null} reduce=$reduce');
    if (overlay == null) {
      _log('showTaskReward early-return: no overlay');
      return;
    }
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FloatingXp(xp: xp, reduce: reduce, onDone: () {
        _log('showTaskReward float removed');
        entry.remove();
      }),
    );
    overlay.insert(entry);
    _log('showTaskReward float inserted');
  }

  static Future<void> maybeShowDailyGoal(
    BuildContext context, {
    required GamificationService game,
    required SettingsService settings,
    bool ignoreDateGuard = false,
  }) async {
    final today = DateTime.now();
    final key = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final persisted = settings.lastDailyGoalCelebratedDate == key;
    final inMemory = _lastDailyGoalDate == key;
    _log('maybeShowDailyGoal key=$key persisted=$persisted inMemory=$inMemory reached=${game.isDailyGoalReached} ignoreDateGuard=$ignoreDateGuard');
    if (!ignoreDateGuard && (persisted || inMemory)) {
      _log('maybeShowDailyGoal early-return: date guard');
      return;
    }
    if (!game.isDailyGoalReached && !ignoreDateGuard) {
      _log('maybeShowDailyGoal early-return: goal not reached');
      return;
    }
    if (!ignoreDateGuard) {
      _lastDailyGoalDate = key;
      await settings.setLastDailyGoalCelebratedDate(key);
    }
    haptic(settings, heavy: true);
    SoundService.instance.play(SoundEvent.celebrate, settings: settings);
    final root = _rootContext(context);
    if (root == null) {
      _log('maybeShowDailyGoal early-return: no root context');
      return;
    }
    final reduce = _reduce(settings, root);
    _log('maybeShowDailyGoal showing dialog reduce=$reduce');
    await showGeneralDialog<void>(
      context: root,
      barrierDismissible: true,
      barrierLabel: 'Daily goal complete',
      barrierColor: Colors.black54,
      transitionDuration: Duration(milliseconds: reduce ? 0 : 250),
      pageBuilder: (ctx, _, __) => _DailyGoalDialog(game: game, reduce: reduce),
    );
    _log('maybeShowDailyGoal dialog closed');
  }

  static Future<void> previewTaskReward(BuildContext context, {required SettingsService settings}) async {
    showTaskReward(context, xp: 20, settings: settings);
  }

  static Future<void> previewDailyGoal(BuildContext context, {required GamificationService game, required SettingsService settings}) async {
    await maybeShowDailyGoal(context, game: game, settings: settings, ignoreDateGuard: true);
  }

  static Future<void> previewLevelUp(BuildContext context, {required SettingsService settings}) async {
    final event = RewardEvent(xpEarned: 0, coinsEarned: 20, leveledUp: true, level: gameLevelForPreview(settings), unlockName: 'Preview Unlock');
    await maybeShowLevelUp(context, event: event, settings: settings);
  }

  static int gameLevelForPreview(SettingsService _) => GamificationService.instance.level;

  static void resetDailyGoalCelebrationMemory() {
    _lastDailyGoalDate = '';
  }

  static Future<void> maybeShowLevelUp(
    BuildContext context, {
    required RewardEvent event,
    required SettingsService settings,
  }) async {
    _log('maybeShowLevelUp leveledUp=${event.leveledUp} level=${event.level}');
    if (!event.leveledUp) {
      _log('maybeShowLevelUp early-return: not leveledUp');
      return;
    }
    haptic(settings, heavy: true);
    SoundService.instance.play(SoundEvent.celebrate, settings: settings);
    final root = _rootContext(context);
    if (root == null) {
      _log('maybeShowLevelUp early-return: no root context');
      return;
    }
    final reduce = _reduce(settings, root);
    await showGeneralDialog<void>(
      context: root,
      barrierDismissible: true,
      barrierLabel: 'Level up',
      barrierColor: Colors.black54,
      transitionDuration: Duration(milliseconds: reduce ? 0 : 250),
      pageBuilder: (ctx, _, __) => _LevelUpDialog(event: event, reduce: reduce),
    );
    _log('maybeShowLevelUp dialog closed');
  }
}

class _FloatingXp extends StatefulWidget {
  final int xp;
  final bool reduce;
  final VoidCallback onDone;
  const _FloatingXp({required this.xp, required this.reduce, required this.onDone});
  @override
  State<_FloatingXp> createState() => _FloatingXpState();
}

class _FloatingXpState extends State<_FloatingXp> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.reduce ? 350 : 900),
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = _c.value;
            return Align(
              alignment: Alignment(0, 0.55 - (widget.reduce ? 0.05 : 0.25) * t),
              child: Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E222B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFFD54F)),
                  ),
                  child: Text(
                    '+${widget.xp} XP',
                    style: appFont(color: const Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DailyGoalDialog extends StatelessWidget {
  final GamificationService game;
  final bool reduce;
  const _DailyGoalDialog({required this.game, required this.reduce});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E222B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFD54F)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!reduce) const _ConfettiBurst(),
              Text('Daily goal complete', style: appFont(color: const Color(0xFFFFD54F), fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('+${GamificationService.dailyGoalCoinReward} coins  ?  +10 goal bonus XP', style: appFont(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 8),
              Text('Streak: ${game.streak} day${game.streak == 1 ? '' : 's'}', style: appFont(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 8),
              Text('Next unlock: Level ${game.level + 1} ${game.rewardForLevel(game.level + 1)?.name ?? ''}', style: appFont(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Nice')),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelUpDialog extends StatelessWidget {
  final RewardEvent event;
  final bool reduce;
  const _LevelUpDialog({required this.event, required this.reduce});

  @override
  Widget build(BuildContext context) {
    final unlock = GamificationService.instance.rewardForLevel(event.level);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E222B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFD54F)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!reduce) const _ConfettiBurst(),
              Text('Level ${event.level}!', style: appFont(color: const Color(0xFFFFD54F), fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(unlock != null ? 'Unlocked: ${unlock.name}' : 'New level reached', style: appFont(color: Colors.white, fontSize: 15)),
              if (unlock != null) ...[
                const SizedBox(height: 4),
                Text(unlock.description, style: appFont(color: Colors.white70, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Awesome')),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst();
  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
  final _rng = math.Random();
  late final List<_Particle> _p = List.generate(24, (_) => _Particle(
    dx: (_rng.nextDouble() - 0.5) * 180,
    dy: 60 + _rng.nextDouble() * 140,
    color: [const Color(0xFFFFD54F), Colors.white, const Color(0xFF7DD3FC), const Color(0xFFA7F3D0)][_rng.nextInt(4)],
    size: 4 + _rng.nextDouble() * 5,
  ));
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      width: 220,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(painter: _ConfettiPainter(_p, _c.value)),
      ),
    );
  }
}

class _Particle { final double dx, dy, size; final Color color; _Particle({required this.dx, required this.dy, required this.color, required this.size}); }
class _ConfettiPainter extends CustomPainter {
  final List<_Particle> p; final double t;
  _ConfettiPainter(this.p, this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 10);
    for (final e in p) {
      final paint = Paint()..color = e.color.withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.drawCircle(center + Offset(e.dx * t, e.dy * t), e.size, paint);
    }
  }
  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
