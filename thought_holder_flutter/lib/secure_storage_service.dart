import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure key storage for BLE pairing secrets using hardware-backed keystore/keychain.
class SecureStorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
    wOptions: WindowsOptions(),
  );

  static const String _keyPrefix = 'th_ble_key_';

  /// Saves the symmetric sync key for a paired device.
  static Future<void> saveSharedKey(String peerDeviceId, String sharedKey) async {
    try {
      await _storage.write(key: '$_keyPrefix$peerDeviceId', value: sharedKey);
    } catch (e) {
      debugPrint('[SecureStorage] Error saving key for $peerDeviceId: $e');
    }
  }

  /// Retrieves the symmetric sync key for a paired device.
  static Future<String?> getSharedKey(String peerDeviceId) async {
    try {
      return await _storage.read(key: '$_keyPrefix$peerDeviceId');
    } catch (e) {
      debugPrint('[SecureStorage] Error reading key for $peerDeviceId: $e');
      return null;
    }
  }

  /// Deletes the symmetric sync key for a paired device.
  static Future<void> deleteSharedKey(String peerDeviceId) async {
    try {
      await _storage.delete(key: '$_keyPrefix$peerDeviceId');
    } catch (e) {
      debugPrint('[SecureStorage] Error deleting key for $peerDeviceId: $e');
    }
  }

  /// Clears all stored BLE keys.
  static Future<void> clearAllKeys() async {
    try {
      final all = await _storage.readAll();
      for (final key in all.keys) {
        if (key.startsWith(_keyPrefix)) {
          await _storage.delete(key: key);
        }
      }
    } catch (e) {
      debugPrint('[SecureStorage] Error clearing keys: $e');
    }
  }
}
