import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'google_drive_service.dart';
import 'thought_provider.dart';
import 'ble_sync_screen.dart';
import 'settings_service.dart';
import 'desktop_manager.dart';
import 'voice_transcription_service.dart';

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
    final isDesktop = DesktopManager.isDesktop;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
                'SYSTEM SETTINGS',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
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
                  // --- Whisper AI (Primary) Section ---
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'WHISPER AI TRANSCRIBER (PRIMARY)',
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
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
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Use Whisper AI as Primary',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: const Text(
                            'Uses Groq whisper-large-v3-turbo when online, with automatic offline fallback to device',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          value: settingsService.useWhisperAsPrimary,
                          activeColor: Colors.amber,
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

                  // --- BLE Sync Section ---
                  const Text(
                    'BLE SYNC (OFFLINE / LOCAL)',
                    style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BleSyncScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.bluetooth, color: Colors.tealAccent),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'BLE Sync',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Sync thoughts offline with nearby devices',
                                  style: TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.white30),
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
}
