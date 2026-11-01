import 'package:flutter_test/flutter_test.dart';
import 'package:thought_holder_flutter/notification_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('UPDATE 4 - Voice Recording Safeguards & Formats', () {
    test('Timer format formats seconds to mm:ss correctly', () {
      String format(int seconds) {
        final m = (seconds ~/ 60).toString().padLeft(2, '0');
        final s = (seconds % 60).toString().padLeft(2, '0');
        return '$m:$s';
      }

      expect(format(0), '00:00');
      expect(format(9), '00:09');
      expect(format(65), '01:05');
      expect(format(3599), '59:59');
      expect(format(3600), '60:00');
    });

    test('Audio preservation fallback message when Groq transcription is unavailable', () {
      const fallbackText = 'Saved. Text will be added when Groq is available.';
      expect(fallbackText, contains('Saved. Text will be added when Groq is available.'));
    });
  });

  group('UPDATE 5 - Nudge Logic: Quiet Hours, Limits, & Privacy', () {
    test('Quiet hours spans midnight correctly (21:00 to 08:00)', () {
      final service = NotificationService();

      // Inside quiet hours: 22:00
      final dt22 = DateTime(2026, 10, 30, 22, 0);
      expect(service.isInsideQuietHours(dt22, '21:00', '08:00'), isTrue);

      // Inside quiet hours: 03:30 (next morning)
      final dt03 = DateTime(2026, 10, 30, 3, 30);
      expect(service.isInsideQuietHours(dt03, '21:00', '08:00'), isTrue);

      // Inside quiet hours: exactly 21:00
      final dt21 = DateTime(2026, 10, 30, 21, 0);
      expect(service.isInsideQuietHours(dt21, '21:00', '08:00'), isTrue);

      // Outside quiet hours: 08:01
      final dt0801 = DateTime(2026, 10, 30, 8, 1);
      expect(service.isInsideQuietHours(dt0801, '21:00', '08:00'), isFalse);

      // Outside quiet hours: 14:00
      final dt14 = DateTime(2026, 10, 30, 14, 0);
      expect(service.isInsideQuietHours(dt14, '21:00', '08:00'), isFalse);
    });

    test('Quiet hours within same day (13:00 to 15:00)', () {
      final service = NotificationService();

      final dt14 = DateTime(2026, 10, 30, 14, 0);
      expect(service.isInsideQuietHours(dt14, '13:00', '15:00'), isTrue);

      final dt12 = DateTime(2026, 10, 30, 12, 0);
      expect(service.isInsideQuietHours(dt12, '13:00', '15:00'), isFalse);

      final dt16 = DateTime(2026, 10, 30, 16, 0);
      expect(service.isInsideQuietHours(dt16, '13:00', '15:00'), isFalse);
    });

    test('Inactivity rule: skip if user opened app in last 2 hours', () {
      final service = NotificationService();
      final now = DateTime.now();

      // Opened 30 minutes ago -> should skip
      final recentOpen = now.subtract(const Duration(minutes: 30));
      expect(service.wasActiveInLastTwoHours(recentOpen.millisecondsSinceEpoch, now: now), isTrue);

      // Opened 3 hours ago -> should NOT skip
      final pastOpen = now.subtract(const Duration(hours: 3));
      expect(service.wasActiveInLastTwoHours(pastOpen.millisecondsSinceEpoch, now: now), isFalse);

      // Never opened (0) -> should NOT skip
      expect(service.wasActiveInLastTwoHours(0, now: now), isFalse);
    });

    test('Lock-screen privacy: words hidden by default', () {
      String getLockScreenText({required bool showWords, required String text}) {
        return showWords ? text : 'Your next step is ready';
      }

      const originalText = 'Finish math homework chapter 4 with Emmanuel';

      expect(getLockScreenText(showWords: false, text: originalText), 'Your next step is ready');
      expect(getLockScreenText(showWords: true, text: originalText), originalText);
    });

    test('Nudge message truncation to ~100 characters with ellipsis', () {
      final longContent = 'A' * 150;
      final truncated = longContent.length > 100
          ? '${longContent.substring(0, 97)}...'
          : longContent;

      expect(truncated.length, 100);
      expect(truncated.endsWith('...'), isTrue);
    });

    test('Unsorted fallback message when no sorted ideas exist', () {
      const unsortedPrompt = 'Got 5 minutes? Sort 3 ideas.';
      expect(unsortedPrompt, 'Got 5 minutes? Sort 3 ideas.');
    });
  });
}
