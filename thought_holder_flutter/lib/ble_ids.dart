/// Custom GATT identifiers for the PK Share protocol.
/// Both the sender and receiver must agree on these — they're how the
/// two apps recognize each other over BLE.
class BleIds {
  BleIds._();

  /// Advertised service UUID. The sender scans for this.
  static const serviceUuid = '8a2ba5c0-0af1-4c8e-9a9e-3a1a2e6d9f01';

  /// Writable characteristic — the sender writes chunks here.
  static const txCharUuid = '8a2ba5c1-0af1-4c8e-9a9e-3a1a2e6d9f01';

  /// Notify characteristic — reserved for the receiver to send an ack /
  /// progress back to the sender. Not wired up yet in this first pass.
  static const statusCharUuid = '8a2ba5c2-0af1-4c8e-9a9e-3a1a2e6d9f01';

  /// Standard Client Characteristic Configuration Descriptor, needed so
  /// centrals can subscribe to notify characteristics.
  static const cccdUuid = '00002902-0000-1000-8000-00805f9b34fb';
}
