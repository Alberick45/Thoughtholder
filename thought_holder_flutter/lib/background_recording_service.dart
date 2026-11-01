import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'settings_service.dart';
import 'sound_service.dart';
import 'thought_provider.dart';
import 'voice_transcription_service.dart';

// Win32 Sleep Prevention FFI
typedef _SetThreadExecutionStateC = Uint32 Function(Uint32 esFlags);
typedef _SetThreadExecutionStateDart = int Function(int esFlags);

class BackgroundRecordingService extends ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('com.thoughtholder.app/background_recording');

  final AudioRecorder _desktopRecorder = AudioRecorder();
  final VoiceTranscriptionService _transcriptionService =
      VoiceTranscriptionService();

  SettingsService? _lastSettings;
  bool _isRecording = false;
  bool _isPaused = false;
  String? _pauseReason;
  int _durationSeconds = 0;
  String? _activeAudioPath;
  Timer? _desktopTimer;

  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  String? get pauseReason => _pauseReason;
  int get durationSeconds => _durationSeconds;
  String? get activeAudioPath => _activeAudioPath;

  String get formattedDuration {
    final mins = _durationSeconds / 60;
    final secs = _durationSeconds % 60;
    return '${mins.toInt().toString().padLeft(2, '0')}:${secs.toInt().toString().padLeft(2, '0')}';
  }

  // Crash recovery state
  String? _unfinishedRecordingPath;
  String? get unfinishedRecordingPath => _unfinishedRecordingPath;
  bool get hasUnfinishedRecording => _unfinishedRecordingPath != null;

  BackgroundRecordingService() {
    if (!kIsWeb && Platform.isAndroid) {
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onTimerTick':
        _durationSeconds = (call.arguments as num).toInt();
        notifyListeners();
        break;
      case 'onStatusChanged':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final status = args['status'] as String?;
        final reason = args['reason'] as String?;
        if (status == 'paused') {
          _isPaused = true;
          _pauseReason = reason ?? 'your phone call';
        } else if (status == 'resumed' || status == 'recording') {
          _isPaused = false;
          _pauseReason = null;
        } else if (status == 'stopped') {
          _isRecording = false;
          _isPaused = false;
        }
        notifyListeners();
        break;
      case 'onRecordingStopped':
        final path = call.arguments as String?;
        if (path != null && path.isNotEmpty) {
          _activeAudioPath = path;
        }
        _isRecording = false;
        _isPaused = false;
        notifyListeners();
        break;
    }
  }

  // --- Windows Sleep Prevention ---
  void _setWindowsSleepPrevention(bool prevent) {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final setThreadExecutionState = kernel32.lookupFunction<
          _SetThreadExecutionStateC, _SetThreadExecutionStateDart>(
        'SetThreadExecutionState',
      );
      if (prevent) {
        // ES_CONTINUOUS (0x80000000) | ES_SYSTEM_REQUIRED (0x00000001) | ES_AWAYMODE_REQUIRED (0x00000040)
        setThreadExecutionState(0x80000000 | 0x00000001 | 0x00000040);
      } else {
        // ES_CONTINUOUS
        setThreadExecutionState(0x80000000);
      }
    } catch (_) {}
  }

  // --- Check Unfinished Recording (Requirement F) ---
  Future<void> checkUnfinishedRecording() async {
    if (kIsWeb) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final unfinishedFile = File('${docs.path}/active_unfinished.wav');
      if (await unfinishedFile.exists()) {
        final len = await unfinishedFile.length();
        if (len > 4000) {
          _unfinishedRecordingPath = unfinishedFile.path;
          notifyListeners();
        } else {
          try {
            await unfinishedFile.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> discardUnfinishedRecording() async {
    if (_unfinishedRecordingPath != null) {
      try {
        final f = File(_unfinishedRecordingPath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      _unfinishedRecordingPath = null;
      notifyListeners();
    }
  }

  // --- Start Recording (Foreground Service on Android, Awake on Desktop) ---
  Future<bool> startRecording(SettingsService settings) async {
    _lastSettings = settings;
    if (_isRecording) return false;

    // Play recording started tone BEFORE opening microphone (Section 1 & 3)
    try {
      if (settings.soundsEnabled) {
        await SoundService.instance.play(SoundEvent.recordStart, settings: settings);
        await Future.delayed(const Duration(milliseconds: 140));
      }
    } catch (_) {}
    SoundService.instance.notifyRecordingStarting();

    _durationSeconds = 0;
    _isPaused = false;
    _pauseReason = null;

    final docs = await getApplicationDocumentsDirectory();
    final outputPath = '${docs.path}/active_unfinished.wav';
    _activeAudioPath = outputPath;

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final success = await _channel.invokeMethod<bool>('startRecording', {
          'outputPath': outputPath,
        });
        _isRecording = success ?? false;
        notifyListeners();
        return _isRecording;
      } catch (e) {
        debugPrint('[BackgroundRecording] Android start failed: $e');
        return false;
      }
    } else {
      // Desktop / iOS / Web
      try {
        final hasPerm = await _desktopRecorder.hasPermission();
        if (!hasPerm) return false;

        _setWindowsSleepPrevention(true);

        await _desktopRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: outputPath,
        );

        _isRecording = true;
        _desktopTimer?.cancel();
        _desktopTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (_isRecording && !_isPaused) {
            _durationSeconds++;
            notifyListeners();
          }
        });

        notifyListeners();
        return true;
      } catch (e) {
        debugPrint('[BackgroundRecording] Desktop start failed: $e');
        _setWindowsSleepPrevention(false);
        return false;
      }
    }
  }

  // --- Stop Recording ---
  Future<String?> stopRecording({SettingsService? settings}) async {
    final s = settings ?? _lastSettings;
    if (!_isRecording && _activeAudioPath == null) return null;

    final recordedPath = _activeAudioPath;
    _isRecording = false;
    _isPaused = false;
    _pauseReason = null;
    _desktopTimer?.cancel();
    _desktopTimer = null;
    _setWindowsSleepPrevention(false);

    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('stopRecording');
      } catch (_) {}
    } else {
      try {
        await _desktopRecorder.stop();
      } catch (_) {}
    }

    SoundService.instance.notifyRecordingStopped();
    // Play recording saved tone AFTER microphone closes (Section 1 & 3)
    try {
      if (s != null && s.soundsEnabled) {
        await SoundService.instance.play(SoundEvent.recordSaved, settings: s);
      }
    } catch (_) {}

    notifyListeners();

    if (recordedPath != null && await File(recordedPath).exists()) {
      // Move active_unfinished.wav to a unique permanent voice note file
      final docs = await getApplicationDocumentsDirectory();
      final savedDir = Directory('${docs.path}/saved_audio');
      if (!await savedDir.exists()) await savedDir.create(recursive: true);

      final finalPath =
          '${savedDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      final file = File(recordedPath);
      await file.copy(finalPath);
      try {
        await file.delete();
      } catch (_) {}

      _activeAudioPath = null;
      return finalPath;
    }

    _activeAudioPath = null;
    return null;
  }

  // --- Process and Save Audio (Groq Whisper with Offline Audio Fallback) ---
  Future<void> processAndSaveThought({
    required String audioPath,
    required ThoughtProvider thoughtProvider,
    required SettingsService settings,
    required void Function(String message, {VoidCallback? onUndo, VoidCallback? onTryAgain}) onFeedback,
  }) async {
    final file = File(audioPath);
    if (!await file.exists()) return;

    final hasKey = settings.hasGroqKey;

    // Check Groq reachability if key present
    bool canTranscribe = false;
    if (hasKey) {
      canTranscribe = await _transcriptionService.checkGroqReachability(settings.groqApiKey);
    }

    if (canTranscribe) {
      onFeedback('Turning your voice into text…');
      try {
        final text = await _transcriptionService.transcribeAudioFile(
          audioPath,
          settings.groqApiKey,
          settings.whisperPrompt,
        );

        if (text.trim().isNotEmpty) {
          await thoughtProvider.addThought(
            text.trim(),
            'thought',
            tags: 'whisper-voice',
          );
          SoundService.instance.play(SoundEvent.save, settings: settings);
          onFeedback(
            'Saved to Unsorted',
            onUndo: () {
              SoundService.instance.play(SoundEvent.undo, settings: settings);
              final last = thoughtProvider.unsortedThoughts.firstOrNull;
              if (last != null) {
                thoughtProvider.moveToTrash(last['id']);
              }
            },
          );
          return;
        }
      } catch (e) {
        debugPrint('[BackgroundRecording] Transcription error: $e');
      }
    }

    // Fallback: Never discard audio (UPDATE 4 - Section A)
    // Keep the audio and show "Saved. Text will be added when Groq is available." with a "Try again" button.
    final durationStr = formattedDuration;
    await thoughtProvider.addThought(
      'Voice note ($durationStr)',
      'thought',
      tags: 'voice-pending-groq:$audioPath',
    );
    SoundService.instance.play(SoundEvent.save, settings: settings);

    onFeedback(
      'Saved. Text will be added when Groq is available.',
      onTryAgain: () async {
        await processAndSaveThought(
          audioPath: audioPath,
          thoughtProvider: thoughtProvider,
          settings: settings,
          onFeedback: onFeedback,
        );
      },
    );
  }
}
