import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../thought_provider.dart';
import '../settings_service.dart';
import '../google_drive_service.dart';
import '../ble_sync_screen.dart';
import '../paired_devices_screen.dart';
import '../services/thought_bundle_service.dart';
import 'group_page_scaffold.dart';
import 'settings_state.dart';
import 'settings_widgets.dart';
import 'diagnostics_screen.dart';
import 'export_ideas_dialog.dart';
import 'import_ideas_dialog.dart';

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
  // ignore: unused_field
  bool _isSyncing = false;
  Map<String, dynamic>? _lastImportBackupInfo;

  @override
  void initState() {
    super.initState();
    _checkSignInStatus();
    _checkLastImportBackup();
  }

  Future<void> _checkLastImportBackup() async {
    try {
      final info = await ThoughtBundleService.instance.getLastImportBackupInfo();
      if (mounted) {
        setState(() {
          _lastImportBackupInfo = info;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleUndoImport(AppColors colors) async {
    if (_lastImportBackupInfo == null) return;

    final ideaCount = _lastImportBackupInfo!['ideaCount'] ?? 0;
    final timestamp = _lastImportBackupInfo!['timestamp'] as int? ?? 0;
    final dateStr = timestamp > 0 ? DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal().toString().split('.').first : '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.line),
        ),
        title: Row(
          children: [
            Icon(Icons.undo, color: colors.bad, size: 22),
            const SizedBox(width: 10),
            Text(
              'Undo last import?',
              style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will restore your database to the safety backup created before the import ($ideaCount ideas, saved $dateStr).',
              style: appFont(color: colors.text, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Text(
              'Any ideas created or modified after that import will be reverted.',
              style: appFont(color: colors.mute, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: appFont(color: colors.mute)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.bad,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Confirm Undo'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ThoughtBundleService.instance.undoLastImport();
      await _checkLastImportBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: colors.card,
            content: Text(
              'Import undone. Database restored from pre-import backup.',
              style: appFont(color: colors.text, fontSize: 13),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: colors.bad,
            content: Text(
              'Undo failed: $e',
              style: appFont(color: Colors.white, fontSize: 13),
            ),
          ),
        );
      }
    }
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

  // ignore: unused_element
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

        const SizedBox(height: 10),

        // 3. Diagnostics & backups
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
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
                Icon(Icons.health_and_safety_outlined, color: colors.gold, size: 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Diagnostics & health',
                        style: appFont(
                          color: colors.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Self-checks, database health, and safety backups',
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

        // 4. Export my ideas
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => const ExportIdeasDialog(),
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
                Icon(Icons.file_upload_outlined, color: colors.gold, size: 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Export my ideas',
                        style: appFont(
                          color: colors.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Save a portable .thoughtbundle file for backup or transfer',
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

        // 5. Import ideas from file
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            ImportIdeasFlow.startImport(
              context,
              onImportCompleted: () {
                _checkLastImportBackup();
                try {
                  context.read<ThoughtProvider>().loadAll();
                } catch (_) {}
              },
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
                Icon(Icons.file_download_outlined, color: colors.gold, size: 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Import ideas from file',
                        style: appFont(
                          color: colors.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Import or merge ideas from a .thoughtbundle file',
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

        // 6. Undo this import (visible for 7 days)
        if (_lastImportBackupInfo != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.bad.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.undo, color: colors.bad, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Undo last import',
                        style: appFont(
                          color: colors.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Safety backup available (${_lastImportBackupInfo!['ideaCount'] ?? 0} ideas). Restores pre-import state.',
                        style: appFont(color: colors.mute, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _handleUndoImport(colors),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.bad,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('Undo import'),
                ),
              ],
            ),
          ),
        ],

        // 7. Collapsible Google Drive (under "Show more options")
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
                      onPressed: null,
                      icon: Icon(Icons.sync_disabled, size: 18, color: colors.mute),
                      label: Text(
                        'Sync is being updated.',
                        style: appFont(color: colors.mute, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colors.line),
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
