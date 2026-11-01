import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:local_notifier/local_notifier.dart';
import 'desktop_manager.dart';
import 'navigation_service.dart';
import 'settings_service.dart';
import 'thought_provider.dart';

class NotificationService extends ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('com.thoughtholder.app/notifications');

  Timer? _schedulerTimer;
  NavigationNotifier? _navigation;
  ThoughtProvider? _provider;
  SettingsService? _settings;

  NotificationService() {
    if (!kIsWeb && Platform.isAndroid) {
      _channel.setMethodCallHandler(_handleNativeCall);
    } else if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      _initDesktopNotifications();
    }
    // Check every minute if a scheduled notification is due
    _schedulerTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkScheduledNudges();
    });
  }

  Future<void> _initDesktopNotifications() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await localNotifier.setup(
        appName: 'ThoughtHolder',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
    } catch (e) {
      debugPrint('[NotificationService] localNotifier.setup error: $e');
    }
  }

  void updateDependencies({
    required NavigationNotifier navigation,
    required ThoughtProvider provider,
    required SettingsService settings,
  }) {
    _navigation = navigation;
    _provider = provider;
    _settings = settings;

    // Sync quick capture notification state
    syncQuickCaptureNotification();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onNotificationTapped') {
      final route = call.arguments as String? ?? '';
      handleRoute(route);
    }
  }

  void handleRoute(String route) {
    if (_navigation == null) return;

    if (route.startsWith('thoughtholder://capture')) {
      _navigation?.goToCapture();
    } else if (route.startsWith('thoughtholder://starthere')) {
      final tapTarget = _settings?.startHereTapTarget ?? 'idea';
      if (tapTarget == 'capture') {
        _navigation?.goToCapture();
      } else {
        _navigation?.goToStream(subTab: 'sorted');
      }
    } else if (route.startsWith('thoughtholder://unsorted')) {
      _navigation?.goToStream(subTab: 'unsorted');
    } else if (route.startsWith('thoughtholder://snooze_1h')) {
      // Snooze by delaying next nudge check
      _settings?.recordAppActiveTime();
    } else if (route.startsWith('thoughtholder://not_now')) {
      // Dismiss
    }
  }

  // --- Quick Capture Notification ---
  Future<void> syncQuickCaptureNotification() async {
    final settings = _settings;
    if (settings == null) return;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('setQuickCapture', {
          'enabled': settings.quickCaptureNotification,
        });
      } catch (_) {}
    }
  }

  // --- Quiet Hours & 2-Hour Inactivity Verification ---
  bool isQuietHours(SettingsService settings) {
    return isInsideQuietHours(
      DateTime.now(),
      settings.quietHoursStart,
      settings.quietHoursEnd,
    );
  }

  bool isInsideQuietHours(
    DateTime now,
    String quietHoursStart,
    String quietHoursEnd,
  ) {
    final currentMinutes = now.hour * 60 + now.minute;

    final startParts = quietHoursStart.split(':');
    final endParts = quietHoursEnd.split(':');

    final startMinutes = (int.tryParse(startParts[0]) ?? 21) * 60 +
        (int.tryParse(startParts.length > 1 ? startParts[1] : '0') ?? 0);
    final endMinutes = (int.tryParse(endParts[0]) ?? 8) * 60 +
        (int.tryParse(endParts.length > 1 ? endParts[1] : '0') ?? 0);

    if (startMinutes > endMinutes) {
      // Overnight (e.g. 21:00 to 08:00)
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    } else {
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    }
  }

  bool wasAppOpenedInLastTwoHours(SettingsService settings) {
    return wasActiveInLastTwoHours(settings.lastAppActiveTime);
  }

  bool wasActiveInLastTwoHours(int lastActiveTime, {DateTime? now}) {
    if (lastActiveTime <= 0) return false;
    final current = now ?? DateTime.now();
    final diff = current.millisecondsSinceEpoch - lastActiveTime;
    return diff < const Duration(hours: 2).inMilliseconds;
  }

  // --- Start Here Nudge Logic (Decided at send time) ---
  Future<void> triggerStartHereNudge({bool isTest = false}) async {
    final settings = _settings;
    final provider = _provider;
    if (settings == null || provider == null) return;

    if (!isTest) {
      if (settings.startHereFrequency == 'off') return;
      if (isQuietHours(settings)) return;
      if (wasAppOpenedInLastTwoHours(settings)) return;
      if (settings.nudgesSentTodayCount >= 3) return;
    }

    final bestIdea = provider.bestNextThought;
    String title = 'Start here';
    String body = '';

    if (bestIdea != null) {
      final rawContent = (bestIdea['content'] as String? ?? '').trim();
      final cappedContent = rawContent.length > 100
          ? '${rawContent.substring(0, 97)}...'
          : rawContent;
      final reason = RankingEngine.getReason(bestIdea);
      body = '$cappedContent\n$reason';
    } else if (provider.unsortedThoughts.isNotEmpty) {
      body = 'Got 5 minutes? Sort 3 ideas.';
    } else if (isTest) {
      // For a test sample when no ideas exist yet:
      body = 'Emmanuel’s QR code\nQuick to finish · due soon';
    } else {
      // Nothing to show: send nothing (Section D)
      return;
    }

    final targetRoute = settings.startHereTapTarget == 'capture'
        ? 'thoughtholder://capture'
        : 'thoughtholder://starthere';

    // Android
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('showStartHereNudge', {
          'title': title,
          'body': body,
          'targetRoute': targetRoute,
          'showWordsOnLockScreen': settings.showWordsOnLockScreen,
        });
        if (!isTest) {
          await settings.incrementNudgesSentToday();
        }
      } catch (_) {}
    }

    // Windows / Desktop
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    if (isDesktop) {
      try {
        final notification = LocalNotification(
          identifier: 'start_here_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          body: body,
          actions: [
            LocalNotificationAction(text: 'Snooze 1 hour'),
            LocalNotificationAction(text: 'Not now'),
          ],
        );
        notification.onClick = () {
          handleRoute(targetRoute);
          DesktopManager.instance.showAndFocus();
        };
        notification.onClickAction = (actionIndex) {
          if (actionIndex == 0) {
            handleRoute('thoughtholder://snooze_1h');
          }
        };
        await notification.show();
        if (!isTest) {
          await settings.incrementNudgesSentToday();
        }
      } catch (e) {
        debugPrint('[NotificationService] Desktop notification error: $e');
      }
    }
  }

  // --- Gentle Capture Reminder Logic ---
  Future<void> triggerCaptureReminder({bool isTest = false}) async {
    final settings = _settings;
    if (settings == null) return;

    if (!isTest) {
      if (settings.captureReminderFrequency == 'off') return;
      if (isQuietHours(settings)) return;
      if (wasAppOpenedInLastTwoHours(settings)) return;
      if (settings.nudgesSentTodayCount >= 3) return;
    }

    // Android
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('showCaptureReminder');
        if (!isTest) {
          await settings.incrementNudgesSentToday();
        }
      } catch (_) {}
    }

    // Windows / Desktop
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    if (isDesktop) {
      try {
        final notification = LocalNotification(
          identifier:
              'capture_reminder_${DateTime.now().millisecondsSinceEpoch}',
          title: 'ThoughtHolder',
          body: 'Got a thought? Tap to capture.',
        );
        notification.onClick = () {
          handleRoute('thoughtholder://capture');
          DesktopManager.instance.showAndFocus();
        };
        await notification.show();
        if (!isTest) {
          await settings.incrementNudgesSentToday();
        }
      } catch (e) {
        debugPrint('[NotificationService] Desktop reminder error: $e');
      }
    }
  }

  // --- Scheduled Checker (Runs every minute) ---
  void _checkScheduledNudges() {
    final settings = _settings;
    if (settings == null) return;

    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // Start here times
    if (settings.startHereFrequency != 'off') {
      final limit = settings.startHereFrequency == 'once'
          ? 1
          : settings.startHereFrequency == 'twice'
              ? 2
              : 3;
      final times = settings.startHereTimes.take(limit).toList();
      if (times.contains(timeStr)) {
        triggerStartHereNudge();
      }
    }

    // Capture reminder times
    if (settings.captureReminderFrequency != 'off') {
      final limit = settings.captureReminderFrequency == 'once'
          ? 1
          : settings.captureReminderFrequency == 'twice'
              ? 2
              : 3;
      final times = settings.captureReminderTimes.take(limit).toList();
      if (times.contains(timeStr)) {
        triggerCaptureReminder();
      }
    }
  }

  // --- Send Me a Test (UPDATE 5 - Section F) ---
  Future<String> sendTestNotifications() async {
    final settings = _settings;
    if (settings == null) return 'Settings unavailable';

    final hasAnyEnabled = settings.quickCaptureNotification ||
        settings.startHereFrequency != 'off' ||
        settings.captureReminderFrequency != 'off';

    final List<String> sentList = [];

    if (hasAnyEnabled) {
      if (settings.quickCaptureNotification) {
        await syncQuickCaptureNotification();
        sentList.add('Quick Capture');
      }
      if (settings.startHereFrequency != 'off') {
        await triggerStartHereNudge(isTest: true);
        sentList.add('Start here');
      }
      if (settings.captureReminderFrequency != 'off') {
        await triggerCaptureReminder(isTest: true);
        sentList.add('Capture reminder');
      }
      return 'Sent samples: ${sentList.join(', ')}';
    } else {
      // None enabled yet: send full sample demonstration so user sees what it looks like
      await triggerStartHereNudge(isTest: true);
      await triggerCaptureReminder(isTest: true);
      return 'Sent demo samples (Start here & Capture reminder). Turn on options above to schedule them!';
    }
  }

  @override
  void dispose() {
    _schedulerTimer?.cancel();
    super.dispose();
  }
}
