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
  static const String _groqApiKeyName = 'th_groq_api_key';

  /// Saves the Groq Whisper API key to OS secure storage.
  static Future<void> saveGroqApiKey(String key) async {
    try {
      await _storage.write(key: _groqApiKeyName, value: key.trim());
    } catch (e) {
      debugPrint('[SecureStorage] Error saving Groq API key: $e');
    }
  }

  /// Retrieves the Groq Whisper API key from OS secure storage.
  static Future<String?> getGroqApiKey() async {
    try {
      return await _storage.read(key: _groqApiKeyName);
    } catch (e) {
      debugPrint('[SecureStorage] Error reading Groq API key: $e');
      return null;
    }
  }

  /// Deletes the Groq Whisper API key from OS secure storage.
  static Future<void> deleteGroqApiKey() async {
    try {
      await _storage.delete(key: _groqApiKeyName);
    } catch (e) {
      debugPrint('[SecureStorage] Error deleting Groq API key: $e');
    }
  }

  /// Self-health test: verifies OS secure storage write, read, and delete cycle.
  static Future<bool> testSecureStorageHealth() async {
    const testKey = 'th_health_check_nonce';
    final testVal = 'nonce_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await _storage.write(key: testKey, value: testVal);
      final readVal = await _storage.read(key: testKey);
      await _storage.delete(key: testKey);
      final afterDelete = await _storage.read(key: testKey);
      return readVal == testVal && (afterDelete == null || afterDelete.isEmpty);
    } catch (e) {
      debugPrint('[SecureStorage] Health check failed: $e');
      return false;
    }
  }

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
