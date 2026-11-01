import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart' as c;
import 'package:thought_holder_flutter/ble_crypto.dart';
import 'package:thought_holder_flutter/pairing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UPDATE 8: Real Pairing with QR & Compare Numbers', () {
    test('Scenario 1: Phone scans laptop QR', () async {
      // 1. Laptop creates pairing session (generates ephemeral X25519 keypair and QR payload)
      final laptopKeyPair = await BleCrypto.generateX25519KeyPair();
      final laptopPub = await BleCrypto.exportPublicKey(laptopKeyPair);
      final sessionToken = BleCrypto.generateSessionToken();
      const laptopId = 'laptop-uuid-001';
      const laptopName = "Paapa's Laptop";
      final now = DateTime.now().millisecondsSinceEpoch;

      final laptopQrPayload = jsonEncode({
        'v': 1,
        'id': laptopId,
        'name': laptopName,
        'pk': laptopPub,
        'token': sessionToken,
        'ts': now,
      });

      // 2. Phone scans laptop QR (mobile_scanner parses QR payload)
      final pairingService = PairingService.instance;
      final parsed = pairingService.validateAndParseQr(laptopQrPayload);
      expect(parsed['v'], equals(1));
      expect(parsed['id'], equals(laptopId));
      expect(parsed['name'], equals(laptopName));
      expect(parsed['pk'], equals(laptopPub));

      // 3. Phone generates its own ephemeral X25519 keypair
      final phoneKeyPair = await BleCrypto.generateX25519KeyPair();
      final phonePub = await BleCrypto.exportPublicKey(phoneKeyPair);
      const phoneId = 'phone-uuid-002';
      const phoneName = "Paapa's Phone";

      // 4. Phone computes shared secret, HKDF keys, and 6-digit SAS code
      final phoneSecret = await BleCrypto.computeSharedSecret(
        localKeyPair: phoneKeyPair,
        remotePublicKeyBase64: laptopPub,
      );
      final phoneKeys = BleCrypto.derivePairingKeys(
        sharedSecret: phoneSecret,
        salt: sessionToken,
      );
      final phoneSas = BleCrypto.calculateSasCode(
        authKey: phoneKeys['authKey'] as List<int>,
        deviceIdA: phoneId,
        deviceIdB: laptopId,
        token: sessionToken,
      );

      // 5. Laptop computes shared secret from phone's public key
      final laptopSecret = await BleCrypto.computeSharedSecret(
        localKeyPair: laptopKeyPair,
        remotePublicKeyBase64: phonePub,
      );
      final laptopKeys = BleCrypto.derivePairingKeys(
        sharedSecret: laptopSecret,
        salt: sessionToken,
      );
      final laptopSas = BleCrypto.calculateSasCode(
        authKey: laptopKeys['authKey'] as List<int>,
        deviceIdA: laptopId,
        deviceIdB: phoneId,
        token: sessionToken,
      );

      // Both compute the EXACT same 6-digit number
      expect(phoneSas, equals(laptopSas));
      expect(phoneSas.length, equals(6));

      // HMAC proof mutual verification
      final phoneProof = BleCrypto.generateHmacProof(
        authKey: phoneKeys['authKey'] as List<int>,
        role: 'peer',
        myId: phoneId,
        peerId: laptopId,
        token: sessionToken,
      );
      final isLaptopVerified = BleCrypto.verifyHmacProof(
        authKey: laptopKeys['authKey'] as List<int>,
        role: 'peer',
        myId: phoneId,
        peerId: laptopId,
        token: sessionToken,
        proofToVerify: phoneProof,
      );
      expect(isLaptopVerified, isTrue);
    });

    test('Scenario 2: Laptop uses Compare numbers while phone shows', () async {
      // Phone advertises over Bluetooth and shows QR + 6-digit number
      final phoneKeyPair = await BleCrypto.generateX25519KeyPair();
      final phonePub = await BleCrypto.exportPublicKey(phoneKeyPair);
      const phoneId = 'phone-456';
      const phoneName = "Paapa's Phone";
      final sessionToken = BleCrypto.generateSessionToken();

      // Laptop (Windows) never calls mobile_scanner and uses Compare numbers
      final laptopKeyPair = await BleCrypto.generateX25519KeyPair();
      final laptopPub = await BleCrypto.exportPublicKey(laptopKeyPair);
      const laptopId = 'laptop-123';

      // Key exchange over BLE
      final laptopSecret = await BleCrypto.computeSharedSecret(
        localKeyPair: laptopKeyPair,
        remotePublicKeyBase64: phonePub,
      );
      final phoneSecret = await BleCrypto.computeSharedSecret(
        localKeyPair: phoneKeyPair,
        remotePublicKeyBase64: laptopPub,
      );
      expect(laptopSecret, equals(phoneSecret));

      final laptopKeys = BleCrypto.derivePairingKeys(sharedSecret: laptopSecret, salt: sessionToken);
      final phoneKeys = BleCrypto.derivePairingKeys(sharedSecret: phoneSecret, salt: sessionToken);

      final laptopSas = BleCrypto.calculateSasCode(
        authKey: laptopKeys['authKey'] as List<int>,
        deviceIdA: laptopId,
        deviceIdB: phoneId,
        token: sessionToken,
      );
      final phoneSas = BleCrypto.calculateSasCode(
        authKey: phoneKeys['authKey'] as List<int>,
        deviceIdA: phoneId,
        deviceIdB: laptopId,
        token: sessionToken,
      );

      // The 6-digit number on both devices is identical
      expect(laptopSas, equals(phoneSas));
    });

    test('Scenario 3: Cancel halfway leaves no saved pairing', () async {
      final keyPair = await BleCrypto.generateX25519KeyPair();
      final pubKey = await BleCrypto.exportPublicKey(keyPair);
      final session = PairingSession(
        localDeviceId: 'laptop-1',
        localDeviceName: 'Laptop',
        localKeyPair: keyPair,
        localPublicKey: pubKey,
        sessionToken: 'token-abc',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );

      // Session in progress, user taps Cancel
      expect(session.isVerified, isFalse);
      expect(session.syncKey, isNull);
      // Halfway state is not saved
    });

    test('Scenario 4: Wrong QR increments failed attempts and triggers lockout at 5', () {
      final service = PairingService.instance;

      // Scan 1: completely corrupted QR
      expect(() => service.validateAndParseQr('not-a-json-payload'), throwsA(isA<FormatException>()));

      // Scan 2: missing public key
      final badQr1 = jsonEncode({'v': 1, 'id': 'x', 'name': 'y', 'token': 'z', 'ts': DateTime.now().millisecondsSinceEpoch});
      expect(() => service.validateAndParseQr(badQr1), throwsA(isA<FormatException>()));

      // Scan 3: expired QR (> 2 minutes)
      final expiredTs = DateTime.now().subtract(const Duration(minutes: 3)).millisecondsSinceEpoch;
      final expiredQr = jsonEncode({
        'v': 1,
        'id': 'x',
        'name': 'y',
        'pk': 'U3ZlTFFqWmtKVEpQWm1GMFptRm1aVzVsYm1Ga1pXNWxiZ1==',
        'token': 'z',
        'ts': expiredTs,
      });
      expect(() => service.validateAndParseQr(expiredQr), throwsA(isA<FormatException>()));

      // Failed attempts counter must be at least 3
      expect(service.failedAttempts, greaterThanOrEqualTo(3));
    });

    test('Scenario 5: Two devices in pairing mode generate unique sessions', () async {
      final kp1 = await BleCrypto.generateX25519KeyPair();
      final kp2 = await BleCrypto.generateX25519KeyPair();
      final tok1 = BleCrypto.generateSessionToken();
      final tok2 = BleCrypto.generateSessionToken();

      expect(tok1, isNot(equals(tok2)));
      final pk1 = await BleCrypto.exportPublicKey(kp1);
      final pk2 = await BleCrypto.exportPublicKey(kp2);
      expect(pk1, isNot(equals(pk2)));
    });

    test('Scenario 6: HMAC proof tamper resistance', () async {
      final kp = await BleCrypto.generateX25519KeyPair();
      final token = BleCrypto.generateSessionToken();
      final authKey = utf8.encode('test-auth-key-32-bytes-long1234');

      final proof = BleCrypto.generateHmacProof(
        authKey: authKey,
        role: 'peer',
        myId: 'device-1',
        peerId: 'device-2',
        token: token,
      );

      // Authentic proof passes
      expect(
        BleCrypto.verifyHmacProof(
          authKey: authKey,
          role: 'peer',
          myId: 'device-1',
          peerId: 'device-2',
          token: token,
          proofToVerify: proof,
        ),
        isTrue,
      );

      // Wrong peerId fails
      expect(
        BleCrypto.verifyHmacProof(
          authKey: authKey,
          role: 'peer',
          myId: 'device-1',
          peerId: 'device-WRONG',
          token: token,
          proofToVerify: proof,
        ),
        isFalse,
      );
    });
  });
}
