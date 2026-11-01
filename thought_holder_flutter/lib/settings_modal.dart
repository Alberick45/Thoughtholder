import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'google_drive_service.dart';
import 'thought_provider.dart';
import 'ble_sync_screen.dart';
import 'settings_service.dart';
import 'desktop_manager.dart';
import 'voice_transcription_service.dart';
import 'app_theme.dart';
import 'connect_groq_modal.dart';
import 'notifications_settings_screen.dart';
import 'starter_buckets_screen.dart';
import 'paired_devices_screen.dart';
import 'duplicate_finder_screen.dart';
import 'history_screen.dart';

class SettingsModal extends StatefulWidget {
  const SettingsModal({Key? key}) : super(key: key);

  @override
  _SettingsModalState createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  final GoogleDriveService _driveService = GoogleDriveService();
  bool _isSignedIn = false;
  bool _isSyncing = false;

  late TextEditingController _apiKeyController;
  late TextEditingController _promptController;
  bool _controllersInit = false;
  bool _testingGroq = false;
  String? _groqStatusText;

  @override
  void initState() {
    super.initState();
    _checkSignInStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_controllersInit) {
      final settings = context.read<SettingsService>();
      _apiKeyController = TextEditingController(text: settings.groqApiKey);
      _promptController = TextEditingController(text: settings.whisperPrompt);
      _controllersInit = true;
    }
  }

  @override
  void dispose() {
    if (_controllersInit) {
      _apiKeyController.dispose();
      _promptController.dispose();
    }
    super.dispose();
  }

  Future<void> _checkSignInStatus() async {
    try {
      final signedIn = await _driveService.isSignedIn;
      if (mounted) {
        setState(() {
          _isSignedIn = signedIn;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSignedIn = false;
        });
      }
    }
  }

  Future<void> _handleSignIn() async {
    try {
      final success = await _driveService.signIn();
      setState(() {
        _isSignedIn = success;
      });
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Successfully connected to Google Drive')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Text('Sign In Failed', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Google Sign-In failed or was cancelled. If you selected your email and it silently crashed, it means your app is missing its SHA-1 fingerprint in the Google Cloud Console.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  const Text('How to fix:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Run `cd android && ./gradlew signingReport` in your terminal.\n2. Copy the SHA-1 hash for the debug variant.\n3. Go to Google Cloud Console -> APIs & Services -> Credentials.\n4. Add an OAuth 2.0 Client ID for Android and paste the SHA-1 hash and your package name.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Text('Technical Error:\n$e', style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontFamily: 'monospace')),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('UNDERSTOOD'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _handleSignOut() async {
    await _driveService.signOut();
    setState(() {
      _isSignedIn = false;
    });
  }

  Future<void> _handleSync() async {
    setState(() {
      _isSyncing = true;
    });
    
    await _driveService.syncThoughtsToDrive();
    
    if (mounted) {
      context.read<ThoughtProvider>().loadThoughts();
      setState(() {
        _isSyncing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync complete!')),
      );
    }
  }

  Future<void> _openWindowsSetting(String uriString) async {
    final uri = Uri.parse(uriString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Cannot launch $uriString: $e');
    }
  }

  Future<void> _testWhisperConnection(SettingsService settings) async {
    setState(() {
      _testingGroq = true;
      _groqStatusText = null;
    });
    final key = _apiKeyController.text.trim();
    await settings.setGroqApiKey(key);
    await settings.setWhisperPrompt(_promptController.text.trim());

    final reachable = await VoiceTranscriptionService().checkGroqReachability(key);

    if (mounted) {
      setState(() {
        _testingGroq = false;
        _groqStatusText = reachable
            ? '✓ Connected! Whisper Large V3 Turbo is online and ready.'
            : '✗ Failed to reach Groq. Check your internet connection & API key.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsService = context.watch<SettingsService>();
    final thoughtProvider = context.watch<ThoughtProvider>();
    final colors = AppColors.of(settingsService.theme);
    final isDesktop = DesktopManager.isDesktop;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SETTINGS',
                style: appFont(
                  color: colors.gold,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                  fontSize: 16,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: colors.mute),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Appearance & Theme Section ---
                  Row(
                    children: [
                      Icon(Icons.palette_outlined, color: colors.gold, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'APPEARANCE & THEME',
                        style: appFont(
                          color: colors.gold,
                          fontSize: 12,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Theme Mode',
                            style: appFont(
                                color: colors.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _buildThemeOption('Dark', 'dark', Icons.dark_mode_outlined, settingsService, colors),
                            const SizedBox(width: 8),
                            _buildThemeOption('Soft light', 'light', Icons.light_mode_outlined, settingsService, colors),
                            const SizedBox(width: 8),
                            _buildThemeOption('Calm', 'calm', Icons.nightlight_outlined, settingsService, colors),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- Bucket Ordering Section ---
                  Row(
                    children: [
                      Icon(Icons.sort_outlined, color: colors.gold, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'BUCKET ORDERING',
                        style: appFont(
                          color: colors.gold,
                          fontSize: 12,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sorted Tab Bucket Order',
                            style: appFont(
                                color: colors.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _buildOrderOption('Most ideas first', 'ideas', settingsService, colors),
                            const SizedBox(width: 8),
                            _buildOrderOption('Creation order', 'creation', settingsService, colors),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // --- Unsorted Order Section (UPDATE 6 - Section A) ---
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Unsorted order',
                            style: appFont(
                                color: colors.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 6),
                        Text(
                          'Choose whether newest or oldest ideas appear first in Unsorted.',
                          style: appFont(color: colors.mute, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _buildUnsortedOrderOption('Newest first (default)', 'newest', settingsService, colors),
                            const SizedBox(width: 8),
                            _buildUnsortedOrderOption('Oldest first', 'oldest', settingsService, colors),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- Starter Buckets Section (UPDATE 6 - Section C) ---
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, color: colors.gold, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'STARTER BUCKETS',
                        style: appFont(
                          color: colors.gold,
                          fontSize: 12,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Starter buckets',
                          style: appFont(
                            color: colors.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Add any of the standard starter buckets anytime.',
                          style: appFont(color: colors.mute, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        ...kStarterBuckets.map((starter) {
                          final name = starter.name;
                          final iconKey = starter.iconKey;
                          final desc = starter.description;
                          final iconData = kBucketIcons[iconKey] ?? Icons.folder_outlined;
                          final bool isExisting = thoughtProvider.buckets.any((b) =>
                              (b['name'] as String).trim().toLowerCase() ==
                              name.trim().toLowerCase());

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: colors.bg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: colors.line),
                                  ),
                                  child: Icon(iconData, color: colors.gold, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: appFont(
                                          color: colors.text,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        desc,
                                        style: appFont(
                                          color: colors.mute,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isExisting)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: colors.bg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: colors.line),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check,
                                            size: 14, color: colors.done),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Added',
                                          style: appFont(
                                            color: colors.mute,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  SizedBox(
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      onPressed: () async {
                                        await thoughtProvider.addBucket(
                                          name,
                                          icon: iconKey,
                                        );
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Added bucket "$name"',
                                                style: appFont(
                                                    color: Colors.amber,
                                                    fontWeight: FontWeight.bold),
                                              ),
                                              backgroundColor:
                                                  const Color(0xFF141416),
                                              duration:
                                                  const Duration(seconds: 3),
                                            ),
                                          );
                                          setState(() {});
                                        }
                                      },
                                      icon: const Icon(Icons.add, size: 16),
                                      label: const Text('Add'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: colors.gold,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- Whisper AI (Primary) Section ---
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: colors.gold, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'WHISPER AI TRANSCRIBER',
                        style: appFont(
                          color: colors.gold,
                          fontSize: 12,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Quick Launch Wizard Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => const ConnectGroqModal(),
                              );
                            },
                            icon: const Icon(Icons.key, size: 16),
                            label: const Text('Open 4-step Groq Setup Wizard'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.gold,
                              foregroundColor: Colors.black,
                              textStyle: appFont(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Divider(color: Colors.white10, height: 1),
                        const SizedBox(height: 14),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('History view as grid',
                              style: appFont(
                                  color: colors.text,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          subtitle: Text(
                            'Toggle between grid and list view for History screen',
                            style: appFont(color: colors.mute, fontSize: 11),
                          ),
                          value: settingsService.historyGridView,
                          activeColor: colors.gold,
                          onChanged: (val) async {
                            await settingsService.setHistoryGridView(val);
                            setState(() {});
                          },
                        ),
                        // Original Whisper toggle
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Use Whisper AI as Primary',
                              style: appFont(
                                  color: colors.text,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          subtitle: Text(
                            'Uses Groq whisper-large-v3-turbo when online, with automatic offline fallback to device',
                            style: appFont(color: colors.mute, fontSize: 11),
                          ),
                          value: settingsService.useWhisperAsPrimary,
                          activeColor: colors.gold,
                          onChanged: (val) async {
                            await settingsService.setUseWhisperAsPrimary(val);
                            setState(() {});
                          },
                        ),
                        const Divider(color: Colors.white10, height: 20),
                        const Text(
                          'Groq API Key:',
                          style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _apiKeyController,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'gsk_...',
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: Colors.black38,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onChanged: (val) => settingsService.setGroqApiKey(val),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Prompt Priming (Names, Terms & Locations):',
                          style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Primes Whisper so it accurately spells names like Albert, local towns, and technical jargon.',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _promptController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'e.g. Albert, PK, Aaenics, Ghana...',
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: Colors.black38,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onChanged: (val) => settingsService.setWhisperPrompt(val),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _testingGroq ? null : () => _testWhisperConnection(settingsService),
                              icon: _testingGroq
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                  : const Icon(Icons.wifi_tethering, size: 16),
                              label: Text(_testingGroq ? 'CHECKING...' : 'TEST CONNECTION'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                                foregroundColor: Colors.black,
                                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (_groqStatusText != null)
                              Expanded(
                                child: Text(
                                  _groqStatusText!,
                                  style: TextStyle(
                                    color: _groqStatusText!.startsWith('✓') ? Colors.greenAccent : Colors.redAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- Desktop / Laptop Widget Section ---
                  if (isDesktop) ...[
                    const Text(
                      'LAPTOP WIDGET & BACKGROUND DAEMON',
                      style: TextStyle(color: Colors.amber, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.keyboard, color: Colors.amber, size: 20),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text('Global Hotkey Shortcut', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                                ),
                                child: const Text(
                                  'Ctrl + Shift + B',
                                  style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Pops up capture window immediately from any open window or desktop, ready to record your thought.',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          const Divider(color: Colors.white10, height: 24),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Launch at Startup', style: TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: const Text('Starts ThoughtHolder in background on Windows boot', style: TextStyle(color: Colors.white54, fontSize: 11)),
                            value: settingsService.launchAtStartup,
                            activeColor: Colors.amber,
                            onChanged: (val) async {
                              await DesktopManager.instance.toggleLaunchAtStartup(val);
                              setState(() {});
                            },
                          ),
                          const Divider(color: Colors.white10, height: 16),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Close to System Tray', style: TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: const Text('Keeps app running in the system tray when closing window', style: TextStyle(color: Colors.white54, fontSize: 11)),
                            value: settingsService.closeToTray,
                            activeColor: Colors.amber,
                            onChanged: (val) async {
                              await settingsService.setCloseToTray(val);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Laptop Sound & Mic Optimization Section ---
                    const Text(
                      'LAPTOP SOUND & RECOGNITION TUNING',
                      style: TextStyle(color: Colors.cyanAccent, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Online Speech Recognition (Fallback Mode)', style: TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: const Text('Leverages Windows cloud speech engine when Whisper is offline', style: TextStyle(color: Colors.white54, fontSize: 11)),
                            value: settingsService.speechOnline,
                            activeColor: Colors.cyanAccent,
                            onChanged: (val) async {
                              await settingsService.setSpeechOnline(val);
                              setState(() {});
                            },
                          ),
                          const Divider(color: Colors.white10, height: 20),
                          const Text(
                            'Windows Sound & Mic Fixes:',
                            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '• If laptop is not hearing you well, check your input level and active microphone.\n• For testing, use the laptop’s built-in mic or a wired headset to avoid Bluetooth Hands-Free profile audio drop.',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _openWindowsSetting('ms-settings:sound'),
                                  icon: const Icon(Icons.mic, size: 16, color: Colors.cyanAccent),
                                  label: const Text('Sound & Mic Level', style: TextStyle(fontSize: 11, color: Colors.cyanAccent)),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Colors.cyanAccent.withOpacity(0.5)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _openWindowsSetting('ms-settings:speech'),
                                  icon: const Icon(Icons.settings_voice, size: 16, color: Colors.cyanAccent),
                                  label: const Text('Windows Speech', style: TextStyle(fontSize: 11, color: Colors.cyanAccent)),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Colors.cyanAccent.withOpacity(0.5)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // --- Cloud Sync Section ---
                  const Text(
                    'CLOUD SYNC (APPDATA FOLDER)',
                    style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.cloud_done,
                              color: _isSignedIn ? Colors.green : Colors.white24,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Google Drive Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  Text(
                                    _isSignedIn ? 'Connected' : 'Not connected',
                                    style: TextStyle(color: _isSignedIn ? Colors.green : Colors.white54, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            if (_isSignedIn)
                              TextButton(
                                onPressed: _handleSignOut,
                                child: const Text('DISCONNECT', style: TextStyle(color: Colors.redAccent)),
                              )
                            else
                              ElevatedButton(
                                onPressed: _handleSignIn,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).primaryColor,
                                  foregroundColor: Colors.black,
                                ),
                                child: const Text('CONNECT'),
                              )
                          ],
                        ),
                        if (_isSignedIn) ...[
                          const Divider(color: Colors.white10, height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isSyncing ? null : _handleSync,
                              icon: _isSyncing 
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber))
                                : const Icon(Icons.sync),
                              label: Text(_isSyncing ? 'SYNCING...' : 'FORCE SYNC NOW'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Theme.of(context).primaryColor,
                                side: BorderSide(color: Theme.of(context).primaryColor.withOpacity(0.5)),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- BLE Sync Section (UPDATE 7) ---
                  Row(
                    children: [
                      Icon(Icons.sync_outlined, color: colors.gold, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'BLE SYNC (OFFLINE / LOCAL)',
                        style: appFont(
                          color: colors.gold,
                          fontSize: 12,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BleSyncScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.gold.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.bluetooth_connected, color: colors.gold, size: 22),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sync with nearby device',
                                  style: appFont(
                                    color: colors.text,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Merge ideas and buckets offline over Bluetooth',
                                  style: appFont(
                                    color: colors.mute,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: colors.mute),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PairedDevicesScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.line),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.devices_outlined, color: colors.gold, size: 22),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Paired devices',
                                  style: appFont(
                                    color: colors.text,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Trusted devices and 6-digit confirmation codes',
                                  style: appFont(
                                    color: colors.mute,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: colors.mute),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DuplicateFinderScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.line),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.copy_all_outlined, color: colors.gold, size: 22),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Find duplicates',
                                  style: appFont(
                                    color: colors.text,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Review and merge ideas with identical text',
                                  style: appFont(
                                    color: colors.mute,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: colors.mute),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
  onTap: () {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  },
  borderRadius: BorderRadius.circular(12),
  child: Container(
    constraints: const BoxConstraints(minHeight: 56),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: colors.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: colors.line),
    ),
    child: Row(
      children: [
        Icon(Icons.history, color: colors.gold, size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'History',
                style: appFont(
                  color: colors.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Review completed ideas',
                style: appFont(
                  color: colors.mute,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right, color: colors.mute),
      ],
    ),
  ),
),
const SizedBox(height: 24),

                  // --- Notifications & Nudges Section (UPDATE 5) ---
                  Row(
                    children: [
                      Icon(Icons.notifications_outlined, color: colors.gold, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'NOTIFICATIONS & NUDGES',
                        style: appFont(
                          color: colors.gold,
                          fontSize: 12,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const NotificationsSettingsScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.gold.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.notifications_active_outlined,
                              color: colors.gold, size: 22),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Notifications & reminders',
                                  style: appFont(
                                    color: colors.text,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Start here nudges, capture reminders & quiet hours',
                                  style: appFont(
                                    color: colors.mute,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: colors.mute),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption(
    String label,
    String key,
    IconData icon,
    SettingsService settings,
    AppColors colors,
  ) {
    final isSelected = settings.theme == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => settings.setTheme(key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? colors.goldBg : colors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? colors.gold : colors.line,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: isSelected ? colors.gold : colors.mute),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: appFont(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? colors.gold : colors.mute,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderOption(
    String label,
    String key,
    SettingsService settings,
    AppColors colors,
  ) {
    final isSelected = settings.bucketOrder == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => settings.setBucketOrder(key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected ? colors.goldBg : colors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? colors.gold : colors.line,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colors.gold : colors.mute,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnsortedOrderOption(
    String label,
    String key,
    SettingsService settings,
    AppColors colors,
  ) {
    final isSelected = settings.unsortedOrder == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => settings.setUnsortedOrder(key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected ? colors.goldBg : colors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? colors.gold : colors.line,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colors.gold : colors.mute,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

