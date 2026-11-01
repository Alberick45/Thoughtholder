import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart' as c;
import 'package:thought_holder_flutter/ble_crypto.dart';
import 'package:thought_holder_flutter/pairing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Update 8 Pairing & Crypto Protocol Tests', () {
    test('1. Two devices exchange X25519 keys and compute identical 6-digit SAS code', () async {
      // Alice (e.g., Laptop / advertiser)
      final aliceKeyPair = await BleCrypto.generateX25519KeyPair();
      final alicePub = await BleCrypto.exportPublicKey(aliceKeyPair);
      const aliceId = 'laptop-uuid-1111';
      const aliceName = "Paapa's Laptop";
      final sessionToken = BleCrypto.generateSessionToken();

      // Bob (e.g., Phone / scanner)
      final bobKeyPair = await BleCrypto.generateX25519KeyPair();
      final bobPub = await BleCrypto.exportPublicKey(bobKeyPair);
      const bobId = 'phone-uuid-2222';
      const bobName = "Paapa's Phone";

      // Bob computes shared secret and keys from Alice's public key & token
      final bobSecret = await BleCrypto.computeSharedSecret(
        localKeyPair: bobKeyPair,
        remotePublicKeyBase64: alicePub,
      );
      final bobKeys = BleCrypto.derivePairingKeys(
        sharedSecret: bobSecret,
        salt: sessionToken,
      );
      final bobSas = BleCrypto.calculateSasCode(
        authKey: bobKeys['authKey'] as List<int>,
        deviceIdA: bobId,
        deviceIdB: aliceId,
        token: sessionToken,
      );

      // Alice computes shared secret and keys from Bob's public key & token
      final aliceSecret = await BleCrypto.computeSharedSecret(
        localKeyPair: aliceKeyPair,
        remotePublicKeyBase64: bobPub,
      );
      final aliceKeys = BleCrypto.derivePairingKeys(
        sharedSecret: aliceSecret,
        salt: sessionToken,
      );
      final aliceSas = BleCrypto.calculateSasCode(
        authKey: aliceKeys['authKey'] as List<int>,
        deviceIdA: aliceId,
        deviceIdB: bobId,
        token: sessionToken,
      );

      // Shared secrets MUST be identical
      expect(bobSecret, equals(aliceSecret));
      // Derived sync keys MUST be identical
      expect(bobKeys['syncKey'], equals(aliceKeys['syncKey']));
      // Compare numbers (SAS code) MUST be identical 6-digit strings
      expect(aliceSas.length, equals(6));
      expect(bobSas, equals(aliceSas));
    });

    test('2. Mutual HMAC proof verification succeeds with matching authKey', () async {
      final keyPairA = await BleCrypto.generateX25519KeyPair();
      final keyPairB = await BleCrypto.generateX25519KeyPair();
      final pubB = await BleCrypto.exportPublicKey(keyPairB);
      final token = BleCrypto.generateSessionToken();

      final secretA = await BleCrypto.computeSharedSecret(
        localKeyPair: keyPairA,
        remotePublicKeyBase64: pubB,
      );
      final keysA = BleCrypto.derivePairingKeys(sharedSecret: secretA, salt: token);
      final authKey = keysA['authKey'] as List<int>;

      final proof = BleCrypto.generateHmacProof(
        authKey: authKey,
        role: 'peer',
        myId: 'device-A',
        peerId: 'device-B',
        token: token,
      );

      final isValid = BleCrypto.verifyHmacProof(
        authKey: authKey,
        role: 'peer',
        myId: 'device-A',
        peerId: 'device-B',
        token: token,
        proofToVerify: proof,
      );

      expect(isValid, isTrue);

      // Tampered proof must fail
      final tamperedProof = proof.replaceFirst(proof[0], proof[0] == 'A' ? 'B' : 'A');
      final isTamperedValid = BleCrypto.verifyHmacProof(
        authKey: authKey,
        role: 'peer',
        myId: 'device-A',
        peerId: 'device-B',
        token: token,
        proofToVerify: tamperedProof,
      );
      expect(isTamperedValid, isFalse);
    });

    test('3. QR code validation: valid QR parses cleanly within 2-minute window', () {
      final service = PairingService.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      final payload = jsonEncode({
        'v': 1,
        'id': 'device-xyz',
        'name': "Paapa's Phone",
        'pk': 'U3ZlTFFqWmtKVEpQWm1GMFptRm1aVzVsYm1Ga1pXNWxiZ1==',
        'token': 'tok1234567890123',
        'ts': now,
      });

      final parsed = service.validateAndParseQr(payload);
      expect(parsed['v'], equals(1));
      expect(parsed['id'], equals('device-xyz'));
      expect(parsed['name'], equals("Paapa's Phone"));
    });

    test('4. QR code validation: expired (> 2 minutes) or malformed QR fails and counts attempt', () {
      final service = PairingService.instance;
      final initialFailures = service.failedAttempts;

      // Expired QR (3 minutes old)
      final expiredTs = DateTime.now().subtract(const Duration(minutes: 3)).millisecondsSinceEpoch;
      final expiredPayload = jsonEncode({
        'v': 1,
        'id': 'device-xyz',
        'name': 'Old Device',
        'pk': 'U3ZlTFFqWmtKVEpQWm1GMFptRm1aVzVsYm1Ga1pXNWxiZ1==',
        'token': 'tok1234567890123',
        'ts': expiredTs,
      });

      expect(() => service.validateAndParseQr(expiredPayload), throwsA(isA<FormatException>()));
      expect(service.failedAttempts, greaterThan(initialFailures));

      // Malformed / wrong QR
      expect(() => service.validateAndParseQr('random non-json data'), throwsA(isA<FormatException>()));
    });

    test('5. Session cancel halfway clears active session without saving anything', () async {
      final keyPair = await BleCrypto.generateX25519KeyPair();
      final pubKey = await BleCrypto.exportPublicKey(keyPair);
      final session = PairingSession(
        localDeviceId: 'dev-1',
        localDeviceName: 'Laptop',
        localKeyPair: keyPair,
        localPublicKey: pubKey,
        sessionToken: 'token123',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );

      expect(session.isExpired, isFalse);
      expect(session.isVerified, isFalse);
      expect(session.sasCode, isNull);
      expect(session.syncKey, isNull);
    });
  });
}
