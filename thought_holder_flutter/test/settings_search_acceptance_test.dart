import 'package:flutter_test/flutter_test.dart';
import 'package:thought_holder_flutter/settings/settings_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Settings Search Acceptance Verification', () {
    final entries = SettingsRegistry.getEntries();

    test('Query "whisper" returns Whisper/AI related settings', () {
      final matches = entries.where((e) => e.matches('whisper')).map((e) => e.title).toList();
      expect(matches, contains('Use Whisper AI first'));
      expect(matches, contains('Set up Groq (4 steps)'));
      expect(matches, contains('Names and terms'));
      expect(matches, contains('Online speech recognition (fallback mode)'));
    });

    test('Query "drive" returns Google Drive backup setting', () {
      final matches = entries.where((e) => e.matches('drive')).map((e) => e.title).toList();
      expect(matches, contains('Google Drive'));
    });

    test('Query "tray" returns System tray setting', () {
      final matches = entries.where((e) => e.matches('tray')).map((e) => e.title).toList();
      expect(matches, contains('Close to system tray'));
    });

    test('Query "calm" returns Theme setting via keywords', () {
      final matches = entries.where((e) => e.matches('calm')).map((e) => e.title).toList();
      expect(matches, contains('Theme'));
    });

    test('Query "split" returns empty results triggering no-match message', () {
      final matches = entries.where((e) => e.matches('split')).map((e) => e.title).toList();
      expect(matches.isEmpty, isTrue);
    });
  });
}
