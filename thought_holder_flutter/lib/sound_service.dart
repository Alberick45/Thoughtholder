import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'settings_service.dart';

/// Sound categories matching Section 2 and 3 settings groups.
enum SoundGroup {
  taps,
  swipes,
  saving,
  deleting,
  typing,
}

/// All sound events supported across the application.
enum SoundEvent {
  // Taps and buttons
  tap,
  tabSwitch,
  popupOpen,
  popupClose,
  switchOn,
  switchOff,
  menuOpen,

  // Swipes and slides
  swipe,
  thresholdClick,

  // Saving and finishing
  save,
  drop,
  done,
  celebrate,

  // Deleting and warnings
  trash,
  deleteForever,
  undo,
  error,

  // Typing
  key,
  keySpace,
  keyEnter,

  // Recording
  recordStart,
  recordSaved,
}

/// Central low-latency sound service managing feedback tones, throttling,
/// volume limits, group settings, and microphone-safe mute windows.
class SoundService extends ChangeNotifier {
  static final SoundService instance = SoundService._();
  SoundService._();

  AudioPlayer? _player;
  bool _isInitialized = false;

  SoundEvent? _lastPlayedEvent;
  DateTime _lastPlayedTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastTypingTime = DateTime.fromMillisecondsSinceEpoch(0);

  bool _isRecording = false;
  DateTime _lastRecordingStateChange = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isRecording => _isRecording;

  /// Returns true while recording voice, and for 400 ms after recording starts or stops.
  bool get isRecordingMuted {
    if (_isRecording) return true;
    final msSinceChange = DateTime.now().difference(_lastRecordingStateChange).inMilliseconds;
    return msSinceChange < 400;
  }

  void notifyRecordingStarting() {
    _isRecording = true;
    _lastRecordingStateChange = DateTime.now();
  }

  void notifyRecordingStopped() {
    _isRecording = false;
    _lastRecordingStateChange = DateTime.now();
  }

  /// Sets whether UI sounds are enabled globally.
  Future<void> setEnabled(bool enabled, {SettingsService? settings}) async {
    if (settings != null) {
      await settings.setSoundsEnabled(enabled);
    }
    notifyListeners();
  }

  /// Sets master sound volume (capped at 80% maximum).
  Future<void> setVolume(double volume, {SettingsService? settings}) async {
    final clamped = volume.clamp(0.0, 0.80);
    if (settings != null) {
      await settings.setSoundVolume(clamped);
    }
    if (_player != null) {
      try {
        await _player!.setVolume(clamped);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Enables or disables a specific sound group.
  Future<void> setGroupEnabled(SoundGroup group, bool enabled, {SettingsService? settings}) async {
    if (settings != null) {
      switch (group) {
        case SoundGroup.taps:
          await settings.setSoundGroupTaps(enabled);
          break;
        case SoundGroup.swipes:
          await settings.setSoundGroupSwipes(enabled);
          break;
        case SoundGroup.saving:
          await settings.setSoundGroupSaving(enabled);
          break;
        case SoundGroup.deleting:
          await settings.setSoundGroupDeleting(enabled);
          break;
        case SoundGroup.typing:
          await settings.setSoundGroupTyping(enabled);
          break;
      }
    }
    notifyListeners();
  }

  /// Preloads audio engine and preheats sound cache for sub-50ms latency.
  Future<void> preload() async {
    if (_isInitialized) return;
    try {
      _player = AudioPlayer();
      await _player!.setReleaseMode(ReleaseMode.stop);
      await _player!.setPlayerMode(PlayerMode.lowLatency);

      // Configure audio context to avoid ducking/pausing user music on mobile.
      // iOS-only options must not be applied on Windows/Linux; that caused silent fallback.
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await AudioPlayer.global.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: false,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.assistanceSonification,
              audioFocus: AndroidAudioFocus.none,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.ambient,
              options: const {
                AVAudioSessionOptions.mixWithOthers,
              },
            ),
          ),
        );
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('[SoundService] Audio initialization failed (silent fallback): $e');
    }
  }

  /// Maps a sound event to its corresponding group switch.
  SoundGroup? getGroupForEvent(SoundEvent event) {
    switch (event) {
      case SoundEvent.tap:
      case SoundEvent.tabSwitch:
      case SoundEvent.popupOpen:
      case SoundEvent.popupClose:
      case SoundEvent.switchOn:
      case SoundEvent.switchOff:
      case SoundEvent.menuOpen:
        return SoundGroup.taps;
      case SoundEvent.swipe:
      case SoundEvent.thresholdClick:
        return SoundGroup.swipes;
      case SoundEvent.save:
      case SoundEvent.drop:
      case SoundEvent.done:
      case SoundEvent.celebrate:
        return SoundGroup.saving;
      case SoundEvent.trash:
      case SoundEvent.deleteForever:
      case SoundEvent.undo:
      case SoundEvent.error:
        return SoundGroup.deleting;
      case SoundEvent.key:
      case SoundEvent.keySpace:
      case SoundEvent.keyEnter:
        return SoundGroup.typing;
      case SoundEvent.recordStart:
      case SoundEvent.recordSaved:
        return null; // Recording cues bypass group filters
    }
  }

  /// Maps a sound event to its asset file name.
  String getFileNameForEvent(SoundEvent event) {
    switch (event) {
      case SoundEvent.tap:
        return 'tap.wav';
      case SoundEvent.tabSwitch:
        return 'tab_switch.wav';
      case SoundEvent.popupOpen:
        return 'popup_open.wav';
      case SoundEvent.popupClose:
        return 'popup_close.wav';
      case SoundEvent.switchOn:
        return 'switch_on.wav';
      case SoundEvent.switchOff:
        return 'switch_off.wav';
      case SoundEvent.menuOpen:
        return 'menu_open.wav';
      case SoundEvent.swipe:
        return 'swipe.wav';
      case SoundEvent.thresholdClick:
        return 'threshold_click.wav';
      case SoundEvent.save:
        return 'save.wav';
      case SoundEvent.drop:
        return 'drop.wav';
      case SoundEvent.done:
        return 'done.wav';
      case SoundEvent.celebrate:
        return 'celebrate.wav';
      case SoundEvent.trash:
        return 'trash.wav';
      case SoundEvent.deleteForever:
        return 'delete_forever.wav';
      case SoundEvent.undo:
        return 'undo.wav';
      case SoundEvent.error:
        return 'error.wav';
      case SoundEvent.key:
        return 'key.wav';
      case SoundEvent.keySpace:
        return 'key_space.wav';
      case SoundEvent.keyEnter:
        return 'key_enter.wav';
      case SoundEvent.recordStart:
        return 'record_start.wav';
      case SoundEvent.recordSaved:
        return 'record_saved.wav';
    }
  }

  /// Plays a sound event respecting master switch, volume, group settings, and throttling.
  /// If [preview] is true, ignores master and group switches (e.g. for "Try a sound" or Test buttons).
  Future<void> play(
    SoundEvent event, {
    SettingsService? settings,
    bool preview = false,
  }) async {
    final now = DateTime.now();

    // 1. Microphone mute window: No UI sounds while recording or within 400ms buffer
    if (!preview && isRecordingMuted) {
      if (event != SoundEvent.recordStart && event != SoundEvent.recordSaved) {
        return;
      }
    }

    // 2. Master switch check: OFF by default until user answers choice card
    if (!preview) {
      final isEnabled = settings?.soundsEnabled ?? false;
      if (!isEnabled) return;
    }

    // 3. Group switch check
    if (!preview && settings != null) {
      final group = getGroupForEvent(event);
      if (group != null) {
        bool groupAllowed = true;
        switch (group) {
          case SoundGroup.taps:
            groupAllowed = settings.soundGroupTaps;
            break;
          case SoundGroup.swipes:
            groupAllowed = settings.soundGroupSwipes;
            break;
          case SoundGroup.saving:
            groupAllowed = settings.soundGroupSaving;
            break;
          case SoundGroup.deleting:
            groupAllowed = settings.soundGroupDeleting;
            break;
          case SoundGroup.typing:
            groupAllowed = settings.soundGroupTyping;
            break;
        }
        if (!groupAllowed) return;
      }
    }

    // 4. Throttling:
    // Ignore repeat of the same sound within 80 ms
    if (!preview && event == _lastPlayedEvent && now.difference(_lastPlayedTime).inMilliseconds < 80) {
      return;
    }

    // Typing throttle: at most one every 60 ms
    if (!preview && (event == SoundEvent.key || event == SoundEvent.keySpace || event == SoundEvent.keyEnter)) {
      if (now.difference(_lastTypingTime).inMilliseconds < 60) {
        return;
      }
      _lastTypingTime = now;
    }

    // 5. Volume check: default 40%, capped at 80% maximum
    final double rawVolume = settings?.soundVolume ?? 0.40;
    final double effectiveVolume = rawVolume.clamp(0.0, 0.80);

    // 6. Play the audio file
    try {
      if (!_isInitialized || _player == null) {
        await preload();
      }
      if (_player == null) return;

      final style = settings?.soundStyle ?? 'soft';
      final fileName = getFileNameForEvent(event);
      final assetPath = 'sounds/$style/$fileName';

      _lastPlayedEvent = event;
      _lastPlayedTime = now;

      // Stop any playing sound so we never play two at once
      await _player!.stop();
      await _player!.setVolume(effectiveVolume);
      await _player!.play(AssetSource(assetPath));
    } catch (e) {
      // Audio errors must fail silently without disrupting the application
      debugPrint('[SoundService] Error playing $event: $e');
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }
}
