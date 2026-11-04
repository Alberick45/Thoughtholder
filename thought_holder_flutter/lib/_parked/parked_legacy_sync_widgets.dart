import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import '../app_theme.dart';

/// PARKED CODE: Phase 5 Item 2 Bluetooth Lock-down
///
/// The widgets below previously provided legacy "Send only" and "Receive only"
/// manual buttons on the Bluetooth sync screen. These manual one-way paths bypassed
/// mutual paired verification and permitted unencrypted transfers.
///
/// Per Phase 5 Item 2 Requirement 2, these unreferenced pieces are parked here rather
/// than deleted outright.
class ParkedLegacySyncWidgets {
  /// Builds the legacy "Send only" UI card with scanner controls.
  static Widget buildSendOnlyCard({
    required BuildContext context,
    required AppColors colors,
    required bool isScanning,
    required VoidCallback onToggleScan,
    required List<BleDevice> devices,
    required void Function(BleDevice) onSendToDevice,
  }) {
    return Container(
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
                  onPressed: onToggleScan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isScanning ? colors.bad : colors.gold,
                    foregroundColor: Colors.black,
                  ),
                  child: Text(isScanning ? 'Stop scan' : 'Scan devices'),
                ),
              ),
            ],
          ),
          if (devices.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...devices.map((d) => ListTile(
                  dense: true,
                  title: Text(d.name ?? d.deviceId, style: appFont(color: colors.text)),
                  trailing: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => onSendToDevice(d),
                      style: ElevatedButton.styleFrom(backgroundColor: colors.gold),
                      child: const Text('Send'),
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  /// Builds the legacy "Receive only" UI card.
  static Widget buildReceiveOnlyCard({
    required BuildContext context,
    required AppColors colors,
    required bool isReceiving,
    required VoidCallback onToggleReceive,
  }) {
    return Container(
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
                isReceiving ? 'Waiting for sender...' : 'Offline',
                style: appFont(
                  color: isReceiving ? colors.done : colors.mute,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: onToggleReceive,
              style: ElevatedButton.styleFrom(
                backgroundColor: isReceiving ? colors.bad : colors.gold,
                foregroundColor: Colors.black,
              ),
              child: Text(isReceiving ? 'Stop receiving' : 'Start receiving'),
            ),
          ),
        ],
      ),
    );
  }
}

