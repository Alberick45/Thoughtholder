import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../ble_crypto.dart';

/// Result of evaluating an incoming Bluetooth write against security rules.
class SecurityCheckResult {
  final bool allowed;
  final String? rejectionReason;
  final String? senderId;
  final int? counter;
  final Uint8List? payload;

  const SecurityCheckResult({
    required this.allowed,
    this.rejectionReason,
    this.senderId,
    this.counter,
    this.payload,
  });

  factory SecurityCheckResult.reject(String reason) => SecurityCheckResult(
        allowed: false,
        rejectionReason: reason,
      );

  factory SecurityCheckResult.accept({
    required String senderId,
    required int counter,
    required Uint8List payload,
  }) =>
      SecurityCheckResult(
        allowed: true,
        senderId: senderId,
        counter: counter,
        payload: payload,
      );
}

/// Enforces the Bluetooth lock-down security rules (Phase 5 Item 2):
/// 1. Receiver does not advertise or accept writes unless a pairing window is open (2 min max).
/// 2. Pairing window closes on success, cancel, or timeout.
/// 3. Authenticates every message by the authenticated header (sender id + monotonic counter + HMAC tag),
///    never by Bluetooth MAC address.
/// 4. Rejects BEFORE reassembly or memory allocation.
/// 5. Caps payload size and write rate.
/// 6. Rejects replayed counters.
/// 7. Unknown/unpaired senders rejected: "This device isn't paired."
class BleSecurityGuard {
  static final BleSecurityGuard instance = BleSecurityGuard._();
  BleSecurityGuard._();

  // Pairing window state (max 2 minutes)
  bool _pairingWindowOpen = false;
  DateTime? _windowExpiresAt;
  Timer? _windowTimer;

  // Monotonic counter tracking per sender ID
  final Map<String, int> _lastSeenCounters = {};
  int Function(String senderId)? counterLookup;
  Future<void> Function(String senderId, int counter)? persistCounter;

  /// Configures disk persistence for monotonic replay counters so they survive app restart.
  void configurePersistence({
    int Function(String senderId)? counterLookup,
    Future<void> Function(String senderId, int counter)? persistCounter,
  }) {
    this.counterLookup = counterLookup;
    this.persistCounter = persistCounter;
  }

  // Rate limiting (sliding window: max 30 writes/second)
  final List<DateTime> _recentWriteTimestamps = [];
  static const int maxWritesPerSecond = 30;

  // Maximum caps: 64 KB per chunk, 5 MB total payload
  static const int maxChunkSize = 64 * 1024;
  static const int maxTotalPayloadSize = 5 * 1024 * 1024;

  bool get isPairingWindowOpen {
    if (!_pairingWindowOpen) return false;
    if (_windowExpiresAt != null && DateTime.now().isAfter(_windowExpiresAt!)) {
      closePairingWindow(reason: 'timeout');
      return false;
    }
    return true;
  }

  int get remainingWindowSeconds {
    if (!isPairingWindowOpen || _windowExpiresAt == null) return 0;
    final diff = _windowExpiresAt!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// Opens a strictly capped pairing window (2 minutes maximum).
  void openPairingWindow({Duration duration = const Duration(minutes: 2)}) {
    _windowTimer?.cancel();
    final effectiveDuration = duration > const Duration(minutes: 2)
        ? const Duration(minutes: 2)
        : duration;

    _pairingWindowOpen = true;
    _windowExpiresAt = DateTime.now().add(effectiveDuration);

    _windowTimer = Timer(effectiveDuration, () {
      closePairingWindow(reason: 'timeout');
    });
  }

  /// Closes the pairing window immediately (on success, cancel, or timeout).
  void closePairingWindow({String reason = 'manual'}) {
    _windowTimer?.cancel();
    _windowTimer = null;
    _pairingWindowOpen = false;
    _windowExpiresAt = null;
  }

  /// Resets state for testing or restart.
  void reset() {
    closePairingWindow();
    _lastSeenCounters.clear();
    _recentWriteTimestamps.clear();
  }

  /// Returns the last seen counter for a sender ID (checks cache then disk persistence).
  int getLastSeenCounter(String senderId) {
    if (_lastSeenCounters.containsKey(senderId)) {
      return _lastSeenCounters[senderId]!;
    }
    final diskVal = counterLookup?.call(senderId) ?? 0;
    _lastSeenCounters[senderId] = diskVal;
    return diskVal;
  }

  /// Manually set the last seen counter (for test setups).
  void setLastSeenCounter(String senderId, int counter) {
    _lastSeenCounters[senderId] = counter;
  }

  /// Packs an authenticated message wire packet:
  /// Header format:
  /// [1 byte Version = 0x01]
  /// [1 byte SenderIdLen]
  /// [SenderIdLen bytes SenderId UTF8]
  /// [8 bytes Counter uint64 BE]
  /// [4 bytes PayloadLen uint32 BE]
  /// [32 bytes HMAC-SHA256 Tag]
  /// [PayloadLen bytes Ciphertext]
  static Uint8List packAuthenticatedMessage({
    required String senderId,
    required int counter,
    required Uint8List payload,
    required String sharedKey,
  }) {
    final senderIdBytes = utf8.encode(senderId);
    if (senderIdBytes.length > 255) {
      throw ArgumentError('Sender ID too long (max 255 bytes)');
    }

    final keyBytes = base64Url.decode(sharedKey);
    final hmac = Hmac(sha256, keyBytes);

    // Encrypt payload using BleCrypto stream cipher
    final ciphertext = BleCrypto.encrypt(payload, sharedKey);

    final headerLen = 1 + 1 + senderIdBytes.length + 8 + 4;
    final headerBytes = Uint8List(headerLen);
    final bd = ByteData.sublistView(headerBytes);

    bd.setUint8(0, 0x01); // Version
    bd.setUint8(1, senderIdBytes.length);
    headerBytes.setRange(2, 2 + senderIdBytes.length, senderIdBytes);
    bd.setUint64(2 + senderIdBytes.length, counter, Endian.big);
    bd.setUint32(2 + senderIdBytes.length + 8, ciphertext.length, Endian.big);

    // Auth Tag over header || ciphertext
    final authInput = Uint8List(headerLen + ciphertext.length)
      ..setRange(0, headerLen, headerBytes)
      ..setRange(headerLen, headerLen + ciphertext.length, ciphertext);
    final tag = hmac.convert(authInput).bytes; // 32 bytes

    // Final packet = [Header][Tag 32 bytes][Ciphertext]
    final packet = Uint8List(headerLen + 32 + ciphertext.length);
    packet.setRange(0, headerLen, headerBytes);
    packet.setRange(headerLen, headerLen + 32, tag);
    packet.setRange(headerLen + 32, packet.length, ciphertext);

    return packet;
  }

  /// Validates an incoming packet BEFORE allocating memory or reassembling.
  /// Enforces all security gates:
  /// 1. Pairing window gate
  /// 2. Rate limit gate
  /// 3. Chunk & payload size gate
  /// 4. Known paired sender gate
  /// 5. Monotonic counter replay gate
  /// 6. Cryptographic HMAC authenticity gate
  SecurityCheckResult validateIncomingWrite({
    required Uint8List packetBytes,
    required String? Function(String senderId) keyLookup,
  }) {
    // 1. Pairing window gate: reject all writes if window is closed
    if (!isPairingWindowOpen) {
      return SecurityCheckResult.reject('Pairing window is closed.');
    }

    // 2. Rate limiting gate: reject before allocating if writes exceed threshold
    final now = DateTime.now();
    _recentWriteTimestamps.removeWhere(
      (ts) => now.difference(ts).inSeconds >= 1,
    );
    if (_recentWriteTimestamps.length >= maxWritesPerSecond) {
      return SecurityCheckResult.reject('Write rate limit exceeded.');
    }
    _recentWriteTimestamps.add(now);

    // 3. Chunk size gate: reject immediately if incoming buffer exceeds max chunk size
    if (packetBytes.length > maxChunkSize) {
      return SecurityCheckResult.reject('Oversized chunk rejected.');
    }

    // Must at least contain Version(1) + SenderIdLen(1)
    if (packetBytes.length < 2) {
      return SecurityCheckResult.reject('Malformed packet: too short.');
    }

    final version = packetBytes[0];
    if (version != 0x01) {
      return SecurityCheckResult.reject('Unsupported message format version.');
    }

    final senderIdLen = packetBytes[1];
    final minHeaderLen = 1 + 1 + senderIdLen + 8 + 4 + 32;
    if (packetBytes.length < minHeaderLen) {
      return SecurityCheckResult.reject('Malformed packet header.');
    }

    final senderId = utf8.decode(packetBytes.sublist(2, 2 + senderIdLen));
    final bd = ByteData.sublistView(packetBytes, 2 + senderIdLen);
    final counter = bd.getUint64(0, Endian.big);
    final payloadLen = bd.getUint32(8, Endian.big);

    // 4. Payload size cap gate: reject BEFORE allocating memory if payload is oversized
    if (payloadLen > maxTotalPayloadSize) {
      return SecurityCheckResult.reject('Oversized payload rejected ($payloadLen bytes).');
    }

    final expectedTotalLen = minHeaderLen + payloadLen;
    if (packetBytes.length != expectedTotalLen) {
      return SecurityCheckResult.reject('Packet size mismatch.');
    }

    // 5. Pairing Key Gate: Unknown/unpaired senders rejected
    final sharedKey = keyLookup(senderId);
    if (sharedKey == null || sharedKey.trim().isEmpty) {
      return SecurityCheckResult.reject("This device isn't paired.");
    }

    // 6. Monotonic Counter / Replay Gate
    final lastSeen = getLastSeenCounter(senderId);
    if (counter <= lastSeen) {
      return SecurityCheckResult.reject(
        'Replay attack detected: counter $counter <= $lastSeen.',
      );
    }

    // 7. Cryptographic HMAC Gate
    final headerLen = 1 + 1 + senderIdLen + 8 + 4;
    final tagOffset = headerLen;
    final receivedTag = packetBytes.sublist(tagOffset, tagOffset + 32);
    final ciphertext = packetBytes.sublist(tagOffset + 32);

    final keyBytes = base64Url.decode(sharedKey.trim());
    final hmac = Hmac(sha256, keyBytes);

    final authInput = Uint8List(headerLen + ciphertext.length)
      ..setRange(0, headerLen, packetBytes.sublist(0, headerLen))
      ..setRange(headerLen, headerLen + ciphertext.length, ciphertext);
    final computedTag = hmac.convert(authInput).bytes;

    // Constant-time tag comparison
    int diff = 0;
    for (int i = 0; i < 32; i++) {
      diff |= receivedTag[i] ^ computedTag[i];
    }
    if (diff != 0) {
      return SecurityCheckResult.reject('Cryptographic authentication failed.');
    }

    // Decrypt payload
    Uint8List decryptedPayload;
    try {
      decryptedPayload = BleCrypto.decrypt(ciphertext, sharedKey.trim());
    } catch (_) {
      return SecurityCheckResult.reject('Decryption failed.');
    }

    // Authentication succeeded: advance monotonic counter and persist to disk
    _lastSeenCounters[senderId] = counter;
    try {
      persistCounter?.call(senderId, counter);
    } catch (_) {}

    return SecurityCheckResult.accept(
      senderId: senderId,
      counter: counter,
      payload: decryptedPayload,
    );
  }
}

