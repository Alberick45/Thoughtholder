import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_ble/universal_ble.dart';
import 'ble_sync_service.dart';
import 'sender_service.dart';
import 'receiver_service.dart';
import 'transfer_progress.dart';
import 'thought_provider.dart';

class BleSyncScreen extends StatefulWidget {
  const BleSyncScreen({Key? key}) : super(key: key);

  @override
  State<BleSyncScreen> createState() => _BleSyncScreenState();
}

class _BleSyncScreenState extends State<BleSyncScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late BleSyncService _bleSync;

  // Send state
  List<BleDevice> _devices = [];
  BleDevice? _sendingTo;
  TransferProgress? _sendProgress;
  StreamSubscription? _devSub;
  StreamSubscription? _sendProgressSub;
  bool _isScanning = false;

  // Receive state
  bool _isReceiving = false;
  TransferProgress? _receiveProgress;
  StreamSubscription? _receiveProgressSub;
  StreamSubscription? _syncCompleteSub; // fires after DB merge is done

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final sender = context.read<SenderService>();
    final receiver = context.read<ReceiverService>();
    _bleSync = BleSyncService(sender: sender, receiver: receiver);

    _devSub = _bleSync.nearbyDevices.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });

    _sendProgressSub = _bleSync.sendProgress.listen((p) {
      if (mounted && p is TransferProgress) {
        setState(() => _sendProgress = p);
      }
    });

    _receiveProgressSub = _bleSync.receiveProgress.listen((p) {
      if (mounted && p is TransferProgress) {
        setState(() => _receiveProgress = p);
        if (p.status == TransferStatus.failed) {
          _showSnack('✗ Sync failed: ${p.error ?? 'Unknown error'}');
        }
      }
    });

    // After DB merge completes, reload ThoughtProvider so Stream screen updates
    _syncCompleteSub = _bleSync.onSyncComplete.listen((count) {
      if (mounted) {
        context.read<ThoughtProvider>().loadThoughts();
        _showSnack('✓ $count thought${count == 1 ? '' : 's'} synced to your stream!');
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _devSub?.cancel();
    _sendProgressSub?.cancel();
    _receiveProgressSub?.cancel();
    _syncCompleteSub?.cancel();
    if (_isScanning) _bleSync.stopScan();
    if (_isReceiving) _bleSync.stopReceiving();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1F1F21),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

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
        _receiveProgress = null;
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
    setState(() { _isScanning = false; _sendingTo = device; _sendProgress = null; });
    try {
      await _bleSync.syncTo(device);
      _showSnack('✓ Thoughts synced to ${device.name ?? device.deviceId}!');
    } catch (e) {
      _showSnack('✗ Sync failed: $e');
    } finally {
      if (mounted) setState(() { _sendingTo = null; _sendProgress = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E10),
      appBar: AppBar(
        title: const Text(
          'BLE SYNC',
          style: TextStyle(
            color: Color(0xFFFFBF00),
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
            fontSize: 13,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0E0E10),
        iconTheme: const IconThemeData(color: Color(0xFF8E9192)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFBF00),
          labelColor: const Color(0xFFFFBF00),
          unselectedLabelColor: const Color(0xFF8E9192),
          tabs: const [
            Tab(icon: Icon(Icons.bluetooth_searching), text: 'SEND'),
            Tab(icon: Icon(Icons.bluetooth_audio), text: 'RECEIVE'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSendTab(),
          _buildReceiveTab(),
        ],
      ),
    );
  }

  Widget _buildSendTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'NEARBY DEVICES',
            subtitle: 'Scan to find a ThoughtHolder device in Receive mode.',
          ),
          const SizedBox(height: 16),

          // Scan Toggle Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sendingTo != null ? null : _toggleScan,
              icon: _isScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF0E0E10),
                      ),
                    )
                  : const Icon(Icons.search),
              label: Text(_isScanning ? 'SCANNING...' : 'START SCAN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFBF00),
                foregroundColor: const Color(0xFF0E0E10),
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Send progress
          if (_sendProgress != null) ...[
            _ProgressCard(progress: _sendProgress!, label: 'Sending...'),
            const SizedBox(height: 16),
          ],

          // Device list
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth_disabled,
                            size: 48, color: Colors.white24),
                        const SizedBox(height: 12),
                        Text(
                          _isScanning
                              ? 'Looking for ThoughtHolder devices...'
                              : 'Tap Scan to find nearby devices.',
                          style: const TextStyle(color: Color(0xFF8E9192)),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _devices.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (_, i) {
                      final d = _devices[i];
                      // We scan with a service UUID filter, so every result IS a ThoughtHolder device.
                      // d.services may be null on Windows (not populated in scan results),
                      // so we fall back to true — the hardware-level filter already guarantees it.
                      final isSyncReceiver = d.services == null ||
                          d.services!.isEmpty ||
                          d.services!.any((s) =>
                              s.toLowerCase() == '8a2ba5c0-0af1-4c8e-9a9e-3a1a2e6d9f01');
                      final isSending = _sendingTo?.deviceId == d.deviceId;

                      return ListTile(
                        tileColor: isSyncReceiver
                            ? Colors.teal.withOpacity(0.08)
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: isSyncReceiver
                              ? const BorderSide(
                                  color: Colors.teal, width: 1)
                              : BorderSide.none,
                        ),
                        leading: Icon(
                          isSyncReceiver
                              ? Icons.sync
                              : Icons.bluetooth,
                          color: isSyncReceiver
                              ? Colors.tealAccent
                              : const Color(0xFF8E9192),
                        ),
                        title: Text(
                          d.name?.isNotEmpty == true
                              ? d.name!
                              : 'Unknown Device',
                          style: TextStyle(
                            color: isSyncReceiver
                                ? Colors.tealAccent
                                : Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          isSyncReceiver
                              ? 'QuickLink Device — tap to sync'
                              : d.deviceId,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSyncReceiver
                                ? Colors.teal
                                : Colors.white30,
                          ),
                        ),
                        trailing: isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFFFBF00),
                                ),
                              )
                            : isSyncReceiver
                                ? const Icon(Icons.chevron_right,
                                    color: Colors.teal)
                                : null,
                        onTap: isSyncReceiver && _sendingTo == null
                            ? () => _syncTo(d)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiveTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'RECEIVE MODE',
            subtitle:
                'Make this device discoverable so another ThoughtHolder can sync to it.',
          ),
          const SizedBox(height: 24),

          // Big receive toggle
          Center(
            child: GestureDetector(
              onTap: _toggleReceive,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isReceiving
                      ? Colors.teal.withOpacity(0.15)
                      : Colors.white.withOpacity(0.04),
                  border: Border.all(
                    color: _isReceiving ? Colors.tealAccent : Colors.white24,
                    width: 2,
                  ),
                  boxShadow: _isReceiving
                      ? [
                          BoxShadow(
                            color: Colors.teal.withOpacity(0.3),
                            blurRadius: 30,
                            spreadRadius: 5,
                          )
                        ]
                      : [],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isReceiving
                          ? Icons.bluetooth_audio
                          : Icons.bluetooth_disabled,
                      size: 48,
                      color: _isReceiving
                          ? Colors.tealAccent
                          : Colors.white38,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isReceiving ? 'LISTENING' : 'OFFLINE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: _isReceiving
                            ? Colors.tealAccent
                            : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Center(
            child: Text(
              _isReceiving
                  ? 'Tap to stop advertising'
                  : 'Tap the button to start',
              style: const TextStyle(color: Color(0xFF8E9192), fontSize: 13),
            ),
          ),

          const SizedBox(height: 32),

          // Receive progress
          if (_receiveProgress != null)
            _ProgressCard(progress: _receiveProgress!, label: 'Receiving...'),

          if (_isReceiving && _receiveProgress == null) ...[
            const Center(
              child: Text(
                'Waiting for a sender to connect...',
                style: TextStyle(color: Color(0xFF8E9192)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF8E9192),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final TransferProgress progress;
  final String label;
  const _ProgressCard({required this.progress, required this.label});

  @override
  Widget build(BuildContext context) {
    final percent = (progress.progress * 100).toStringAsFixed(0);
    final speed = progress.speedBytesPerSec;
    final speedStr = speed > 1024
        ? '${(speed / 1024).toStringAsFixed(1)} KB/s'
        : '${speed.toStringAsFixed(0)} B/s';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                progress.status == TransferStatus.completed
                    ? '✓ Done'
                    : label,
                style: const TextStyle(
                    color: Color(0xFFFFBF00),
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
              Text(
                '$percent%',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.progress,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(
              progress.status == TransferStatus.completed
                  ? Colors.tealAccent
                  : const Color(0xFFFFBF00),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 6),
          Text(
            '${_bytes(progress.bytesTransferred)} / ${_bytes(progress.totalBytes)}  •  $speedStr',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _bytes(int b) =>
      b > 1024 * 1024
          ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB'
          : b > 1024
              ? '${(b / 1024).toStringAsFixed(1)} KB'
              : '$b B';
}
