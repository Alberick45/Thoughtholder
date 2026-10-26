import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:home_widget/home_widget.dart';
import 'thought_provider.dart';
import 'gamification_provider.dart';
import 'record_trigger.dart';
import 'settings_service.dart';
import 'voice_transcription_service.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({Key? key}) : super(key: key);

  @override
  _CaptureScreenState createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final VoiceTranscriptionService _transcriptionService =
      VoiceTranscriptionService();

  bool _isListening = false;
  bool _isTranscribing = false;
  TranscriptionEngine? _activeEngine;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  String _captureMode = 'voice'; // 'voice' | 'text'
  final TextEditingController _textController = TextEditingController();

  String _committedText = '';
  double _soundLevel = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    recordRequested.addListener(_onRecordRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onRecordRequested();
      _checkPendingRecordings();
    });
  }

  void _onRecordRequested() {
    if (!recordRequested.value) return;
    recordRequested.value = false;
    setState(() => _captureMode = 'voice');
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  Future<void> _checkPendingRecordings() async {
    try {
      final settings = context.read<SettingsService>();
      final recovered =
          await _transcriptionService.retryPendingRecordings(settings);
      if (recovered.isNotEmpty && mounted) {
        for (final text in recovered) {
          context.read<ThoughtProvider>().addThought(
                text,
                'thought',
                tags: 'whisper-offline-retry',
              );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Transcribed ${recovered.length} pending offline thoughts with Whisper AI!',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.teal.shade900,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    recordRequested.removeListener(_onRecordRequested);
    _transcriptionService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _isListening) {
      _stopListening();
    }
  }

  Future<void> _startListening() async {
    if (_isListening || _isTranscribing) return;

    final settings = context.read<SettingsService>();
    _committedText = '';
    _soundLevel = 0.0;

    final engine = await _transcriptionService.start(
      settings: settings,
      onLiveText: (text) {
        if (mounted) {
          setState(() {
            _committedText = text;
          });
        }
      },
      onAmplitude: (normalized) {
        if (mounted) {
          setState(() {
            _soundLevel = normalized;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isListening = true;
        _activeEngine = engine;
      });
    }
  }

  Future<void> _stopListening() async {
    if (!_isListening) return;

    final settings = context.read<SettingsService>();

    setState(() {
      _isListening = false;
      if (_activeEngine == TranscriptionEngine.whisper) {
        _isTranscribing = true;
      }
    });

    final result = await _transcriptionService.stop(settings);

    if (mounted) {
      setState(() {
        _isTranscribing = false;
        _soundLevel = 0.0;
      });
    }

    if (result.pendingOffline && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '✓ Audio saved offline. Will auto-transcribe with Whisper when connected.',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Color(0xFF141416),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (result.text.isNotEmpty && mounted) {
      final isWhisper = result.engine == TranscriptionEngine.whisper;
      context.read<ThoughtProvider>().addThought(
            result.text,
            'thought',
            tags: isWhisper ? 'whisper-ai' : 'voice-fallback',
          );
      context.read<GamificationProvider>().captureVoice();

      if (!kIsWeb && Platform.isAndroid) {
        await HomeWidget.saveWidgetData<String>('last_thought', result.text);
        await HomeWidget.updateWidget(
          qualifiedAndroidName:
              'com.example.thought_holder_flutter.ThoughtWidgetProvider',
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isWhisper ? '✓ TRANSCRIBED WITH WHISPER AI' : '✓ SAVED TO STREAM',
            style: const TextStyle(
                color: Colors.amber, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF141416),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _submitText() async {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      context
          .read<ThoughtProvider>()
          .addThought(text, 'thought', tags: 'text-entry');
      context.read<GamificationProvider>().captureText();
      if (!kIsWeb && Platform.isAndroid) {
        await HomeWidget.saveWidgetData<String>('last_thought', text);
        await HomeWidget.updateWidget(
          qualifiedAndroidName:
              'com.example.thought_holder_flutter.ThoughtWidgetProvider',
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ SAVED TO STREAM',
              style:
                  TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          backgroundColor: Color(0xFF141416),
          duration: Duration(seconds: 2),
        ),
      );
      _textController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Mode Toggle
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    if (_isListening) _stopListening();
                    setState(() => _captureMode = 'voice');
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    decoration: BoxDecoration(
                      color: _captureMode == 'voice'
                          ? Theme.of(context).colorScheme.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _captureMode == 'voice'
                          ? [
                              const BoxShadow(
                                  color: Colors.black26, blurRadius: 4)
                            ]
                          : [],
                    ),
                    child: Text(
                      'VOICE',
                      style: TextStyle(
                        color: _captureMode == 'voice'
                            ? Theme.of(context).primaryColor
                            : Colors.white54,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    if (_isListening) _stopListening();
                    setState(() => _captureMode = 'text');
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    decoration: BoxDecoration(
                      color: _captureMode == 'text'
                          ? Theme.of(context).colorScheme.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _captureMode == 'text'
                          ? [
                              const BoxShadow(
                                  color: Colors.black26, blurRadius: 4)
                            ]
                          : [],
                    ),
                    child: Text(
                      'TEXT',
                      style: TextStyle(
                        color: _captureMode == 'text'
                            ? Theme.of(context).primaryColor
                            : Colors.white54,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Center(
              child:
                  _captureMode == 'voice' ? _buildVoiceMode() : _buildTextMode(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceMode() {
    final isWhisper = _activeEngine == TranscriptionEngine.whisper;

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Engine Status Badge
          if (_isListening || _isTranscribing)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: isWhisper
                    ? const Color(0xFFFFBF00).withOpacity(0.15)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isWhisper
                      ? const Color(0xFFFFBF00).withOpacity(0.4)
                      : Colors.white24,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isWhisper ? Icons.auto_awesome : Icons.mic_none,
                    size: 14,
                    color: isWhisper ? const Color(0xFFFFBF00) : Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isWhisper ? 'WHISPER AI (TURBO)' : 'OFFLINE FALLBACK',
                    style: TextStyle(
                      color:
                          isWhisper ? const Color(0xFFFFBF00) : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ),

          Text(
            _isTranscribing
                ? 'TRANSCRIBING WITH WHISPER AI...'
                : (_isListening
                    ? (isWhisper
                        ? 'HOLDING THOUGHT (WHISPER AI)...'
                        : 'LISTENING (DEVICE)...')
                    : 'TAP TO HOLD A THOUGHT'),
            style: TextStyle(
              color: _isTranscribing
                  ? const Color(0xFFFFBF00)
                  : (_isListening
                      ? Theme.of(context).colorScheme.error
                      : Colors.white54),
              letterSpacing: 2.0,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),

          // Live Audio Equalizer / Sound Level Bars
          if (_isListening) ...[
            const SizedBox(height: 12),
            _buildAudioVisualizer(),
          ],

          const SizedBox(height: 20),

          // Transcribing indicator
          if (_isTranscribing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40.0, vertical: 10),
              child: Column(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFFFFBF00),
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Transcribing audio via Groq Whisper Turbo...',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),

          // Live Text display (Device fallback) or Prompt preview (Whisper)
          if (_isListening)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(
                    isWhisper
                        ? 'Speak continuously without cut-off.\nTap button again when finished to transcribe.'
                        : (_committedText.isEmpty
                            ? 'Listening... speak now.'
                            : _committedText),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isWhisper ? Colors.white70 : Colors.white,
                      fontSize: 16,
                      fontStyle:
                          isWhisper ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 36),

          // Mic Capture Button
          GestureDetector(
            onTap: _isTranscribing
                ? null
                : (_isListening ? _stopListening : _startListening),
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                final double soundScale = _isListening
                    ? 1.0 + (math.min(1.0, _soundLevel) * 0.18)
                    : 1.0;
                final scale = _isListening
                    ? (_pulseAnimation.value * soundScale)
                    : 1.0;

                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      borderRadius: _isListening
                          ? BorderRadius.circular(24)
                          : BorderRadius.circular(75),
                      color: Theme.of(context).colorScheme.surface,
                      border: Border.all(
                        color: _isListening
                            ? Theme.of(context)
                                .colorScheme
                                .error
                                .withOpacity(0.6)
                            : Colors.white10,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _isListening
                              ? Colors.redAccent.withOpacity(0.35)
                              : Colors.black54,
                          blurRadius: _isListening ? 26 : 20,
                          spreadRadius: _isListening ? 8 : 5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isTranscribing
                          ? const CircularProgressIndicator(
                              color: Color(0xFFFFBF00),
                            )
                          : (_isListening
                              ? Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.error,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                )
                              : Icon(
                                  Icons.mic,
                                  size: 60,
                                  color: Theme.of(context).primaryColor,
                                )),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),
          if (!kIsWeb && Platform.isWindows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                _isListening
                    ? 'Press mic button again when done'
                    : 'Global Hotkey: Ctrl+Shift+B pops up & captures',
                style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 11,
                  letterSpacing: 1.1,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  /// Live visual audio level bars reacting to microphone input
  Widget _buildAudioVisualizer() {
    final double normalized = math.min(1.0, math.max(0.08, _soundLevel));

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final factor = [0.6, 0.9, 1.0, 0.8, 0.5][index];
        final barHeight = 8.0 + (normalized * 28.0 * factor);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 4,
          height: barHeight,
          decoration: BoxDecoration(
            color: normalized > 0.15
                ? const Color(0xFFFFBF00)
                : Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildTextMode() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: _textController,
            maxLines: 5,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Type your thought here...',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(20),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _submitText,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surface,
              side: const BorderSide(color: Colors.white10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'SAVE THOUGHT',
              style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
