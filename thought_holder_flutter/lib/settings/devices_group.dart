import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../settings_service.dart';
import '../google_drive_service.dart';
import '../ble_sync_screen.dart';
import '../paired_devices_screen.dart';
import 'group_page_scaffold.dart';
import 'settings_state.dart';
import 'settings_widgets.dart';

class DevicesGroupScreen extends StatelessWidget {
  const DevicesGroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GroupPageScaffold(
      title: 'Devices and backup',
      child: DevicesGroupContent(),
    );
  }
}

class DevicesGroupContent extends StatefulWidget {
  const DevicesGroupContent({super.key});

  @override
  State<DevicesGroupContent> createState() => _DevicesGroupContentState();
}

class _DevicesGroupContentState extends State<DevicesGroupContent> {
  static const String _groupId = 'devices_group';

  final GoogleDriveService _driveService = GoogleDriveService();
  bool _isSignedIn = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _checkSignInStatus();
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
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully connected to Google Drive')),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Text('Sign In Failed', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            content: SingleChildScrollView(
              child: Text(e.toString()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              )
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected from Google Drive')),
      );
    }
  }

  Future<void> _handleSync() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      await _driveService.syncThoughtsToDrive();
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync complete!')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync encountered an error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);
    final isExpanded = SettingsState.isExpanded(_groupId);

    final pairedCount = settings.getPairedDevices().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Sync with nearby device
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BleSyncScreen()),
            );
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.line),
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
                      const SizedBox(height: 2),
                      Text(
                        'Merge ideas and buckets offline over Bluetooth',
                        style: appFont(color: colors.mute, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.mute, size: 22),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // 2. Paired devices
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PairedDevicesScreen()),
            );
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.bg,
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
                      const SizedBox(height: 2),
                      Text(
                        '$pairedCount trusted device${pairedCount == 1 ? '' : 's'}',
                        style: appFont(color: colors.mute, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.mute, size: 22),
              ],
            ),
          ),
        ),

        // 3. Collapsible Google Drive (under "Show more options")
        if (isExpanded) ...[
          const SizedBox(height: 20),
          Divider(color: colors.line, height: 1),
          const SizedBox(height: 16),
          Text(
            'Google Drive',
            style: appFont(
              color: colors.text,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sync backup database to your personal Google Drive AppData folder.',
            style: appFont(color: colors.mute, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.line),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.cloud_done,
                      color: _isSignedIn ? colors.done : colors.mute,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Google Drive status',
                            style: appFont(
                              color: colors.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isSignedIn ? 'Connected' : 'Not connected',
                            style: appFont(
                              color: _isSignedIn ? colors.done : colors.mute,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isSignedIn)
                      SizedBox(
                        height: 38,
                        child: TextButton(
                          onPressed: _handleSignOut,
                          child: Text(
                            'Disconnect',
                            style: appFont(color: colors.bad, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 38,
                        child: ElevatedButton(
                          onPressed: _handleSignIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.gold,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Connect'),
                        ),
                      ),
                  ],
                ),
                if (_isSignedIn) ...[
                  const SizedBox(height: 12),
                  Divider(color: colors.line, height: 1),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: _isSyncing ? null : _handleSync,
                      icon: _isSyncing
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.gold,
                              ),
                            )
                          : Icon(Icons.sync, size: 18, color: colors.gold),
                      label: Text(
                        _isSyncing ? 'Syncing…' : 'Force sync now',
                        style: appFont(color: colors.gold, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colors.gold),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),
        ShowMoreButton(
          count: 1,
          isExpanded: isExpanded,
          onTap: () {
            setState(() {
              SettingsState.toggleExpanded(_groupId);
            });
          },
          colors: colors,
        ),
      ],
    );
  }
}
