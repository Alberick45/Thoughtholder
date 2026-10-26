import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'settings_service.dart';

enum TranscriptionEngine {
  whisper,
  fallbackDevice,
}

class TranscriptionResult {
  final String text;
  final TranscriptionEngine engine;
  final bool pendingOffline;
  final String? errorMessage;

  const TranscriptionResult({
    required this.text,
    required this.engine,
    this.pendingOffline = false,
    this.errorMessage,
  });
}

/// Unified voice transcription service:
/// - Primary: Whisper-large-v3-turbo via Groq Cloud API (state-of-the-art accuracy, never cut-off by pauses, name priming)
/// - Fallback: Built-in SpeechToText (offline / on-device fallback when internet is unreachable)
class VoiceTranscriptionService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final stt.SpeechToText _speechToText = stt.SpeechToText();

  TranscriptionEngine? _currentEngine;
  TranscriptionEngine? get currentEngine => _currentEngine;

  Timer? _amplitudeTimer;
  String? _currentAudioPath;
  bool _isRecording = false;
  bool get isRecording => _isRecording;

  // Fallback state
  String _fallbackCommitted = '';
  String _fallbackSegment = '';
  bool _wantListening = false;
  int _fallbackRetryCount = 0;
  Timer? _fallbackRestartTimer;
  String? _fallbackLocaleId;
  bool _speechReady = false;

  static const String groqTranscriptionsUrl =
      'https://api.groq.com/openai/v1/audio/transcriptions';

  /// Verifies real internet connectivity to Groq servers
  Future<bool> checkGroqReachability(String apiKey) async {
    if (apiKey.trim().isEmpty) return false;
    try {
      final res = await http.get(
        Uri.parse('https://api.groq.com/openai/v1/models'),
        headers: {'Authorization': 'Bearer ${apiKey.trim()}'},
      ).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Starts voice capture using Whisper if online, or Device fallback if offline
  Future<TranscriptionEngine> start({
    required SettingsService settings,
    required void Function(String text) onLiveText,
    required void Function(double normalizedVolume) onAmplitude,
  }) async {
    _isRecording = true;
    final groqKey = settings.groqApiKey;
    final preferWhisper = settings.useWhisperAsPrimary;

    bool canUseWhisper = false;
    if (preferWhisper && groqKey.isNotEmpty) {
      canUseWhisper = await checkGroqReachability(groqKey);
    }

    if (canUseWhisper) {
      try {
        final hasPerm = await _audioRecorder.hasPermission();
        if (hasPerm) {
          final tempDir = await getTemporaryDirectory();
          _currentAudioPath =
              '${tempDir.path}/thought_${DateTime.now().millisecondsSinceEpoch}.wav';

          await _audioRecorder.start(
            const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: 16000,
              numChannels: 1,
            ),
            path: _currentAudioPath!,
          );

          _currentEngine = TranscriptionEngine.whisper;

          // Poll amplitude for live visualizer
          _amplitudeTimer?.cancel();
          _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 75), (_) async {
            if (!_isRecording) return;
            try {
              final amp = await _audioRecorder.getAmplitude();
              // current is typically -160 to 0 dBFS. -50 to -5 is normal voice
              final double normalized = math.max(0.0, (amp.current + 55.0) / 55.0).clamp(0.0, 1.0);
              onAmplitude(normalized);
            } catch (_) {}
          });

          return TranscriptionEngine.whisper;
        }
      } catch (e) {
        debugPrint('[VoiceTranscription] AudioRecorder error, falling back to STT: $e');
      }
    }

    // --- Device Fallback ---
    _currentEngine = TranscriptionEngine.fallbackDevice;
    _fallbackCommitted = '';
    _fallbackSegment = '';
    _wantListening = true;
    _fallbackRetryCount = 0;

    await _initFallbackSTT();
    _startFallbackListen(settings, onLiveText, onAmplitude);

    return TranscriptionEngine.fallbackDevice;
  }

  Future<void> _initFallbackSTT() async {
    if (_speechReady) return;
    _speechReady = await _speechToText.initialize(
      onError: (e) => debugPrint('[FallbackSTT] error: ${e.errorMsg}'),
      onStatus: (s) => debugPrint('[FallbackSTT] status: $s'),
      debugLogging: kDebugMode,
    );

    if (_speechReady) {
      final locales = await _speechToText.locales();
      final sys = await _speechToText.systemLocale();
      for (final p in ['en_GH', 'en-GH', 'en_NG', 'en-NG', 'en_GB', 'en-GB', 'en_US', 'en-US']) {
        final match = locales.where((l) => l.localeId.toLowerCase() == p.toLowerCase());
        if (match.isNotEmpty) {
          _fallbackLocaleId = match.first.localeId;
          break;
        }
      }
      _fallbackLocaleId ??= sys?.localeId;
    }
  }

  void _startFallbackListen(
    SettingsService settings,
    void Function(String text) onLiveText,
    void Function(double normalizedVolume) onAmplitude,
  ) {
    _speechToText.listen(
      onResult: (result) {
        final words = result.recognizedWords.trim();
        if (words.isEmpty) return;
        if (result.finalResult) {
          _fallbackCommitted = '$_fallbackCommitted $words'.trim();
          _fallbackSegment = '';
        } else {
          _fallbackSegment = words;
        }
        final combined = '$_fallbackCommitted $_fallbackSegment'.trim();
        onLiveText(combined);
      },
      onSoundLevelChange: (level) {
        final normalized = (level.abs() / 20.0).clamp(0.0, 1.0);
        onAmplitude(normalized);
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: _fallbackLocaleId,
        listenFor: const Duration(minutes: 15),
        pauseFor: const Duration(seconds: 30),
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
        autoPunctuation: true,
        onDevice: !settings.speechOnline,
      ),
    );
  }

  /// Stops voice capture and returns the transcribed thought
  Future<TranscriptionResult> stop(SettingsService settings) async {
    _isRecording = false;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;

    if (_currentEngine == TranscriptionEngine.fallbackDevice) {
      _wantListening = false;
      _fallbackRestartTimer?.cancel();
      try {
        await _speechToText.stop();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 300));
      final fullText = '$_fallbackCommitted $_fallbackSegment'.trim();
      _fallbackCommitted = '';
      _fallbackSegment = '';
      return TranscriptionResult(
        text: fullText,
        engine: TranscriptionEngine.fallbackDevice,
      );
    }

    // --- Whisper Stop & Transcribe ---
    String? recordedFilePath;
    try {
      recordedFilePath = await _audioRecorder.stop();
    } catch (e) {
      debugPrint('[VoiceTranscription] Stop recorder error: $e');
    }

    recordedFilePath ??= _currentAudioPath;
    _currentAudioPath = null;

    if (recordedFilePath == null || !await File(recordedFilePath).exists()) {
      return const TranscriptionResult(
        text: '',
        engine: TranscriptionEngine.whisper,
      );
    }

    final file = File(recordedFilePath);
    final fileSize = await file.length();
    if (fileSize < 2000) {
      // Audio file was too short/empty
      try { await file.delete(); } catch (_) {}
      return const TranscriptionResult(
        text: '',
        engine: TranscriptionEngine.whisper,
      );
    }

    try {
      final text = await _transcribeWithGroq(
        filePath: recordedFilePath,
        apiKey: settings.groqApiKey,
        prompt: settings.whisperPrompt,
      );

      // Clean up temporary audio file after successful transcription
      try { await file.delete(); } catch (_) {}

      return TranscriptionResult(
        text: text,
        engine: TranscriptionEngine.whisper,
      );
    } catch (e) {
      debugPrint('[VoiceTranscription] Groq upload failed, saving for pending retry: $e');
      await _savePendingOfflineAudio(recordedFilePath);
      return const TranscriptionResult(
        text: '',
        engine: TranscriptionEngine.whisper,
        pendingOffline: true,
        errorMessage: 'Network error. Audio saved offline and will transcribe when online.',
      );
    }
  }

  /// Multi-part POST to Groq Whisper endpoint
  Future<String> _transcribeWithGroq({
    required String filePath,
    required String apiKey,
    required String prompt,
  }) async {
    final uri = Uri.parse(groqTranscriptionsUrl);
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
      ..fields['model'] = 'whisper-large-v3-turbo'
      ..fields['language'] = 'en'
      ..fields['prompt'] = prompt
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamedResponse = await request.send().timeout(const Duration(seconds: 40));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final text = (data['text'] as String?)?.trim() ?? '';
      return text;
    } else {
      throw Exception('Groq API Error (${response.statusCode}): ${response.body}');
    }
  }

  Future<void> _savePendingOfflineAudio(String sourcePath) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final pendingDir = Directory('${docs.path}/pending_recordings');
      if (!await pendingDir.exists()) {
        await pendingDir.create(recursive: true);
      }
      final target = '${pendingDir.path}/${DateTime.now().millisecondsSinceEpoch}.wav';
      await File(sourcePath).copy(target);
      await File(sourcePath).delete();
    } catch (e) {
      debugPrint('[VoiceTranscription] Error saving pending audio: $e');
    }
  }

  /// Retries transcribing any audio files stored while offline
  Future<List<String>> retryPendingRecordings(SettingsService settings) async {
    final apiKey = settings.groqApiKey;
    if (apiKey.isEmpty) return [];

    final isOnline = await checkGroqReachability(apiKey);
    if (!isOnline) return [];

    try {
      final docs = await getApplicationDocumentsDirectory();
      final pendingDir = Directory('${docs.path}/pending_recordings');
      if (!await pendingDir.exists()) return [];

      final results = <String>[];
      final files = pendingDir.listSync().whereType<File>().toList();

      for (final f in files) {
        if (f.path.toLowerCase().endsWith('.wav')) {
          try {
            final text = await _transcribeWithGroq(
              filePath: f.path,
              apiKey: apiKey,
              prompt: settings.whisperPrompt,
            );
            if (text.isNotEmpty) {
              results.add(text);
              await f.delete();
            }
          } catch (_) {
            // Keep file for next retry
          }
        }
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  void dispose() {
    _amplitudeTimer?.cancel();
    _fallbackRestartTimer?.cancel();
    _audioRecorder.dispose();
  }
}
