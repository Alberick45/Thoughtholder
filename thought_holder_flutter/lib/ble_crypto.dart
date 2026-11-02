import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as c;

/// Cryptographic services for BLE pairing, encryption, and authentication.
class BleCrypto {
  static final Random _secureRandom = Random.secure();
  static final c.X25519 _x25519 = c.X25519();

  /// Generates an ephemeral X25519 keypair for pairing.
  static Future<c.SimpleKeyPair> generateX25519KeyPair() async {
    return await _x25519.newKeyPair();
  }

  /// Exports an X25519 public key to base64Url string.
  static Future<String> exportPublicKey(c.SimpleKeyPair keyPair) async {
    final pubKey = await keyPair.extractPublicKey();
    return base64Url.encode(pubKey.bytes);
  }

  /// Computes the 32-byte shared secret from local keypair and remote public key (base64Url).
  static Future<List<int>> computeSharedSecret({
    required c.SimpleKeyPair localKeyPair,
    required String remotePublicKeyBase64,
  }) async {
    final remoteBytes = base64Url.decode(remotePublicKeyBase64);
    if (remoteBytes.length != 32) {
      throw const FormatException('Remote public key must be 32 bytes');
    }
    final remoteKey = c.SimplePublicKey(remoteBytes, type: c.KeyPairType.x25519);
    final secret = await _x25519.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remoteKey,
    );
    return await secret.extractBytes();
  }

  /// Standard RFC 5869 HKDF-SHA256 Extract and Expand.
  static Uint8List hkdfSha256(
    List<int> ikm, {
    List<int>? salt,
    List<int>? info,
    int length = 32,
  }) {
    final actualSalt = (salt == null || salt.isEmpty) ? Uint8List(32) : Uint8List.fromList(salt);
    final actualInfo = info ?? <int>[];
    // Extract: PRK = HMAC-SHA256(salt, IKM)
    final prk = Hmac(sha256, actualSalt).convert(ikm).bytes;
    // Expand: OKM = HMAC-SHA256(PRK, info || 0x01)
    final okm = Hmac(sha256, prk).convert([...actualInfo, 0x01]).bytes;
    return Uint8List.fromList(okm.sublist(0, length));
  }

  /// Derives pairing keys from X25519 shared secret:
  /// - 'authKey': 32 bytes `List<int>` (for SAS code and HMAC proof)
  /// - 'syncKey': 32 bytes base64Url String (for session encryption)
  static Map<String, dynamic> derivePairingKeys({
    required List<int> sharedSecret,
    required String salt,
  }) {
    final saltBytes = utf8.encode(salt);
    final authKey = hkdfSha256(
      sharedSecret,
      salt: saltBytes,
      info: utf8.encode('ThoughtHolder-Auth-v1'),
      length: 32,
    );
    final syncKeyBytes = hkdfSha256(
      sharedSecret,
      salt: saltBytes,
      info: utf8.encode('ThoughtHolder-Sync-v1'),
      length: 32,
    );
    return {
      'authKey': authKey,
      'syncKey': base64Url.encode(syncKeyBytes),
    };
  }

  /// Calculates deterministic 6-digit Short Authentication String (SAS).
  /// Both devices calculate the exact same code from authKey and sorted IDs.
  static String calculateSasCode({
    required List<int> authKey,
    required String deviceIdA,
    required String deviceIdB,
    required String token,
  }) {
    final sorted = [deviceIdA, deviceIdB]..sort();
    final hmac = Hmac(sha256, authKey);
    final digest = hmac.convert(utf8.encode('sas:${sorted[0]}:${sorted[1]}:$token')).bytes;
    final int val = ((digest[0] & 0x7F) << 24) |
        (digest[1] << 16) |
        (digest[2] << 8) |
        digest[3];
    final code = (val % 900000 + 100000).toString();
    return code;
  }

  /// Generates HMAC proof of possession of shared key.
  static String generateHmacProof({
    required List<int> authKey,
    required String role,
    required String myId,
    required String peerId,
    required String token,
  }) {
    final hmac = Hmac(sha256, authKey);
    final digest = hmac.convert(utf8.encode('proof:$role:$myId:$peerId:$token')).bytes;
    return base64Url.encode(digest);
  }

  /// Verifies HMAC proof in constant time.
  static bool verifyHmacProof({
    required List<int> authKey,
    required String role,
    required String myId,
    required String peerId,
    required String token,
    required String proofToVerify,
  }) {
    try {
      final expected = generateHmacProof(
        authKey: authKey,
        role: role,
        myId: myId,
        peerId: peerId,
        token: token,
      );
      final a = base64Url.decode(expected);
      final b = base64Url.decode(proofToVerify);
      if (a.length != b.length) return false;
      int diff = 0;
      for (int i = 0; i < a.length; i++) {
        diff |= a[i] ^ b[i];
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }

  /// Generates a random 16-byte session token (base64Url).
  static String generateSessionToken() {
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return base64Url.encode(bytes);
  }

  /// Generates a random 6-digit pairing verification code (e.g., "482910")
  static String generatePairingCode() {
    final num = _secureRandom.nextInt(900000) + 100000;
    return num.toString();
  }

  /// Derives a deterministic 6-digit Short Authentication String (SAS) from two device IDs and a salt
  static String derivePairingCode(String deviceIdA, String deviceIdB, String salt) {
    final sorted = [deviceIdA, deviceIdB]..sort();
    final input = utf8.encode('${sorted[0]}|${sorted[1]}|$salt');
    final digest = sha256.convert(input);
    final bytes = digest.bytes;
    final int value = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    final positive = value.abs() % 900000 + 100000;
    return positive.toString();
  }

  /// Derives a 32-byte AES/HMAC key from a pairing code and salt (or two device IDs)
  static String deriveKey(String pairingCode, String salt) {
    final raw = '$pairingCode:$salt';
    final keyBytes = sha256.convert(utf8.encode(raw)).bytes;
    return base64Url.encode(keyBytes);
  }

  /// Derives a 32-byte AES/HMAC key from a pairing code and device IDs
  static String deriveSharedKey(String pairingCode, String deviceIdA, String deviceIdB) {
    final sorted = [deviceIdA, deviceIdB]..sort();
    final raw = '${sorted[0]}:$pairingCode:${sorted[1]}';
    final keyBytes = sha256.convert(utf8.encode(raw)).bytes;
    return base64Url.encode(keyBytes);
  }

  /// Encrypts and compresses arbitrary byte data
  static Uint8List encryptData(List<int> plainBytes, String base64Key) {
    final compressed = compress(Uint8List.fromList(plainBytes));
    return encrypt(compressed, base64Key);
  }

  /// Decrypts and decompresses payload
  static List<int> decryptData(List<int> payload, String base64Key) {
    final decrypted = decrypt(Uint8List.fromList(payload), base64Key);
    return decompress(decrypted);
  }

  /// Encrypts bytes using AES-CTR-like stream cipher derived from HMAC-SHA256 with an authentication tag
  static Uint8List encrypt(Uint8List plainBytes, String base64Key) {
    final keyBytes = base64Url.decode(base64Key);

    // Generate 16-byte random IV
    final iv = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      iv[i] = _secureRandom.nextInt(256);
    }

    // Generate keystream blocks using HMAC-SHA256(key, iv || counter)
    final cipherText = Uint8List(plainBytes.length);
    int blockCounter = 0;
    int processed = 0;

    final hmac = Hmac(sha256, keyBytes);

    while (processed < plainBytes.length) {
      final counterBytes = ByteData(4)..setUint32(0, blockCounter, Endian.big);
      final blockInput = Uint8List(16 + 4)
        ..setRange(0, 16, iv)
        ..setRange(16, 20, counterBytes.buffer.asUint8List());

      final keyStreamBlock = hmac.convert(blockInput).bytes;
      final bytesInBlock = min(32, plainBytes.length - processed);

      for (int i = 0; i < bytesInBlock; i++) {
        cipherText[processed + i] = plainBytes[processed + i] ^ keyStreamBlock[i];
      }

      processed += bytesInBlock;
      blockCounter++;
    }

    // Authenticate: HMAC(key, iv || cipherText)
    final authInput = Uint8List(16 + cipherText.length)
      ..setRange(0, 16, iv)
      ..setRange(16, 16 + cipherText.length, cipherText);
    final authTag = hmac.convert(authInput).bytes; // 32 bytes

    // Result format: [16 bytes IV][32 bytes HMAC][Ciphertext]
    final result = Uint8List(16 + 32 + cipherText.length);
    result.setRange(0, 16, iv);
    result.setRange(16, 48, authTag);
    result.setRange(48, result.length, cipherText);

    return result;
  }

  /// Decrypts bytes and verifies authentication tag. Throws exception if authentication fails.
  static Uint8List decrypt(Uint8List payload, String base64Key) {
    if (payload.length < 48) {
      throw const FormatException('Encrypted payload too short');
    }

    final keyBytes = base64Url.decode(base64Key);
    final iv = payload.sublist(0, 16);
    final authTag = payload.sublist(16, 48);
    final cipherText = payload.sublist(48);

    final hmac = Hmac(sha256, keyBytes);

    // Verify HMAC
    final authInput = Uint8List(16 + cipherText.length)
      ..setRange(0, 16, iv)
      ..setRange(16, 16 + cipherText.length, cipherText);
    final expectedTag = hmac.convert(authInput).bytes;

    bool match = true;
    for (int i = 0; i < 32; i++) {
      if (authTag[i] != expectedTag[i]) {
        match = false;
      }
    }

    if (!match) {
      throw const SecurityException('BLE payload authentication failed: Invalid key or corrupted data');
    }

    // Decrypt using keystream
    final plainBytes = Uint8List(cipherText.length);
    int blockCounter = 0;
    int processed = 0;

    while (processed < cipherText.length) {
      final counterBytes = ByteData(4)..setUint32(0, blockCounter, Endian.big);
      final blockInput = Uint8List(16 + 4)
        ..setRange(0, 16, iv)
        ..setRange(16, 20, counterBytes.buffer.asUint8List());

      final keyStreamBlock = hmac.convert(blockInput).bytes;
      final bytesInBlock = min(32, cipherText.length - processed);

      for (int i = 0; i < bytesInBlock; i++) {
        plainBytes[processed + i] = cipherText[processed + i] ^ keyStreamBlock[i];
      }

      processed += bytesInBlock;
      blockCounter++;
    }

    return plainBytes;
  }

  /// Compresses payload using gzip
  static Uint8List compress(Uint8List data) {
    return Uint8List.fromList(gzip.encode(data));
  }

  /// Decompresses payload using gzip
  static Uint8List decompress(Uint8List compressed) {
    return Uint8List.fromList(gzip.decode(compressed));
  }
}

class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);
  @override
  String toString() => 'SecurityException: $message';
}
