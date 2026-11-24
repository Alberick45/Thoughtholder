import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'database_helper.dart';
import 'services/voice_segment_service.dart';
import 'settings_service.dart';
import 'sound_service.dart';
import 'thought_provider.dart';
import 'utils/app_logger.dart';
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
  bool _isTranscribing = false;
  String? _pauseReason;
  int _durationSeconds = 0;
  String? _activeAudioPath;
  String? _lastCreatedRecordingId;
  Timer? _desktopTimer;

  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  bool get isTranscribing => _isTranscribing;
  String? get pauseReason => _pauseReason;
  int get durationSeconds => _durationSeconds;
  String? get activeAudioPath => _activeAudioPath;
  String? get lastCreatedRecordingId => _lastCreatedRecordingId;

  String get formattedDuration {
    final mins = _durationSeconds ~/ 60;
    final secs = _durationSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  static String formatSeconds(int totalSec) {
    final mins = totalSec ~/ 60;
    final secs = totalSec % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  static String formatRecordingDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[dt.month - 1];
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $month, $hour:$min $ampm';
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
        setThreadExecutionState(0x80000000 | 0x00000001 | 0x00000040);
      } else {
        setThreadExecutionState(0x80000000);
      }
    } catch (_) {}
  }

  // --- Check Disk Space before long recordings (Requirement 7) ---
  Future<bool> hasEnoughDiskSpace() async {
    if (kIsWeb) return true;
    try {
      if (Platform.isWindows) {
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          '(Get-PSDrive C).Free / 1MB'
        ]);
        if (res.exitCode == 0) {
          final freeMb = double.tryParse(res.stdout.toString().trim());
          if (freeMb != null && freeMb < 100) {
            return false;
          }
        }
      }
    } catch (_) {}
    return true;
  }

  // --- Check Unfinished Recording and Auto-Recover (Requirement 1) ---
  Future<void> checkUnfinishedRecording() async {
    if (kIsWeb) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final unfinishedFile = File('${docs.path}/active_unfinished.wav');
      if (await unfinishedFile.exists()) {
        final len = await unfinishedFile.length();
        if (len > 4000) {
          // Repair 44-byte RIFF header so audio is valid and playable
          await VoiceSegmentService.instance.repairWavHeader(unfinishedFile);

          final savedDir = Directory('${docs.path}/saved_audio');
          if (!await savedDir.exists()) await savedDir.create(recursive: true);

          final recId = 'rec_recovered_${DateTime.now().millisecondsSinceEpoch}';
          final recoveredPath = '${savedDir.path}/$recId.wav';
          await unfinishedFile.copy(recoveredPath);
          try { await unfinishedFile.delete(); } catch (_) {}

          final pcmBytes = (await File(recoveredPath).length()) - 44;
          final durationSec = (pcmBytes / 32000).round();
          final now = DateTime.now().millisecondsSinceEpoch;
          final retentionDays = _lastSettings?.audioRetentionDays ?? 7;

          await DatabaseHelper.instance.insertVoiceRecording({
            'id': recId,
            'file_path': recoveredPath,
            'duration_seconds': durationSec > 0 ? durationSec : 1,
            'created_at': now,
            'status': 'saved',
            'total_segments': 1,
            'completed_segments': 0,
            'error_message': 'Recovered after unexpected app close.',
            'transcript': null,
            'associated_thought_id': null,
            'audio_kept_until': now + (retentionDays * 86400000),
          });

          _unfinishedRecordingPath = recoveredPath;
          AppLogger.info('BackgroundRecording', 'Recovered unfinished recording: $recoveredPath ($durationSec sec)');
          notifyListeners();
        } else {
          try {
            await unfinishedFile.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      AppLogger.error('BackgroundRecording', 'Error recovering unfinished recording: $e');
    }
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

    // Check disk space before recording
    final spaceOk = await hasEnoughDiskSpace();
    if (!spaceOk) {
      AppLogger.info('BackgroundRecording', 'Low disk space (<100MB) before recording');
    }

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
        AppLogger.error('BackgroundRecording', 'Android start failed: $e');
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
        AppLogger.error('BackgroundRecording', 'Desktop start failed: $e');
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
    final finalDurationSec = _durationSeconds;
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
    try {
      if (s != null && s.soundsEnabled) {
        await SoundService.instance.play(SoundEvent.recordSaved, settings: s);
      }
    } catch (_) {}

    notifyListeners();

    if (recordedPath != null && await File(recordedPath).exists()) {
      // Repair WAV header before moving to permanent location
      await VoiceSegmentService.instance.repairWavHeader(File(recordedPath));

      final docs = await getApplicationDocumentsDirectory();
      final savedDir = Directory('${docs.path}/saved_audio');
      if (!await savedDir.exists()) await savedDir.create(recursive: true);

      final recId = 'rec_${DateTime.now().millisecondsSinceEpoch}';
      final finalPath = '${savedDir.path}/$recId.wav';
      final file = File(recordedPath);
      await file.copy(finalPath);
      try {
        await file.delete();
      } catch (_) {}

      final now = DateTime.now().millisecondsSinceEpoch;
      final retentionDays = s?.audioRetentionDays ?? 7;

      // Register in voice_recordings table immediately (Part 2: Save audio first)
      await DatabaseHelper.instance.insertVoiceRecording({
        'id': recId,
        'file_path': finalPath,
        'duration_seconds': finalDurationSec > 0 ? finalDurationSec : 1,
        'created_at': now,
        'status': 'saved',
        'total_segments': 1,
        'completed_segments': 0,
        'error_message': null,
        'transcript': null,
        'associated_thought_id': null,
        'audio_kept_until': now + (retentionDays * 86400000),
      });

      _lastCreatedRecordingId = recId;
      _activeAudioPath = null;
      return finalPath;
    }

    _activeAudioPath = null;
    return null;
  }

  // --- Process and Save Audio (Segmented Groq Whisper with Stitching & Retry) ---
  Future<void> processAndSaveThought({
    required String audioPath,
    required ThoughtProvider thoughtProvider,
    required SettingsService settings,
    required void Function(String message, {VoidCallback? onUndo, VoidCallback? onTryAgain}) onFeedback,
    String? existingRecordingId,
  }) async {
    final file = File(audioPath);
    if (!await file.exists()) return;

    _isTranscribing = true;
    notifyListeners();

    try {
      final recId = existingRecordingId ?? _lastCreatedRecordingId ?? 'rec_${DateTime.now().millisecondsSinceEpoch}';
    final hasKey = settings.hasGroqKey;
    final now = DateTime.now();

    bool canTranscribe = false;
    if (hasKey) {
      canTranscribe = await _transcriptionService.checkGroqReachability(settings.groqApiKey);
    }

    if (canTranscribe) {
      onFeedback('Preparing voice note for transcription…');

      try {
        // Split audio into 90-second segments with 2s overlap
        final docs = await getApplicationDocumentsDirectory();
        final segDir = Directory('${docs.path}/audio_segments/$recId');
        final segments = await VoiceSegmentService.instance.splitWavFile(
          wavFile: file,
          outputDir: segDir,
          segmentDurationSec: 90,
          overlapSec: 2,
        );

        final totalSegments = segments.length;
        await DatabaseHelper.instance.updateVoiceRecording(recId, {
          'status': 'transcribing',
          'total_segments': totalSegments,
        });

        // Store segments in DB
        for (final seg in segments) {
          final segId = 'seg_${recId}_${seg.index}';
          await DatabaseHelper.instance.insertVoiceSegment({
            'id': segId,
            'recording_id': recId,
            'segment_index': seg.index,
            'file_path': seg.filePath,
            'start_ms': seg.startMs,
            'end_ms': seg.endMs,
            'status': 'pending',
            'transcript': null,
            'error_message': null,
            'retry_count': 0,
          });
        }

        int completed = 0;
        final segmentRows = await DatabaseHelper.instance.fetchVoiceSegments(recId);

        for (int i = 0; i < segmentRows.length; i++) {
          final sRow = segmentRows[i];
          final sId = sRow['id'] as String;
          final sPath = sRow['file_path'] as String;

          if (sRow['status'] == 'done' && (sRow['transcript'] as String?)?.isNotEmpty == true) {
            completed++;
            continue;
          }

          onFeedback('Transcribing part ${i + 1} of $totalSegments…');

          try {
            final partText = await _transcriptionService.transcribeAudioFile(
              sPath,
              settings.groqApiKey,
              settings.whisperPrompt,
            );

            await DatabaseHelper.instance.updateVoiceSegment(sId, {
              'status': 'done',
              'transcript': partText,
              'error_message': null,
            });
            completed++;
          } catch (e) {
            AppLogger.error('BackgroundRecording', 'Segment $i failed: $e');
            await DatabaseHelper.instance.updateVoiceSegment(sId, {
              'status': 'failed',
              'error_message': e.toString(),
            });
          }

          await DatabaseHelper.instance.updateVoiceRecording(recId, {
            'completed_segments': completed,
          });
        }

        // Fetch all updated segments and stitch in order
        final updatedSegments = await DatabaseHelper.instance.fetchVoiceSegments(recId);
        final stitched = VoiceSegmentService.instance.stitchTranscripts(updatedSegments);

        if (stitched.isNotEmpty) {
          final thought = await thoughtProvider.addThought(
            stitched,
            'thought',
            tags: 'whisper-voice',
            bucket: 'Raw',
          );

          await DatabaseHelper.instance.updateVoiceRecording(recId, {
            'status': 'done',
            'transcript': stitched,
            'associated_thought_id': thought['id'],
            'error_message': null,
          });

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
        AppLogger.error('BackgroundRecording', 'Transcription pipeline failed: $e');
        await DatabaseHelper.instance.updateVoiceRecording(recId, {
          'status': 'failed',
          'error_message': e.toString(),
        });
      }
    }

    // Fallback: Never lose a voice note!
    // Create thought in Unsorted holding the audio path, with status 'failed' in voice recordings
    final dateStr = formatRecordingDate(now);
    final durationStr = formattedDuration;
    final fallbackTitle = 'Voice note $dateStr ($durationStr), not transcribed yet';

    final thought = await thoughtProvider.addThought(
      fallbackTitle,
      'thought',
      tags: 'voice-pending-groq:$audioPath',
      bucket: 'Raw',
    );

    await DatabaseHelper.instance.updateVoiceRecording(recId, {
      'status': 'failed',
      'error_message': canTranscribe
          ? 'Transcription failed. You can retry anytime.'
          : 'Offline or Groq unreachable. Text will be added when online.',
      'associated_thought_id': thought['id'],
    });

    SoundService.instance.play(SoundEvent.save, settings: settings);

    onFeedback(
      'Saved. Text will be added when Groq is available.',
      onTryAgain: () async {
        await retryRecording(
          recId,
          thoughtProvider: thoughtProvider,
          settings: settings,
          onFeedback: onFeedback,
        );
      },
    );
    } finally {
      _isTranscribing = false;
      notifyListeners();
    }
  }

  /// Retries transcription for an entire voice recording with one click
  Future<bool> retryRecording(
    String recordingId, {
    required ThoughtProvider thoughtProvider,
    required SettingsService settings,
    void Function(String message)? onFeedback,
  }) async {
    final rec = await DatabaseHelper.instance.fetchVoiceRecording(recordingId);
    if (rec == null) return false;

    final filePath = rec['file_path'] as String;
    if (!await File(filePath).exists()) {
      onFeedback?.call('Audio file not found on disk');
      return false;
    }

    onFeedback?.call('Retrying transcription…');
    await processAndSaveThought(
      audioPath: filePath,
      thoughtProvider: thoughtProvider,
      settings: settings,
      existingRecordingId: recordingId,
      onFeedback: (msg, {onTryAgain, onUndo}) => onFeedback?.call(msg),
    );
    return true;
  }

  /// Retries specifically the failed segments of a recording
  Future<bool> retryFailedSegments(
    String recordingId, {
    required ThoughtProvider thoughtProvider,
    required SettingsService settings,
    void Function(String message)? onFeedback,
  }) async {
    final segments = await DatabaseHelper.instance.fetchVoiceSegments(recordingId);
    final failed = segments.where((s) => s['status'] == 'failed' || s['status'] == 'pending').toList();
    if (failed.isEmpty) return true;

    int completed = segments.where((s) => s['status'] == 'done').length;

    for (int i = 0; i < failed.length; i++) {
      final seg = failed[i];
      final segId = seg['id'] as String;
      final segPath = seg['file_path'] as String;
      onFeedback?.call('Retrying part ${seg['segment_index'] + 1}…');

      try {
        final text = await _transcriptionService.transcribeAudioFile(
          segPath,
          settings.groqApiKey,
          settings.whisperPrompt,
        );
        await DatabaseHelper.instance.updateVoiceSegment(segId, {
          'status': 'done',
          'transcript': text,
          'error_message': null,
        });
        completed++;
      } catch (e) {
        await DatabaseHelper.instance.updateVoiceSegment(segId, {
          'status': 'failed',
          'error_message': e.toString(),
        });
      }
    }

    await DatabaseHelper.instance.updateVoiceRecording(recordingId, {
      'completed_segments': completed,
    });

    final allUpdated = await DatabaseHelper.instance.fetchVoiceSegments(recordingId);
    final stitched = VoiceSegmentService.instance.stitchTranscripts(allUpdated);

    if (stitched.isNotEmpty) {
      final rec = await DatabaseHelper.instance.fetchVoiceRecording(recordingId);
      final thoughtId = rec?['associated_thought_id'] as String?;
      if (thoughtId != null && thoughtId.isNotEmpty) {
        await thoughtProvider.updateContent(thoughtId, stitched);
      }
      await DatabaseHelper.instance.updateVoiceRecording(recordingId, {
        'status': 'done',
        'transcript': stitched,
      });
      onFeedback?.call('Transcription complete!');
      return true;
    }
    return false;
  }

  /// Automatically retries any pending or failed recordings on app start or internet reconnect
  Future<void> autoRetryPendingAndFailed(
    SettingsService settings,
    ThoughtProvider thoughtProvider,
  ) async {
    if (!settings.hasGroqKey) return;
    final isOnline = await _transcriptionService.checkGroqReachability(settings.groqApiKey);
    if (!isOnline) return;

    try {
      final recordings = await DatabaseHelper.instance.fetchVoiceRecordings();
      final toRetry = recordings.where((r) =>
          r['status'] == 'failed' || r['status'] == 'saved' || r['status'] == 'transcribing').toList();

      for (final rec in toRetry) {
        final recId = rec['id'] as String;
        final path = rec['file_path'] as String;
        if (await File(path).exists()) {
          await processAndSaveThought(
            audioPath: path,
            thoughtProvider: thoughtProvider,
            settings: settings,
            existingRecordingId: recId,
            onFeedback: (msg, {onTryAgain, onUndo}) {},
          );
        }
      }
    } catch (e) {
      AppLogger.error('BackgroundRecording', 'Auto-retry failed: $e');
    }
  }

  /// Cleans up audio files whose transcripts have been saved for > 7 days (Requirement 2)
  Future<void> cleanupExpiredAudio(SettingsService settings) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final recordings = await DatabaseHelper.instance.fetchVoiceRecordings();

      for (final rec in recordings) {
        final status = rec['status'] as String?;
        final keptUntil = (rec['audio_kept_until'] as num?)?.toInt() ?? 0;
        final thoughtId = rec['associated_thought_id'] as String?;
        final path = rec['file_path'] as String?;

        // NEVER delete audio until its transcript is saved and associated with a thought!
        if (status == 'done' && thoughtId != null && keptUntil > 0 && now >= keptUntil) {
          if (path != null) {
            final f = File(path);
            if (await f.exists()) {
              try { await f.delete(); } catch (_) {}
            }
          }
          // Also clean up segment directory if exists
          try {
            final docs = await getApplicationDocumentsDirectory();
            final segDir = Directory('${docs.path}/audio_segments/${rec['id']}');
            if (await segDir.exists()) {
              await segDir.delete(recursive: true);
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      AppLogger.error('BackgroundRecording', 'Audio cleanup error: $e');
    }
  }
}
