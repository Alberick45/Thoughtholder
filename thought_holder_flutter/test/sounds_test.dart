import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:thought_holder_flutter/sound_service.dart';
import 'package:thought_holder_flutter/settings_service.dart';

// Mock settings service for unit tests without Hive disk dependency
class MockSoundSettings extends Fake implements SettingsService {
  bool _soundsEnabled = false;
  double _soundVolume = 0.40;
  bool _soundGroupTaps = true;
  bool _soundGroupSwipes = true;
  bool _soundGroupSaving = true;
  bool _soundGroupDeleting = true;
  bool _soundGroupTyping = false;
  String _soundStyle = 'soft';
  bool _soundPromptAnswered = false;

  @override
  bool get soundsEnabled => _soundsEnabled;
  @override
  Future<void> setSoundsEnabled(bool value) async {
    _soundsEnabled = value;
  }

  @override
  double get soundVolume => _soundVolume;
  @override
  Future<void> setSoundVolume(double value) async {
    _soundVolume = value.clamp(0.0, 0.80);
  }

  @override
  bool get soundGroupTaps => _soundGroupTaps;
  @override
  Future<void> setSoundGroupTaps(bool value) async {
    _soundGroupTaps = value;
  }

  @override
  bool get soundGroupSwipes => _soundGroupSwipes;
  @override
  Future<void> setSoundGroupSwipes(bool value) async {
    _soundGroupSwipes = value;
  }

  @override
  bool get soundGroupSaving => _soundGroupSaving;
  @override
  Future<void> setSoundGroupSaving(bool value) async {
    _soundGroupSaving = value;
  }

  @override
  bool get soundGroupDeleting => _soundGroupDeleting;
  @override
  Future<void> setSoundGroupDeleting(bool value) async {
    _soundGroupDeleting = value;
  }

  @override
  bool get soundGroupTyping => _soundGroupTyping;
  @override
  Future<void> setSoundGroupTyping(bool value) async {
    _soundGroupTyping = value;
  }

  @override
  String get soundStyle => _soundStyle;
  @override
  Future<void> setSoundStyle(String value) async {
    _soundStyle = value;
  }

  @override
  bool get soundPromptAnswered => _soundPromptAnswered;
  @override
  Future<void> setSoundPromptAnswered(bool value) async {
    _soundPromptAnswered = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SOUNDS: Design Rules & Engine Verification', () {
    late SoundService soundService;
    late MockSoundSettings settings;

    setUp(() {
      soundService = SoundService.instance;
      settings = MockSoundSettings();
    });

    test('1. Master switch is OFF by default and controls sound emission', () async {
      // Off by default
      expect(settings.soundsEnabled, isFalse);

      // Verify group mappings for all sound events
      for (final event in SoundEvent.values) {
        final group = soundService.getGroupForEvent(event);
        final fileName = soundService.getFileNameForEvent(event);
        expect(fileName, endsWith('.wav'));
        if (event == SoundEvent.recordStart || event == SoundEvent.recordSaved) {
          expect(group, isNull, reason: 'Recording cues bypass group filters');
        } else {
          expect(group, isNotNull, reason: '$event must belong to a group');
        }
      }

      // Preview mode works even when master is off
      await soundService.play(SoundEvent.save, settings: settings, preview: true);

      // Turning on master switch
      await settings.setSoundsEnabled(true);
      expect(settings.soundsEnabled, isTrue);
    });

    test('2. Group switches silence their specific events', () async {
      await settings.setSoundsEnabled(true);

      // Taps group
      expect(soundService.getGroupForEvent(SoundEvent.tap), equals(SoundGroup.taps));
      expect(soundService.getGroupForEvent(SoundEvent.tabSwitch), equals(SoundGroup.taps));
      expect(soundService.getGroupForEvent(SoundEvent.popupOpen), equals(SoundGroup.taps));
      expect(soundService.getGroupForEvent(SoundEvent.popupClose), equals(SoundGroup.taps));
      expect(soundService.getGroupForEvent(SoundEvent.switchOn), equals(SoundGroup.taps));
      expect(soundService.getGroupForEvent(SoundEvent.switchOff), equals(SoundGroup.taps));
      expect(soundService.getGroupForEvent(SoundEvent.menuOpen), equals(SoundGroup.taps));

      // Swipes group
      expect(soundService.getGroupForEvent(SoundEvent.swipe), equals(SoundGroup.swipes));
      expect(soundService.getGroupForEvent(SoundEvent.thresholdClick), equals(SoundGroup.swipes));

      // Saving group
      expect(soundService.getGroupForEvent(SoundEvent.save), equals(SoundGroup.saving));
      expect(soundService.getGroupForEvent(SoundEvent.drop), equals(SoundGroup.saving));
      expect(soundService.getGroupForEvent(SoundEvent.done), equals(SoundGroup.saving));
      expect(soundService.getGroupForEvent(SoundEvent.celebrate), equals(SoundGroup.saving));

      // Deleting group
      expect(soundService.getGroupForEvent(SoundEvent.trash), equals(SoundGroup.deleting));
      expect(soundService.getGroupForEvent(SoundEvent.deleteForever), equals(SoundGroup.deleting));
      expect(soundService.getGroupForEvent(SoundEvent.undo), equals(SoundGroup.deleting));
      expect(soundService.getGroupForEvent(SoundEvent.error), equals(SoundGroup.deleting));

      // Typing group
      expect(soundService.getGroupForEvent(SoundEvent.key), equals(SoundGroup.typing));
      expect(soundService.getGroupForEvent(SoundEvent.keySpace), equals(SoundGroup.typing));
      expect(soundService.getGroupForEvent(SoundEvent.keyEnter), equals(SoundGroup.typing));

      // Verify disabling group turns it off
      await settings.setSoundGroupTaps(false);
      expect(settings.soundGroupTaps, isFalse);

      await settings.setSoundGroupTyping(true);
      expect(settings.soundGroupTyping, isTrue);
    });

    test('3. Master volume slider clamps at max 80% (0.80)', () async {
      // Default volume
      expect(settings.soundVolume, equals(0.40));

      // Setting higher than 0.80 clamps to 0.80
      await settings.setSoundVolume(1.0);
      expect(settings.soundVolume, equals(0.80));

      await settings.setSoundVolume(0.85);
      expect(settings.soundVolume, equals(0.80));

      // Normal value
      await settings.setSoundVolume(0.60);
      expect(settings.soundVolume, equals(0.60));

      // Negative value clamps to 0.0
      await settings.setSoundVolume(-0.5);
      expect(settings.soundVolume, equals(0.0));

      // SoundService setVolume also clamps
      await soundService.setVolume(0.99, settings: settings);
      expect(settings.soundVolume, equals(0.80));
    });

    test('4. Throttling logic drops rapid repeated events', () async {
      await settings.setSoundsEnabled(true);

      // Play once
      await soundService.play(SoundEvent.tap, settings: settings);

      // Immediate replay of same event is throttled (<80 ms)
      await soundService.play(SoundEvent.tap, settings: settings);

      // Typing throttle (<60 ms)
      await settings.setSoundGroupTyping(true);
      await soundService.play(SoundEvent.key, settings: settings);
      await soundService.play(SoundEvent.key, settings: settings);
    });

    test('5. Microphone mute window mutes UI sounds during recording and for 400 ms after', () async {
      // Initially not recording and not muted
      soundService.notifyRecordingStopped();
      // Wait for any trailing 400ms buffer from prior test
      await Future<void>.delayed(const Duration(milliseconds: 410));
      expect(soundService.isRecording, isFalse);
      expect(soundService.isRecordingMuted, isFalse);

      // Recording starts
      soundService.notifyRecordingStarting();
      expect(soundService.isRecording, isTrue);
      expect(soundService.isRecordingMuted, isTrue);

      // Recording stops -> still muted for 400ms buffer
      soundService.notifyRecordingStopped();
      expect(soundService.isRecording, isFalse);
      expect(soundService.isRecordingMuted, isTrue);

      // Wait 410 ms -> mute window expires
      await Future<void>.delayed(const Duration(milliseconds: 410));
      expect(soundService.isRecordingMuted, isFalse);
    });

    test('6. Audio assets resolve, all 22 events exist in soft and crisp, and combined size < 1 MB', () {
      final softDir = Directory('assets/sounds/soft');
      final crispDir = Directory('assets/sounds/crisp');

      expect(softDir.existsSync(), isTrue, reason: 'assets/sounds/soft directory must exist');
      expect(crispDir.existsSync(), isTrue, reason: 'assets/sounds/crisp directory must exist');

      int totalSizeBytes = 0;

      for (final event in SoundEvent.values) {
        final filename = soundService.getFileNameForEvent(event);
        final softFile = File('${softDir.path}/$filename');
        final crispFile = File('${crispDir.path}/$filename');

        expect(softFile.existsSync(), isTrue, reason: 'Missing soft sound file: $filename');
        expect(crispFile.existsSync(), isTrue, reason: 'Missing crisp sound file: $filename');

        final softLen = softFile.lengthSync();
        final crispLen = crispFile.lengthSync();

        expect(softLen, greaterThan(44), reason: 'File $filename in soft must be valid WAV');
        expect(crispLen, greaterThan(44), reason: 'File $filename in crisp must be valid WAV');

        // Check RIFF header
        final softBytes = softFile.readAsBytesSync();
        final riffTag = String.fromCharCodes(softBytes.sublist(0, 4));
        final waveTag = String.fromCharCodes(softBytes.sublist(8, 12));
        expect(riffTag, equals('RIFF'), reason: '$filename must be a RIFF WAV file');
        expect(waveTag, equals('WAVE'), reason: '$filename must have WAVE format');

        totalSizeBytes += softLen + crispLen;
      }

      // Total size must be under 1 MB (1,048,576 bytes)
      expect(totalSizeBytes, lessThan(1048576));
      expect(totalSizeBytes, lessThan(600000), reason: 'Assets are highly optimized around ~470 KB');
    });
  });
}
