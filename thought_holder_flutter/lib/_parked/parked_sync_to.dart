import 'dart:convert';
import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';
import '../database_helper.dart';
import '../sender_service.dart';

/// PARKED CODE: Phase 5 Item 2 Bluetooth Lock-down
///
/// The `syncTo` method below was part of the legacy one-way unencrypted sync path.
/// It transferred raw database records as an unencrypted JSON blob over BLE without
/// pairing key verification, counter replay protection, or authenticated headers.
///
/// Per Phase 5 Item 2 Requirement 2, this unreferenced path is moved here rather than
/// deleted outright.
class ParkedLegacySyncTo {
  static Future<void> syncTo(BleDevice device, SenderService sender) async {
    final db = await DatabaseHelper.instance.database;
    final thoughts = await db.query('thoughts');

    final payload = json.encode({
      'thoughts': thoughts,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'source': 'thought_holder_flutter',
    });

    final bytes = Uint8List.fromList(utf8.encode(payload));

    await sender.sendBytes(
      device,
      bytes,
      type: 'text',
      name: null,
    );
  }
}

