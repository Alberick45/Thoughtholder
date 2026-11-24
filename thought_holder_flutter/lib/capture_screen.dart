import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app_theme.dart';
import 'background_recording_service.dart';
import 'database_helper.dart';
import 'navigation_service.dart';
import 'settings_service.dart';
import 'sound_service.dart';
import 'thought_provider.dart';
import 'voice_recordings_screen.dart';
import 'widgets/swipe_tabs.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with SingleTickerProviderStateMixin {
  String _captureMode = 'voice'; // 'voice' | 'text'
  final TextEditingController _textController = TextEditingController();
  Box? _prefsBox;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initDraftStorage();
  }

  Future<void> _initDraftStorage() async {
    try {
      _prefsBox = await Hive.openBox('app_preferences');
      final draft =
          _prefsBox?.get('draft_thought_text', defaultValue: '') as String?;
      if (draft != null && draft.isNotEmpty && _textController.text.isEmpty) {
        _textController.text = draft;
      }
    } catch (_) {}
    _textController.addListener(_onDraftChanged);
  }

  void _onDraftChanged() {
    _prefsBox?.put('draft_thought_text', _textController.text);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    super.dispose();
  }

  // --- Start Recording Flow (UPDATE 4 & 5) ---
  Future<void> _onRecordPressed() async {
    final settings = context.read<SettingsService>();
    final bgRecorder = context.read<BackgroundRecordingService>();

    // 1. Microphone permission with short plain explanation first
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      if (!mounted) return;
      final proceed = await _showPermissionExplanationDialog(context);
      if (!proceed) return;

      final res = await Permission.microphone.request();
      if (!res.isGranted) return;
    }

    // 2. Notification permission on Android 13+
    if (!kIsWeb && Platform.isAndroid) {
      final notifStatus = await Permission.notification.status;
      if (!notifStatus.isGranted) {
        await Permission.notification.request();
      }
    }

    // 3. Web warning (UPDATE 4 - Section E)
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Keep this screen on while recording.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }

    // 4. First-time recording privacy notice (UPDATE 4 - Section H)
    if (!settings.hasSeenRecordingPrivacyNotice && mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.of(settings.theme).card,
          title: Text(
            'Your voice stays private',
            style: appFont(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: Text(
            'Your voice is sent to Groq to turn it into text. Nothing else leaves your phone.',
            style: appFont(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                settings.setSeenRecordingPrivacyNotice();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.of(settings.theme).gold,
                foregroundColor: Colors.black,
              ),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
    }

    // 5. One-time "Keep recording reliably" tip (UPDATE 4 - Section B)
    if (!kIsWeb &&
        Platform.isAndroid &&
        !settings.hasSeenBatteryOptimizationTip &&
        mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.of(settings.theme).card,
          title: Text(
            'Keep recording reliably',
            style: appFont(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: Text(
            'Some phone brands kill background apps when the screen is off. You can disable battery optimisation for ThoughtHolder so recordings are never cut short.',
            style: appFont(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () {
                settings.setSeenBatteryOptimizationTip();
                Navigator.pop(ctx);
              },
              child: const Text('Not now'),
            ),
            ElevatedButton(
              onPressed: () {
                settings.setSeenBatteryOptimizationTip();
                Navigator.pop(ctx);
                const MethodChannel('com.thoughtholder.app/background_recording')
                    .invokeMethod('openBatteryOptimizationSettings');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.of(settings.theme).gold,
                foregroundColor: Colors.black,
              ),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
    }

    // 6. Start background recording
    await bgRecorder.startRecording(settings);
  }

  Future<bool> _showPermissionExplanationDialog(BuildContext context) async {
    final colors = AppColors.of(context.read<SettingsService>().theme);
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        title: Text(
          'Microphone permission',
          style: appFont(color: colors.text, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'So it can keep recording when your screen is off.',
          style: appFont(color: colors.mute, fontSize: 15, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: appFont(color: colors.mute)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.gold,
              foregroundColor: Colors.black,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  // --- Stop Recording Flow (UPDATE 4 - Section A) ---
  Future<void> _onStopPressed() async {
    final bgRecorder = context.read<BackgroundRecordingService>();
    final settings = context.read<SettingsService>();
    final provider = context.read<ThoughtProvider>();
    final nav = context.read<NavigationNotifier>();

    final audioPath = await bgRecorder.stopRecording(settings: settings);
    if (audioPath == null) return;

    // Navigate to Stream > Unsorted immediately
    nav.goToStream(subTab: 'unsorted');

    // Process and transcribe with feedback and try again
    await bgRecorder.processAndSaveThought(
      audioPath: audioPath,
      thoughtProvider: provider,
      settings: settings,
      onFeedback: (message, {onUndo, onTryAgain}) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message,
              style: appFont(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            backgroundColor: const Color(0xFF141416),
            duration: const Duration(seconds: 6),
            action: onUndo != null
                ? SnackBarAction(
                    label: 'UNDO',
                    textColor: Colors.amber,
                    onPressed: () {
                      SoundService.instance.play(SoundEvent.undo, settings: settings);
                      onUndo();
                    },
                  )
                : (onTryAgain != null
                    ? SnackBarAction(
                        label: 'TRY AGAIN',
                        textColor: Colors.amber,
                        onPressed: onTryAgain,
                      )
                    : null),
          ),
        );
      },
    );
  }

  void _submitText() async {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      FocusScope.of(context).unfocus();
      final provider = context.read<ThoughtProvider>();
      final nav = context.read<NavigationNotifier>();
      final settings = context.read<SettingsService>();
      final messenger = ScaffoldMessenger.of(context);
      final createdThought = await provider.addThought(
        text,
        'thought',
        tags: 'text-entry',
        bucket: 'Raw',
      );
      SoundService.instance.play(SoundEvent.save, settings: settings);
      _textController.clear();
      _prefsBox?.delete('draft_thought_text');

      if (mounted) {
        nav.goToStream(subTab: 'sorted');
        nav.selectBucket('Raw');

        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Saved to Raw',
              style: appFont(color: Colors.amber, fontWeight: FontWeight.bold),
            ),
            backgroundColor: const Color(0xFF141416),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Undo',
              textColor: Colors.amber,
              onPressed: () {
                SoundService.instance.play(SoundEvent.undo, settings: settings);
                provider.moveToTrash(createdThought['id'] as String);
                _textController.text = text;
              },
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final bgRecorder = context.watch<BackgroundRecordingService>();
    final colors = AppColors.of(settings.theme);

    // ========================================================================
    // WHILE RECORDING: ONE BIG THING (UPDATE 4 - Section A & I)
    // The screen shows a large timer (mm:ss), the label "Recording",
    // and ONE big "Stop" button. Nothing else competes with it!
    // ========================================================================
    if (bgRecorder.isRecording) {
      return _buildActiveRecordingScreen(bgRecorder, colors);
    }

    // ========================================================================
    // IDLE STATE (UPDATE 5 - Section A)
    // "Ready", big Record button, Text option.
    // ========================================================================
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 12),

          // Unfinished Recording Recovery Card (UPDATE 4 - F, UPDATE 5 - A)
          if (bgRecorder.hasUnfinishedRecording) ...[
            _buildUnfinishedRecordingCard(bgRecorder, colors),
            const SizedBox(height: 12),
          ],

          // Top Bar: Mode Toggle (Voice / Text) & Voice Recordings List (Requirement 4)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                // Mode Toggle: Voice / Text
                Container(
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: colors.line),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _captureMode = 'voice'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 10),
                          decoration: BoxDecoration(
                            color: _captureMode == 'voice'
                                ? colors.goldBg
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _captureMode == 'voice'
                                  ? colors.gold
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.mic_outlined,
                                size: 18,
                                color: _captureMode == 'voice'
                                    ? colors.gold
                                    : colors.mute,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Voice',
                                style: appFont(
                                  color: _captureMode == 'voice'
                                      ? colors.gold
                                      : colors.mute,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _captureMode = 'text'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 10),
                          decoration: BoxDecoration(
                            color: _captureMode == 'text'
                                ? colors.goldBg
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _captureMode == 'text'
                                  ? colors.gold
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.edit_note,
                                size: 18,
                                color: _captureMode == 'text'
                                    ? colors.gold
                                    : colors.mute,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Text',
                                style: appFont(
                                  color: _captureMode == 'text'
                                      ? colors.gold
                                      : colors.mute,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Voice Recordings Button with badge for number waiting (Part 2: Requirement 4)
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: DatabaseHelper.instance.fetchVoiceRecordings(),
                  builder: (context, snapshot) {
                    final recs = snapshot.data ?? [];
                    final waitingCount = recs.where((r) =>
                        r['status'] == 'saved' ||
                        r['status'] == 'failed' ||
                        r['status'] == 'transcribing').length;

                    return OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.text,
                        side: BorderSide(
                          color: waitingCount > 0 ? colors.gold : colors.line,
                          width: waitingCount > 0 ? 1.5 : 1,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const VoiceRecordingsScreen()),
                        ).then((_) => setState(() {}));
                      },
                      icon: Icon(
                        Icons.library_music_outlined,
                        size: 17,
                        color: waitingCount > 0 ? colors.gold : colors.mute,
                      ),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Voice recordings',
                            style: appFont(
                              color: colors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (waitingCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: colors.gold,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$waitingCount',
                                style: appFont(
                                  color: Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          Expanded(
            child: _captureMode == 'voice'
                ? _buildVoiceIdleMode(colors, settings)
                : _buildTextMode(colors),
          ),
        ],
      ),
    );
  }

  // --- Active Recording View: Large Timer, Label, ONE Big Stop Button ---
  Widget _buildActiveRecordingScreen(
    BackgroundRecordingService bgRecorder,
    AppColors colors,
  ) {
    final isPaused = bgRecorder.isPaused;
    final pauseReason = bgRecorder.pauseReason ?? 'your phone call';

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Large Timer (mm:ss)
              Text(
                bgRecorder.formattedDuration,
                style: appFont(
                  color: colors.gold,
                  fontSize: 64,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 12),

              // Status Label
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: isPaused ? colors.gold : colors.bad,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isPaused ? 'Paused: $pauseReason' : 'Recording',
                    style: appFont(
                      color: isPaused ? colors.gold : colors.bad,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 50),

              // ONE Big "Stop" Button (>= 48px, nothing competes with it)
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: _onStopPressed,
                  icon: const Icon(Icons.stop_rounded, size: 28),
                  label: Text(
                    'Stop',
                    style: appFont(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.bad,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Unfinished Recording Recovery Card (Section F) ---
  Widget _buildUnfinishedRecordingCard(
    BackgroundRecordingService bgRecorder,
    AppColors colors,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.gold, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'We found a recording that didn’t finish. Save it?',
                  style: appFont(
                    color: colors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final path = bgRecorder.unfinishedRecordingPath;
                      if (path != null) {
                        final provider = context.read<ThoughtProvider>();
                        final settings = context.read<SettingsService>();
                        final nav = context.read<NavigationNotifier>();
                        await bgRecorder.discardUnfinishedRecording();
                        nav.goToStream(subTab: 'unsorted');
                        await bgRecorder.processAndSaveThought(
                          audioPath: path,
                          thoughtProvider: provider,
                          settings: settings,
                          onFeedback: (msg, {onUndo, onTryAgain}) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(msg)),
                            );
                          },
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Save it',
                      style: appFont(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => bgRecorder.discardUnfinishedRecording(),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Delete it',
                      style: appFont(
                        color: colors.bad,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Voice Idle Mode (UPDATE 5 - Section A) ---
  Widget _buildVoiceIdleMode(AppColors colors, SettingsService settings) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'READY',
              style: appFont(
                color: colors.mute,
                letterSpacing: 2.5,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 36),

            // Big Record Button (>= 48px target, 140px diameter)
            GestureDetector(
              onTap: _onRecordPressed,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.card,
                      border: Border.all(
                        color: colors.gold,
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.gold.withValues(alpha: 0.15),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        Icons.mic,
                        size: 58,
                        color: colors.gold,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'Tap to record',
              style: appFont(
                color: colors.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            Text(
              'Recording continues when screen turns off',
              style: appFont(
                color: colors.mute,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 30),

            // Option to switch to Text
            TextButton.icon(
              onPressed: () => setState(() => _captureMode = 'text'),
              icon: Icon(Icons.edit_note, color: colors.gold, size: 20),
              label: Text(
                'Or type a thought instead',
                style: appFont(
                  color: colors.gold,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Text Input Mode ---
  Widget _buildTextMode(AppColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  _submitText,
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  _submitText,
            },
            child: SwipeExclusion(
              child: TextField(
                controller: _textController,
              onChanged: (val) {
                final s = context.read<SettingsService>();
                if (val.isNotEmpty && val.endsWith('\n')) {
                  SoundService.instance.play(SoundEvent.keyEnter, settings: s);
                } else if (val.isNotEmpty && val.endsWith(' ')) {
                  SoundService.instance.play(SoundEvent.keySpace, settings: s);
                } else {
                  SoundService.instance.play(SoundEvent.key, settings: s);
                }
              },
              maxLines: 7,
              minLines: 4,
              style: appFont(
                color: colors.text,
                fontSize: 18,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: 'Type your thought here...',
                hintStyle: appFont(color: colors.mute, fontSize: 18),
                filled: true,
                fillColor: colors.card,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: colors.line, width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: colors.gold, width: 2.0),
                ),
                contentPadding: const EdgeInsets.all(20),
              ),
            ),
          ),
        ),
          const SizedBox(height: 16),

          ElevatedButton(
            onPressed: _submitText,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.gold,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
            ),
            child: Text(
              'Save thought',
              style: appFont(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 17,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 10),

          Text(
            'Saves to Unsorted · Press Ctrl+Enter to save',
            textAlign: TextAlign.center,
            style: appFont(
              color: colors.mute,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
