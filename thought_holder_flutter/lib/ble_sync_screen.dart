import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_ble/universal_ble.dart';
import 'ble_sync_service.dart';
import 'sender_service.dart';
import 'receiver_service.dart';
import 'transfer_progress.dart';
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

  // Legacy Send state (under Advanced)
  List<BleDevice> _devices = [];
  BleDevice? _sendingTo;
  StreamSubscription? _devSub;
  StreamSubscription? _sendProgressSub;
  bool _isScanning = false;

  // Legacy Receive state (under Advanced)
  bool _isReceiving = false;
  StreamSubscription? _receiveProgressSub;
  StreamSubscription? _syncCompleteSub;
  StreamSubscription? _mergeProgressSub;

  bool _isAdvancedExpanded = false;

  @override
  void initState() {
    super.initState();

    final sender = context.read<SenderService>();
    final receiver = context.read<ReceiverService>();
    final settings = context.read<SettingsService>();
    _bleSync = BleSyncService(sender: sender, receiver: receiver, settings: settings);

    _devSub = _bleSync.nearbyDevices.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });

    _sendProgressSub = _bleSync.sendProgress.listen((p) {
      // Progress event received
    });

    _receiveProgressSub = _bleSync.receiveProgress.listen((p) {
      if (mounted && p is TransferProgress) {
        if (p.status == TransferStatus.failed) {
          _showSnack('Sync failed: ${p.error ?? 'Unknown error'}');
        }
      }
    });

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
    _devSub?.cancel();
    _sendProgressSub?.cancel();
    _receiveProgressSub?.cancel();
    _syncCompleteSub?.cancel();
    _mergeProgressSub?.cancel();
    if (_isScanning) _bleSync.stopScan();
    if (_isReceiving) _bleSync.stopReceiving();
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

  // --- Advanced Legacy One-Way Controls ---

  Future<void> _toggleScan() async {
    if (_isScanning) {
      await _bleSync.stopScan();
      setState(() { _isScanning = false; _devices = []; });
    } else {
      try {
        setState(() { _isScanning = true; _devices = []; });
        await _bleSync.startScan();
      } catch (e) {
        setState(() => _isScanning = false);
        _showSnack('Scan failed: $e');
      }
    }
  }

  Future<void> _toggleReceive() async {
    if (_isReceiving) {
      await _bleSync.stopReceiving();
      setState(() {
        _isReceiving = false;
      });
    } else {
      try {
        await _bleSync.startReceiving();
        setState(() => _isReceiving = true);
      } catch (e) {
        _showSnack('Failed to start receiving: $e');
      }
    }
  }

  Future<void> _syncTo(BleDevice device) async {
    if (_sendingTo != null) return;
    await _bleSync.stopScan();
    setState(() { _isScanning = false; _sendingTo = device; });
    try {
      await _bleSync.syncTo(device);
      _showSnack('Ideas copied to ${device.name ?? device.deviceId}!');
    } catch (e) {
      _showSnack('Sync failed: $e');
    } finally {
      if (mounted) setState(() { _sendingTo = null; });
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

              // ──────────────────────────────────────────────────────────────
              // 4. "ADVANCED" COLLAPSED SECTION (Section 8)
              // ──────────────────────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.line),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: _isAdvancedExpanded,
                    onExpansionChanged: (exp) => setState(() => _isAdvancedExpanded = exp),
                    iconColor: colors.gold,
                    collapsedIconColor: colors.mute,
                    title: Text(
                      'Advanced',
                      style: appFont(
                        color: colors.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      'One-way copy modes',
                      style: appFont(color: colors.mute, fontSize: 12),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Copies ideas to the other device. Does not bring back changes.',
                              style: appFont(color: colors.mute, fontSize: 13, height: 1.4),
                            ),
                            const SizedBox(height: 16),

                            // Send Only
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.bg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colors.line),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Send only',
                                        style: appFont(
                                          color: colors.text,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(
                                        height: 48,
                                        child: ElevatedButton(
                                          onPressed: _toggleScan,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _isScanning ? colors.bad : colors.gold,
                                            foregroundColor: Colors.black,
                                          ),
                                          child: Text(_isScanning ? 'Stop scan' : 'Scan devices'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_devices.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    ..._devices.map((d) => ListTile(
                                          dense: true,
                                          title: Text(d.name ?? d.deviceId, style: appFont(color: colors.text)),
                                          trailing: SizedBox(
                                            height: 48,
                                            child: ElevatedButton(
                                              onPressed: () => _syncTo(d),
                                              style: ElevatedButton.styleFrom(backgroundColor: colors.gold),
                                              child: const Text('Send'),
                                            ),
                                          ),
                                        )),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Receive Only
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.bg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colors.line),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Receive only',
                                        style: appFont(
                                          color: colors.text,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        _isReceiving ? 'Waiting for sender...' : 'Offline',
                                        style: appFont(
                                          color: _isReceiving ? colors.done : colors.mute,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: _toggleReceive,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isReceiving ? colors.bad : colors.gold,
                                        foregroundColor: Colors.black,
                                      ),
                                      child: Text(_isReceiving ? 'Stop receiving' : 'Start receiving'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
