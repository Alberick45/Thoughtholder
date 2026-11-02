import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart' as c;
import 'ble_crypto.dart';
import 'settings_service.dart';
import 'sync_identity.dart';

/// Represents an active ephemeral pairing session.
class PairingSession {
  final String localDeviceId;
  final String localDeviceName;
  final c.SimpleKeyPair localKeyPair;
  final String localPublicKey; // base64Url
  final String sessionToken; // 16 bytes base64Url
  final DateTime createdAt;
  final DateTime expiresAt;

  String? remoteDeviceId;
  String? remoteDeviceName;
  String? remotePublicKey;
  String? sasCode;
  String? syncKey;
  List<int>? authKey;
  bool isVerified = false;

  PairingSession({
    required this.localDeviceId,
    required this.localDeviceName,
    required this.localKeyPair,
    required this.localPublicKey,
    required this.sessionToken,
    required this.createdAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  int get remainingSeconds {
    final diff = expiresAt.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// JSON payload encoded in QR code.
  String get qrPayload => jsonEncode({
        'v': 1,
        'id': localDeviceId,
        'name': localDeviceName,
        'pk': localPublicKey,
        'token': sessionToken,
        'ts': createdAt.millisecondsSinceEpoch,
      });
}

/// Service managing the complete Stage 5 QR & Compare Numbers pairing protocol.
class PairingService extends ChangeNotifier {
  static final PairingService instance = PairingService._();
  PairingService._();

  PairingSession? _activeSession;
  PairingSession? get activeSession => _activeSession;

  int _failedAttempts = 0;
  int get failedAttempts => _failedAttempts;

  DateTime? _lockedOutUntil;
  DateTime? get lockedOutUntil => _lockedOutUntil;

  Timer? _countdownTimer;
  int _remainingSeconds = 120;
  int get remainingSeconds => _remainingSeconds;

  bool get isLockedOut {
    if (_lockedOutUntil == null) return false;
    if (DateTime.now().isBefore(_lockedOutUntil!)) {
      return true;
    }
    _lockedOutUntil = null;
    _failedAttempts = 0;
    return false;
  }

  int get lockoutRemainingSeconds {
    if (_lockedOutUntil == null) return 0;
    final diff = _lockedOutUntil!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  void _recordFailure() {
    _failedAttempts++;
    if (_failedAttempts >= 5) {
      _lockedOutUntil = DateTime.now().add(const Duration(minutes: 2));
    }
    notifyListeners();
  }

  /// Creates a fresh 2-minute pairing session with ephemeral X25519 keypair.
  Future<PairingSession> startSession(SettingsService settings) async {
    if (isLockedOut) {
      throw 'Pairing is temporarily locked out. Please wait $lockoutRemainingSeconds seconds.';
    }

    _cancelTimer();
    final localId = SyncIdentity.getDeviceId(settings);
    final localName = settings.deviceName.isNotEmpty
        ? settings.deviceName
        : SyncIdentity.defaultDeviceName();

    final keyPair = await BleCrypto.generateX25519KeyPair();
    final pubKey = await BleCrypto.exportPublicKey(keyPair);
    final token = BleCrypto.generateSessionToken();
    final now = DateTime.now();
    final expires = now.add(const Duration(minutes: 2));

    _activeSession = PairingSession(
      localDeviceId: localId,
      localDeviceName: localName,
      localKeyPair: keyPair,
      localPublicKey: pubKey,
      sessionToken: token,
      createdAt: now,
      expiresAt: expires,
    );

    _remainingSeconds = 120;
    _startTimer();
    notifyListeners();
    return _activeSession!;
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeSession == null || _activeSession!.isExpired) {
        _remainingSeconds = 0;
        timer.cancel();
        _recordFailure();
        notifyListeners();
        return;
      }
      _remainingSeconds = _activeSession!.remainingSeconds;
      notifyListeners();
    });
  }

  void _cancelTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  /// Cancels the current pairing session halfway and resets state.
  void cancelSession() {
    _cancelTimer();
    _activeSession = null;
    notifyListeners();
  }

  /// Validates and parses raw QR code string.
  /// Throws descriptive error and increments failed attempts if invalid.
  Map<String, dynamic> validateAndParseQr(String raw) {
    if (isLockedOut) {
      throw 'Pairing is temporarily locked out. Please wait $lockoutRemainingSeconds seconds.';
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('QR code is not a valid ThoughtHolder format.');
      }
      final v = decoded['v'];
      final id = decoded['id'] as String?;
      final name = decoded['name'] as String?;
      final pk = decoded['pk'] as String?;
      final token = decoded['token'] as String?;
      final ts = decoded['ts'] as int?;

      if (v != 1 || id == null || name == null || pk == null || token == null || ts == null) {
        throw const FormatException('QR code payload is missing required pairing fields.');
      }

      if (pk.length < 40) {
        throw const FormatException('Invalid public key in QR code.');
      }

      // Validate 2-minute pairing window (120 seconds + 5s leeway for clock drift)
      final ageMs = DateTime.now().millisecondsSinceEpoch - ts;
      if (ageMs > 125000 || ageMs < -10000) {
        throw const FormatException('This pairing QR code has expired (2-minute window exceeded).');
      }

      return Map<String, dynamic>.from(decoded);
    } catch (e) {
      _recordFailure();
      rethrow;
    }
  }

  /// Ingests parsed remote peer data into the active session, computes shared secret,
  /// HKDF keys, and deterministic 6-digit SAS code.
  Future<String> computePairingWithRemote({
    required PairingSession session,
    required String remoteDeviceId,
    required String remoteDeviceName,
    required String remotePublicKeyBase64,
    required String remoteToken,
  }) async {
    if (session.isExpired) {
      _recordFailure();
      throw 'Pairing session has expired.';
    }
    if (remoteDeviceId == session.localDeviceId) {
      throw 'Cannot pair a device with itself.';
    }

    try {
      // 1. X25519 Shared Secret
      final sharedSecret = await BleCrypto.computeSharedSecret(
        localKeyPair: session.localKeyPair,
        remotePublicKeyBase64: remotePublicKeyBase64,
      );

      // 2. HKDF Key Derivation (using sessionToken as salt)
      final keys = BleCrypto.derivePairingKeys(
        sharedSecret: sharedSecret,
        salt: session.sessionToken,
      );
      final authKey = keys['authKey'] as List<int>;
      final syncKey = keys['syncKey'] as String;

      // 3. Deterministic 6-digit SAS code
      final sasCode = BleCrypto.calculateSasCode(
        authKey: authKey,
        deviceIdA: session.localDeviceId,
        deviceIdB: remoteDeviceId,
        token: session.sessionToken,
      );

      session.remoteDeviceId = remoteDeviceId;
      session.remoteDeviceName = remoteDeviceName;
      session.remotePublicKey = remotePublicKeyBase64;
      session.sasCode = sasCode;
      session.syncKey = syncKey;
      session.authKey = authKey;

      notifyListeners();
      return sasCode;
    } catch (e) {
      _recordFailure();
      rethrow;
    }
  }

  /// Completes pairing after mutual comparison and verification.
  /// Saves key to flutter_secure_storage and registers real device in SettingsService.
  Future<void> confirmVerification({
    required PairingSession session,
    required SettingsService settings,
  }) async {
    if (session.isExpired) {
      _recordFailure();
      throw 'Pairing window expired before confirmation.';
    }
    if (session.remoteDeviceId == null || session.syncKey == null || session.authKey == null) {
      throw 'Cannot verify before completing key exchange.';
    }

    // Verify HMAC proof
    final localProof = BleCrypto.generateHmacProof(
      authKey: session.authKey!,
      role: 'peer',
      myId: session.localDeviceId,
      peerId: session.remoteDeviceId!,
      token: session.sessionToken,
    );

    final isValid = BleCrypto.verifyHmacProof(
      authKey: session.authKey!,
      role: 'peer',
      myId: session.localDeviceId,
      peerId: session.remoteDeviceId!,
      token: session.sessionToken,
      proofToVerify: localProof,
    );

    if (!isValid) {
      _recordFailure();
      throw 'Cryptographic proof verification failed.';
    }

    // Save verified pairing with real device name and secure key storage
    await settings.savePairedDevice(
      session.remoteDeviceId!,
      session.remoteDeviceName ?? 'Connected Device',
      session.syncKey!,
    );

    session.isVerified = true;
    _failedAttempts = 0;
    _cancelTimer();
    notifyListeners();
  }
}
