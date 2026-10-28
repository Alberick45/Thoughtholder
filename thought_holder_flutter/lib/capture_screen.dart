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
import 'navigation_service.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
  Box? _prefsBox;

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
    _initDraftStorage();
  }

  Future<void> _initDraftStorage() async {
    try {
      _prefsBox = await Hive.openBox('app_preferences');
      final draft = _prefsBox?.get('draft_thought_text', defaultValue: '') as String?;
      if (draft != null && draft.isNotEmpty && _textController.text.isEmpty) {
        _textController.text = draft;
      }
    } catch (_) {}
    _textController.addListener(_onDraftChanged);
  }

  void _onDraftChanged() {
    _prefsBox?.put('draft_thought_text', _textController.text);
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
    _textController.removeListener(_onDraftChanged);
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
            isWhisper ? '✓ Transcribed & saved to Unsorted' : '✓ Saved to Unsorted',
            style: const TextStyle(
                color: Colors.amber, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF141416),
          duration: const Duration(seconds: 2),
        ),
      );

      // Navigate to Stream > Unsorted
      if (mounted) {
        context.read<NavigationNotifier>().goToStream(subTab: 'unsorted');
      }
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
      _textController.clear();
      _prefsBox?.delete('draft_thought_text');
      FocusScope.of(context).unfocus();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Saved to Unsorted',
              style:
                  TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          backgroundColor: Color(0xFF141416),
          duration: Duration(seconds: 2),
        ),
      );

      // Navigate to Stream > Unsorted
      if (mounted) {
        context.read<NavigationNotifier>().goToStream(subTab: 'unsorted');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Mode Toggle (Accessible: never color alone, distinct filled background)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161618),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white12),
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
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
                    decoration: BoxDecoration(
                      color: _captureMode == 'voice'
                          ? const Color(0xFF282308)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _captureMode == 'voice'
                            ? const Color(0xFFFFBF00)
                            : Colors.transparent,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mic_outlined,
                          size: 16,
                          color: _captureMode == 'voice'
                              ? const Color(0xFFFFBF00)
                              : Colors.white54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'VOICE',
                          style: TextStyle(
                            color: _captureMode == 'voice'
                                ? const Color(0xFFFFBF00)
                                : Colors.white54,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    if (_isListening) _stopListening();
                    setState(() => _captureMode = 'text');
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
                    decoration: BoxDecoration(
                      color: _captureMode == 'text'
                          ? const Color(0xFF282308)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _captureMode == 'text'
                            ? const Color(0xFFFFBF00)
                            : Colors.transparent,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_note,
                          size: 18,
                          color: _captureMode == 'text'
                              ? const Color(0xFFFFBF00)
                              : Colors.white54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'TEXT',
                          style: TextStyle(
                            color: _captureMode == 'text'
                                ? const Color(0xFFFFBF00)
                                : Colors.white54,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _captureMode == 'voice'
                ? Center(child: _buildVoiceMode())
                : _buildTextMode(),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Text Input with Ctrl+Enter keyboard support on desktop
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  _submitText,
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  _submitText,
            },
            child: TextField(
              controller: _textController,
              maxLines: 7,
              minLines: 4,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: 'Type your thought here...',
                hintStyle: const TextStyle(color: Colors.white60, fontSize: 18),
                filled: true,
                fillColor: const Color(0xFF1B1B1E),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.white24, width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: Color(0xFFFFBF00), width: 2.0),
                ),
                contentPadding: const EdgeInsets.all(20),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Filled Gold Save Button (Full Width for mobile & desktop)
          ElevatedButton(
            onPressed: _submitText,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFBF00),
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
            ),
            child: const Text(
              'Save to Unsorted',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 17,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // "Say where it goes" label + desktop shortcut hint
          const Text(
            'Saves to Unsorted · Press Ctrl+Enter to save',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
