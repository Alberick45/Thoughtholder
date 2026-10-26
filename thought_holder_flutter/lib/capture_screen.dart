import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:home_widget/home_widget.dart';
import 'thought_provider.dart';
import 'gamification_provider.dart';
import 'record_trigger.dart';
import 'settings_service.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({Key? key}) : super(key: key);

  @override
  _CaptureScreenState createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  String _captureMode = 'voice'; // 'voice' | 'text'
  final TextEditingController _textController = TextEditingController();

  bool _wantListening = false; // true until user explicitly presses stop
  bool _speechReady = false;
  String _committedText = ''; // text banked from earlier segments
  String _currentSegment = ''; // text from the segment in progress
  bool _saving = false;
  String? _localeId;

  // Sound & mic reactivity
  double _soundLevel = 0.0;
  Timer? _restartDebounce;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speech = stt.SpeechToText();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    recordRequested.addListener(_onRecordRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRecordRequested());
  }

  void _onRecordRequested() {
    if (!recordRequested.value) return;
    recordRequested.value = false;
    setState(() => _captureMode = 'voice');
    _startListening();
  }

  @override
  void dispose() {
    recordRequested.removeListener(_onRecordRequested);
    _wantListening = false;
    _restartDebounce?.cancel();
    _speech.cancel();
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

  Future<bool> _initSpeech() async {
    if (_speechReady) return true;
    _speechReady = await _speech.initialize(
      onStatus: _onStatus,
      onError: _onError,
      debugLogging: kDebugMode,
    );

    if (_speechReady) {
      final locales = await _speech.locales();
      final systemLocale = await _speech.systemLocale();

      // On Windows, speech engines frequently fail if requested a locale
      // that does not have an offline voice pack installed.
      // We look for English variants, falling back to system locale.
      final candidates = ['en_GH', 'en-GH', 'en_NG', 'en-NG', 'en_GB', 'en-GB', 'en_US', 'en-US'];
      for (final p in candidates) {
        final m = locales.where((l) => l.localeId.toLowerCase() == p.toLowerCase());
        if (m.isNotEmpty) {
          _localeId = m.first.localeId;
          break;
        }
      }

      if (_localeId == null && systemLocale != null) {
        _localeId = systemLocale.localeId;
      }
    }
    return _speechReady;
  }

  void _onStatus(String status) {
    debugPrint('[CaptureScreen] Speech status: $status');
    if (status == 'listening') {
      _retryCount = 0;
      if (mounted && !_isListening) {
        setState(() => _isListening = true);
      }
    } else if ((status == 'done' || status == 'notListening') && _wantListening) {
      // The recognizer stopped (silence or timeout). Re-listen if user hasn't pressed stop.
      _scheduleRestart(250);
    }
  }

  void _onError(SpeechRecognitionError e) {
    debugPrint('[CaptureScreen] Speech error: ${e.errorMsg} (permanent: ${e.permanent})');
    if (!_wantListening) return;

    const restartableErrors = {
      'error_no_match',
      'error_speech_timeout',
      'error_client',
      'error_busy',
      'error_audio_error',
      'error_server',
      'error_network_timeout',
    };

    if (restartableErrors.contains(e.errorMsg) && _retryCount < 8) {
      _retryCount++;
      final delay = 250 + (_retryCount * 120);
      _scheduleRestart(delay);
    } else if (!e.permanent && _retryCount < 5) {
      _retryCount++;
      _scheduleRestart(500);
    } else {
      _wantListening = false;
      _finishAndSave(); // Never lose captured text on error
    }
  }

  void _scheduleRestart([int delayMs = 250]) {
    if (!_wantListening || !mounted) return;
    _restartDebounce?.cancel();
    _restartDebounce = Timer(Duration(milliseconds: delayMs), () async {
      if (!_wantListening || !mounted) return;
      await _restartListening();
    });
  }

  Future<void> _restartListening() async {
    if (!_wantListening) return;

    // Bank current speech segment before re-opening audio stream
    if (_currentSegment.isNotEmpty) {
      _committedText = '$_committedText $_currentSegment'.trim();
      _currentSegment = '';
      if (mounted) setState(() {});
    }

    try {
      // Free audio stream handle (crucial on Windows to prevent error_busy)
      await _speech.cancel();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted && _wantListening) {
      _listen();
    }
  }

  void _listen() {
    SettingsService? settings;
    try {
      settings = context.read<SettingsService>();
    } catch (_) {}

    final bool useOnline = !kIsWeb && Platform.isWindows
        ? (settings?.speechOnline ?? true)
        : false;

    _speech.listen(
      onResult: (val) {
        if (!mounted) return;
        final words = val.recognizedWords.trim();
        if (words.isEmpty) return;
        setState(() {
          if (val.finalResult) {
            _committedText = '$_committedText $words'.trim();
            _currentSegment = '';
          } else {
            _currentSegment = words;
          }
        });
      },
      onSoundLevelChange: (level) {
        if (mounted) {
          setState(() {
            _soundLevel = level;
          });
        }
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: _localeId,
        listenFor: const Duration(minutes: 15),
        pauseFor: const Duration(seconds: 30),
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
        autoPunctuation: true,
        // On Windows: onDevice: false allows Windows Online Speech Recognition (cloud recognizer)
        // when turned on in Windows Privacy & Security settings, vastly improving accuracy.
        onDevice: !useOnline,
      ),
    );
  }

  Future<void> _startListening() async {
    if (_isListening) return;
    if (!await _initSpeech()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Microphone or speech service unavailable. Please check system permissions.',
            ),
          ),
        );
      }
      return;
    }
    _committedText = '';
    _currentSegment = '';
    _soundLevel = 0.0;
    _retryCount = 0;
    _wantListening = true;
    setState(() => _isListening = true);
    _listen();
  }

  Future<void> _stopListening() async {
    _wantListening = false;
    _restartDebounce?.cancel();
    await _speech.stop();
    await Future.delayed(const Duration(milliseconds: 350));
    await _finishAndSave();
  }

  Future<void> _finishAndSave() async {
    if (_saving) return;
    _saving = true;
    final text = '$_committedText $_currentSegment'.trim();
    _committedText = '';
    _currentSegment = '';
    _soundLevel = 0.0;
    if (mounted) setState(() => _isListening = false);

    if (text.isNotEmpty && mounted) {
      context.read<ThoughtProvider>().addThought(text, 'thought', tags: 'voice-recording');
      context.read<GamificationProvider>().captureVoice();
      if (!kIsWeb && Platform.isAndroid) {
        await HomeWidget.saveWidgetData<String>('last_thought', text);
        await HomeWidget.updateWidget(
          qualifiedAndroidName: 'com.example.thought_holder_flutter.ThoughtWidgetProvider',
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '✓ SAVED TO STREAM',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Color(0xFF141416),
          duration: Duration(seconds: 2),
        ),
      );
    }
    _saving = false;
  }

  void _submitText() async {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      context.read<ThoughtProvider>().addThought(text, 'thought', tags: 'text-entry');
      context.read<GamificationProvider>().captureText();
      if (!kIsWeb && Platform.isAndroid) {
        await HomeWidget.saveWidgetData<String>('last_thought', text);
        await HomeWidget.updateWidget(
          qualifiedAndroidName: 'com.example.thought_holder_flutter.ThoughtWidgetProvider',
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '✓ SAVED TO STREAM',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
          ),
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
                    _wantListening = false;
                    _restartDebounce?.cancel();
                    _speech.cancel();
                    setState(() {
                      _captureMode = 'voice';
                      _isListening = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    decoration: BoxDecoration(
                      color: _captureMode == 'voice'
                          ? Theme.of(context).colorScheme.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _captureMode == 'voice'
                          ? [const BoxShadow(color: Colors.black26, blurRadius: 4)]
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
                    _wantListening = false;
                    _restartDebounce?.cancel();
                    _speech.cancel();
                    setState(() {
                      _captureMode = 'text';
                      _isListening = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    decoration: BoxDecoration(
                      color: _captureMode == 'text'
                          ? Theme.of(context).colorScheme.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _captureMode == 'text'
                          ? [const BoxShadow(color: Colors.black26, blurRadius: 4)]
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
              child: _captureMode == 'voice' ? _buildVoiceMode() : _buildTextMode(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceMode() {
    final hasAudioActivity = _soundLevel.abs() > 0.05;

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isListening)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                _isListening ? 'LISTENING & HOLDING...' : 'TAP TO HOLD A THOUGHT',
                style: TextStyle(
                  color: _isListening
                      ? Theme.of(context).colorScheme.error
                      : Colors.white54,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),

          // Live Audio Equalizer / Sound Level Bars
          if (_isListening) ...[
            const SizedBox(height: 12),
            _buildAudioVisualizer(),
          ],

          const SizedBox(height: 20),
          if (_isListening)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: _committedText,
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      TextSpan(
                        text: _committedText.isEmpty ? _currentSegment : ' $_currentSegment',
                        style: const TextStyle(
                          color: Color(0xFFFFBF00),
                          fontStyle: FontStyle.italic,
                          fontSize: 18,
                        ),
                      ),
                      if (_committedText.isEmpty && _currentSegment.isEmpty)
                        const TextSpan(
                          text: 'Speak freely... (continuous stream)',
                          style: TextStyle(color: Colors.white38, fontSize: 15),
                        ),
                    ]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 40),

          // Mic Capture Button
          GestureDetector(
            onTap: _isListening ? _stopListening : _startListening,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                final double soundScale = _isListening
                    ? 1.0 + (math.min(1.0, (_soundLevel.abs() / 20.0)) * 0.15)
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
                            ? Theme.of(context).colorScheme.error.withOpacity(0.6)
                            : Colors.white10,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _isListening
                              ? (hasAudioActivity
                                  ? Colors.redAccent.withOpacity(0.4)
                                  : Theme.of(context)
                                      .colorScheme
                                      .error
                                      .withOpacity(0.2))
                              : Colors.black54,
                          blurRadius: _isListening ? 26 : 20,
                          spreadRadius: _isListening ? 8 : 5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isListening
                          ? Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.error,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            )
                          : Icon(
                              Icons.mic,
                              size: 60,
                              color: Theme.of(context).primaryColor,
                            ),
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
                    : 'Global Hotkey: Ctrl+Shift+B from anywhere',
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
    final double normalized = math.min(1.0, math.max(0.08, _soundLevel.abs() / 15.0));

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
            color: normalized > 0.15 ? const Color(0xFFFFBF00) : Colors.white24,
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
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
