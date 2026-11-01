import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_theme.dart';
import 'settings_service.dart';
import 'sync_identity.dart';
import 'ble_crypto.dart';

class PairedDevicesScreen extends StatefulWidget {
  const PairedDevicesScreen({super.key});

  @override
  State<PairedDevicesScreen> createState() => _PairedDevicesScreenState();
}

class _PairedDevicesScreenState extends State<PairedDevicesScreen> {
  void _startPairing() {
    final code = BleCrypto.generatePairingCode();

    showDialog(
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
            'Pair a device',
            style: appFont(
              color: colors.text,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Make sure both devices show this same 6-digit code:',
                style: appFont(color: colors.mute, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.gold, width: 2),
                ),
                child: Text(
                  code,
                  style: appFont(
                    color: colors.gold,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Once confirmed, your devices will sync seamlessly without asking again.',
                textAlign: TextAlign.center,
                style: appFont(color: colors.mute, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: appFont(color: colors.mute)),
            ),
            ElevatedButton(
              onPressed: () async {
                final settings = context.read<SettingsService>();
                final peerId = SyncIdentity.newUuid();
                final sharedKey = BleCrypto.deriveSharedKey(
                  code,
                  SyncIdentity.getDeviceId(settings),
                  peerId,
                );
                await settings.savePairedDevice(
                  peerId,
                  'Nearby Device',
                  sharedKey,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Device paired successfully!'),
                      backgroundColor: const Color(0xFF141416),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.gold,
                foregroundColor: Colors.black,
              ),
              child: const Text('Confirm match'),
            ),
          ],
        );
      },
    );
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
                            lastSyncStr = 'Last sync: ${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
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
                                  onPressed: () async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    await settings.removePairedDevice(id);
                                    if (mounted) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text('Device forgotten'),
                                          backgroundColor: Color(0xFF141416),
                                        ),
                                      );
                                    }
                                  },
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: colors.bad.withOpacity(0.5)),
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
                  onPressed: _startPairing,
                  icon: const Icon(Icons.add, color: Colors.black),
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
