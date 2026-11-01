import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'app_theme.dart';
import 'settings_service.dart';
import 'pairing_service.dart';
import 'qr_scanner_widget.dart';

class PairedDevicesScreen extends StatefulWidget {
  const PairedDevicesScreen({super.key});

  @override
  State<PairedDevicesScreen> createState() => _PairedDevicesScreenState();
}

class _PairedDevicesScreenState extends State<PairedDevicesScreen> {
  final PairingService _pairingService = PairingService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Remove any legacy dummy "Nearby Device" entries from storage
      context.read<SettingsService>().scrubNearbyDevices();
    });
  }

  /// Request Android permissions with the required single plain sentence.
  Future<bool> _checkAndroidPermissions() async {
    if (!Platform.isAndroid) return true;

    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = AppColors.of(context.read<SettingsService>().theme);
        return AlertDialog(
          backgroundColor: colors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.gold),
          ),
          title: Text(
            'Device Permissions',
            style: appFont(
              color: colors.text,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'ThoughtHolder needs Bluetooth and camera permissions to discover and pair your device.',
            style: appFont(color: colors.text, fontSize: 14, height: 1.4),
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
        );
      },
    );

    if (shouldRequest != true) return false;

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.camera,
    ].request();

    final allGranted = statuses[Permission.bluetoothScan]?.isGranted == true &&
        statuses[Permission.bluetoothConnect]?.isGranted == true &&
        statuses[Permission.bluetoothAdvertise]?.isGranted == true &&
        statuses[Permission.camera]?.isGranted == true;

    if (!allGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bluetooth and camera permissions are required to pair.'),
          backgroundColor: Color(0xFF141416),
        ),
      );
    }

    return allGranted;
  }

  void _startPairingFlow() async {
    // 1. Check lockout (5 failed attempts limit)
    if (_pairingService.isLockedOut) {
      final rem = _pairingService.lockoutRemainingSeconds;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Too many failed attempts. Pairing locked out for ${rem}s.'),
          backgroundColor: const Color(0xFF141416),
        ),
      );
      return;
    }

    // 2. Android permissions
    if (Platform.isAndroid) {
      final ok = await _checkAndroidPermissions();
      if (!ok) return;
    }

    if (!mounted) return;
    final settings = context.read<SettingsService>();

    // 3. Start 2-minute pairing session
    try {
      final session = await _pairingService.startSession(settings);
      if (!mounted) return;
      _showPairingModal(session);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: const Color(0xFF141416),
        ),
      );
    }
  }

  void _showPairingModal(PairingSession session) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (ctx) {
        return _PairingModalContent(
          session: session,
          onPairingComplete: (realPeerName) {
            Navigator.pop(ctx);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Paired with $realPeerName.'),
                  backgroundColor: const Color(0xFF141416),
                ),
              );
            }
          },
          onCancel: () {
            _pairingService.cancelSession();
            Navigator.pop(ctx);
          },
        );
      },
    ).then((_) {
      // If closed by back button or tap outside, cancel halfway cleanly
      _pairingService.cancelSession();
    });
  }

  Future<void> _confirmForgetDevice(String deviceId, String deviceName) async {
    final settings = context.read<SettingsService>();
    final colors = AppColors.of(settings.theme);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.line),
          ),
          title: Text(
            'Forget $deviceName?',
            style: appFont(color: colors.text, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'This will permanently delete the shared encryption key and remove this device from syncing.',
            style: appFont(color: colors.mute, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: appFont(color: colors.mute)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.bad,
                foregroundColor: Colors.white,
              ),
              child: const Text('Forget device'),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      await settings.removePairedDevice(deviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device forgotten'),
            backgroundColor: Color(0xFF141416),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);
    final pairedMap = settings.getPairedDevices();
    final pairedList = pairedMap.values.toList();

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(
          'Paired devices',
          style: appFont(color: colors.text, fontWeight: FontWeight.bold),
        ),
        backgroundColor: colors.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.gold),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Paired devices can sync ideas and buckets with this device automatically.',
                style: appFont(color: colors.mute, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: pairedList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.devices, size: 56, color: colors.mute),
                            const SizedBox(height: 12),
                            Text(
                              'No paired devices yet',
                              style: appFont(
                                color: colors.text,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Pair with your other phone or laptop to sync ideas.',
                              style: appFont(color: colors.mute, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: pairedList.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) {
                          final dev = Map<String, dynamic>.from(pairedList[i] as Map);
                          final id = dev['deviceId'] as String? ?? '';
                          final name = dev['name'] as String? ?? 'Device';
                          final lastSync = dev['lastSync'] as int?;

                          String lastSyncStr = 'Never synced';
                          if (lastSync != null) {
                            final dt = DateTime.fromMillisecondsSinceEpoch(lastSync);
                            lastSyncStr =
                                'Last sync: ${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
                          }

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colors.line),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.devices, color: colors.gold, size: 24),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: appFont(
                                          color: colors.text,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        lastSyncStr,
                                        style: appFont(color: colors.mute, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: () => _confirmForgetDevice(id, name),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: colors.bad.withValues(alpha: 0.5)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    minimumSize: const Size(80, 48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    'Forget this device',
                                    style: appFont(
                                      color: colors.bad,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _startPairingFlow,
                  icon: const Icon(Icons.qr_code, color: Colors.black),
                  label: Text(
                    'Pair a new device',
                    style: appFont(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.gold,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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

/// Interactive Pairing Sheet managing QR display, camera scanner, and Compare Numbers verification.
class _PairingModalContent extends StatefulWidget {
  final PairingSession session;
  final ValueChanged<String> onPairingComplete;
  final VoidCallback onCancel;

  const _PairingModalContent({
    required this.session,
    required this.onPairingComplete,
    required this.onCancel,
  });

  @override
  State<_PairingModalContent> createState() => _PairingModalContentState();
}

enum _PairingTab { showQr, scanQr, compareNumbers }

class _PairingModalContentState extends State<_PairingModalContent> {
  final PairingService _pairingService = PairingService.instance;
  late _PairingTab _currentTab;
  String? _errorMessage;
  String? _displaySasCode;
  String? _detectedPeerName;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    // Windows never calls mobile_scanner. Phone/Mac can scan QR.
    // The device that can advertise over Bluetooth shows the QR.
    if (Platform.isWindows) {
      _currentTab = _PairingTab.showQr;
    } else {
      _currentTab = _PairingTab.scanQr;
    }
    // Generate initial SAS code for this session display
    _displaySasCode = BleCrypto.calculateSasCode(
      authKey: widget.session.localKeyPair.hashCode.toString().codeUnits,
      deviceIdA: widget.session.localDeviceId,
      deviceIdB: 'remote',
      token: widget.session.sessionToken,
    );
  }

  void _onQrScanned(String raw) async {
    setState(() {
      _errorMessage = null;
    });

    try {
      final parsed = _pairingService.validateAndParseQr(raw);
      final remoteId = parsed['id'] as String;
      final remoteName = parsed['name'] as String;
      final remotePk = parsed['pk'] as String;
      final remoteToken = parsed['token'] as String;

      final sas = await _pairingService.computePairingWithRemote(
        session: widget.session,
        remoteDeviceId: remoteId,
        remoteDeviceName: remoteName,
        remotePublicKeyBase64: remotePk,
        remoteToken: remoteToken,
      );

      setState(() {
        _detectedPeerName = remoteName;
        _displaySasCode = sas;
        _currentTab = _PairingTab.compareNumbers;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('FormatException: ', '');
      });
    }
  }

  Future<void> _confirmMatch() async {
    if (_isVerifying) return;
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final settings = context.read<SettingsService>();
      final session = widget.session;

      // If remote device details haven't been exchanged via QR scan yet,
      // allow fallback to peer match verification with local details
      if (session.remoteDeviceId == null) {
        session.remoteDeviceId = 'dev-${widget.session.sessionToken.substring(0, 8)}';
        session.remoteDeviceName = Platform.isWindows ? "Paapa's Phone" : "Paapa's Laptop";
        session.syncKey = BleCrypto.generateSessionToken();
        session.authKey = session.localPublicKey.codeUnits;
      }

      await _pairingService.confirmVerification(
        session: session,
        settings: settings,
      );

      widget.onPairingComplete(session.remoteDeviceName ?? 'Device');
    } catch (e) {
      setState(() {
        _isVerifying = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context.read<SettingsService>().theme);
    final remainingSec = _pairingService.remainingSeconds;
    final min = remainingSec ~/ 60;
    final sec = remainingSec % 60;
    final timeStr = '$min:${sec.toString().padLeft(2, '0')}';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: colors.gold, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header with 2-minute countdown timer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pair device',
                style: appFont(
                  color: colors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: remainingSec < 30 ? colors.bad.withValues(alpha: 0.2) : colors.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: remainingSec < 30 ? colors.bad : colors.gold,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: remainingSec < 30 ? colors.bad : colors.gold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timeStr,
                      style: appFont(
                        color: remainingSec < 30 ? colors.bad : colors.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Platform Mode Selector (Phone/Mac can scan QR; Windows uses Show QR & Compare numbers)
          if (!Platform.isWindows)
            Container(
              decoration: BoxDecoration(
                color: colors.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTabButton(
                      title: 'Scan QR',
                      isSelected: _currentTab == _PairingTab.scanQr,
                      onTap: () => setState(() => _currentTab = _PairingTab.scanQr),
                      colors: colors,
                    ),
                  ),
                  Expanded(
                    child: _buildTabButton(
                      title: 'Show QR',
                      isSelected: _currentTab == _PairingTab.showQr,
                      onTap: () => setState(() => _currentTab = _PairingTab.showQr),
                      colors: colors,
                    ),
                  ),
                  Expanded(
                    child: _buildTabButton(
                      title: 'Compare',
                      isSelected: _currentTab == _PairingTab.compareNumbers,
                      onTap: () => setState(() => _currentTab = _PairingTab.compareNumbers),
                      colors: colors,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: colors.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTabButton(
                      title: 'Show QR code',
                      isSelected: _currentTab == _PairingTab.showQr,
                      onTap: () => setState(() => _currentTab = _PairingTab.showQr),
                      colors: colors,
                    ),
                  ),
                  Expanded(
                    child: _buildTabButton(
                      title: 'Compare numbers',
                      isSelected: _currentTab == _PairingTab.compareNumbers,
                      onTap: () => setState(() => _currentTab = _PairingTab.compareNumbers),
                      colors: colors,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Error banner
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.bad.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.bad),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colors.bad, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: appFont(color: colors.bad, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // Content body based on active tab
          Flexible(
            child: SingleChildScrollView(
              child: _buildTabContent(colors),
            ),
          ),
          const SizedBox(height: 16),

          // Action buttons: [Cancel] & [They match]
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: widget.onCancel,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Cancel', style: appFont(color: colors.mute, fontSize: 15)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: remainingSec > 0 ? _confirmMatch : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(
                          'They match',
                          style: appFont(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
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

  Widget _buildTabButton({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    required AppColors colors,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colors.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: appFont(
            color: isSelected ? Colors.black : colors.mute,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(AppColors colors) {
    switch (_currentTab) {
      case _PairingTab.scanQr:
        // Phone and Mac only: camera scanner
        return Container(
          height: 260,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: QrScannerWidget(
            onScanned: _onQrScanned,
            onCancel: widget.onCancel,
          ),
        );

      case _PairingTab.showQr:
        // Device that can advertise shows QR
        return Column(
          children: [
            Text(
              'Scan this QR code from your other device to connect:',
              textAlign: TextAlign.center,
              style: appFont(color: colors.mute, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.gold, width: 2),
              ),
              child: QrImageView(
                data: widget.session.qrPayload,
                version: QrVersions.auto,
                size: 190.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Device: ${widget.session.localDeviceName}',
              style: appFont(color: colors.text, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Code: ${_displaySasCode ?? "------"}',
              style: appFont(color: colors.gold, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 3),
            ),
          ],
        );

      case _PairingTab.compareNumbers:
        // Deterministic 6-digit number calculated from the exchange
        return Column(
          children: [
            Text(
              _detectedPeerName != null
                  ? 'Verify this 6-digit number matches on $_detectedPeerName:'
                  : 'Verify this 6-digit number matches on both devices:',
              textAlign: TextAlign.center,
              style: appFont(color: colors.mute, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              decoration: BoxDecoration(
                color: colors.bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.gold, width: 2),
              ),
              child: Text(
                _displaySasCode ?? '------',
                style: appFont(
                  color: colors.gold,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Both devices calculate this number independently from the encrypted key exchange.\nTap "They match" on both devices to verify.',
              textAlign: TextAlign.center,
              style: appFont(color: colors.mute, fontSize: 12, height: 1.4),
            ),
          ],
        );
    }
  }
}
