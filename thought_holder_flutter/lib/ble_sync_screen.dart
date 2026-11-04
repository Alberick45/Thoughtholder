import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_ble/universal_ble.dart';
import 'ble_sync_service.dart';
import 'sender_service.dart';
import 'receiver_service.dart';
import 'thought_provider.dart';
import 'settings_service.dart';
import 'app_theme.dart';
import 'paired_devices_screen.dart';
import 'ble_merge_engine.dart';

class BleSyncScreen extends StatefulWidget {
  const BleSyncScreen({super.key});

  @override
  State<BleSyncScreen> createState() => _BleSyncScreenState();
}

class _BleSyncScreenState extends State<BleSyncScreen>
    with SingleTickerProviderStateMixin {
  late BleSyncService _bleSync;

  // Symmetrical / 2-Way Sync State
  bool _isSyncing = false;
  String _syncStatusMessage = '';
  double _syncProgressVal = 0.0;
  MergeResult? _lastMergeResult;
  bool _showSummary = false;
  String? _connectedDeviceName;

  StreamSubscription? _syncCompleteSub;
  StreamSubscription? _mergeProgressSub;


  @override
  void initState() {
    super.initState();

    final sender = context.read<SenderService>();
    final receiver = context.read<ReceiverService>();
    final settings = context.read<SettingsService>();
    _bleSync = BleSyncService(sender: sender, receiver: receiver, settings: settings);

    // 2-Way Merge Progress listener
    _mergeProgressSub = _bleSync.mergeProgress.listen((update) {
      if (!mounted) return;
      setState(() {
        _syncStatusMessage = update.message;
        _syncProgressVal = update.progress;
        if (update.isCompleted) {
          _isSyncing = false;
          _showSummary = true;
          _lastMergeResult = update.result;
          context.read<ThoughtProvider>().loadAll();
        } else if (update.error != null) {
          _isSyncing = false;
          _showSnack('Sync stopped. Nothing was changed. Try again.');
        }
      });
    });

    _syncCompleteSub = _bleSync.onSyncComplete.listen((count) {
      if (mounted) {
        context.read<ThoughtProvider>().loadThoughts();
        _showSnack('Synced $count ${count == 1 ? 'idea' : 'ideas'}!');
      }
    });
  }

  @override
  void dispose() {
    _syncCompleteSub?.cancel();
    _mergeProgressSub?.cancel();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF141416),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ignore: unused_element
  Future<void> _startTwoWaySync() async {
    final settings = context.read<SettingsService>();
    final pairedMap = settings.getPairedDevices();

    if (pairedMap.isEmpty) {
      // Need to pair first
      final goPair = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final colors = AppColors.of(settings.theme);
          return AlertDialog(
            backgroundColor: colors.card,
            title: Text('Pair a device first', style: appFont(color: colors.text, fontWeight: FontWeight.bold)),
            content: Text(
              'To sync ideas safely, confirm a 6-digit code with your nearby phone or laptop.',
              style: appFont(color: colors.mute, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Not now', style: appFont(color: colors.mute)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.gold,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Pair now'),
              ),
            ],
          );
        },
      );

      if (goPair == true && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PairedDevicesScreen()),
        );
      }
      return;
    }

    // Pick first paired device
    final targetEntry = pairedMap.values.first as Map;
    final targetId = targetEntry['deviceId'] as String;
    final targetName = targetEntry['name'] as String? ?? 'Nearby device';

    setState(() {
      _isSyncing = true;
      _connectedDeviceName = targetName;
      _syncStatusMessage = 'Connecting to $targetName...';
      _syncProgressVal = 0.1;
      _showSummary = false;
    });

    try {
      final bleDevice = BleDevice(deviceId: targetId, name: targetName);
      await _bleSync.syncTwoWay(bleDevice);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
        _showSnack('Sync stopped. Nothing was changed. Try again.');
      }
    }
  }

  void _cancelSync() {
    setState(() {
      _isSyncing = false;
      _syncStatusMessage = '';
    });
    _showSnack('Sync cancelled. Nothing was changed.');
  }

  Future<void> _undoSync() async {
    final provider = context.read<ThoughtProvider>();
    final success = await provider.restoreFromLatestSnapshot();

    if (mounted) {
      setState(() => _showSummary = false);
      if (success) {
        _showSnack(
          'Restored to previous state. Sync again on your other device if you want them to match.',
        );
      } else {
        _showSnack('Could not restore previous state.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);
    final lastSyncInfo = settings.getLastSyncInfo();

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(
          'Sync with nearby device',
          style: appFont(
            color: colors.text,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        backgroundColor: colors.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.gold),
        actions: [
          IconButton(
            icon: Icon(Icons.devices, color: colors.gold),
            tooltip: 'Paired devices',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PairedDevicesScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ──────────────────────────────────────────────────────────────
              // 1. WHILE SYNCING: ONE CALM SCREEN (Section 8)
              // ──────────────────────────────────────────────────────────────
              if (_isSyncing) ...[
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.gold, width: 1.5),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(
                          value: _syncProgressVal > 0 ? _syncProgressVal : null,
                          strokeWidth: 3.5,
                          color: colors.gold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _syncStatusMessage,
                        textAlign: TextAlign.center,
                        style: appFont(
                          color: colors.text,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Connected to ${_connectedDeviceName ?? 'device'}.\nKeep this screen open while syncing.',
                        textAlign: TextAlign.center,
                        style: appFont(color: colors.mute, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        width: 140,
                        child: OutlinedButton(
                          onPressed: _cancelSync,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.line),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: appFont(color: colors.mute, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ]

              // ──────────────────────────────────────────────────────────────
              // 2. RESULT SUMMARY SCREEN (Section 8)
              // ──────────────────────────────────────────────────────────────
              else if (_showSummary && _lastMergeResult != null) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.gold, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: colors.done, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            'Sync complete',
                            style: appFont(
                              color: colors.text,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _lastMergeResult!.toPlainSummary(),
                        style: appFont(
                          color: colors.text,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => setState(() => _showSummary = false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.gold,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Done',
                            style: appFont(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _undoSync,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.bad.withValues(alpha: 0.6)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Undo this sync',
                            style: appFont(color: colors.bad, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ]

              // ──────────────────────────────────────────────────────────────
              // 3. IDLE: UNIFIED "SYNC NOW" CARD (Section 8)
              // ──────────────────────────────────────────────────────────────
              else ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.line),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.sync, size: 48, color: colors.gold),
                      const SizedBox(height: 16),
                      Text(
                        'Keep both devices up to date',
                        style: appFont(
                          color: colors.text,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Make your phone and laptop end up with the same ideas, buckets and states.',
                        textAlign: TextAlign.center,
                        style: appFont(color: colors.mute, fontSize: 14, height: 1.3),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: null,
                          icon: Icon(Icons.sync_disabled, color: colors.mute, size: 22),
                          label: Text(
                            'Sync is being updated.',
                            style: appFont(
                              color: colors.mute,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.card,
                            disabledBackgroundColor: colors.card,
                            side: BorderSide(color: colors.line),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        lastSyncInfo != null
                            ? 'Last sync: $lastSyncInfo'
                            : 'Last sync: Never synced',
                        style: appFont(color: colors.mute, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
