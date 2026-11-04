import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:thought_holder_flutter/ble_sync_service.dart';
import 'package:thought_holder_flutter/receiver_service.dart';
import 'package:thought_holder_flutter/sender_service.dart';
import 'package:thought_holder_flutter/settings_service.dart';
import 'package:thought_holder_flutter/history_service.dart';
import 'package:thought_holder_flutter/services/ble_security_guard.dart';

// Mock SenderService to track calls to sendBytes
class MockSenderService extends SenderService {
  int sendBytesCalls = 0;
  Uint8List? lastSentBytes;

  @override
  Future<void> sendBytes(
    BleDevice device,
    Uint8List bytes, {
    required String type,
    String? name,
  }) async {
    sendBytesCalls++;
    lastSentBytes = bytes;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
  });


  setUp(() {
    BleSecurityGuard.instance.reset();
  });

  group('Phase 5 Item 2: Bluetooth Lock-down Tests', () {
    const peerDeviceId = 'paired-peer-uuid-2222';
    const unpairedDeviceId = 'unpaired-attacker-uuid-9999';
    final sharedKey = base64Url.encode(List<int>.generate(32, (i) => (i * 7 + 3) % 256));

    test('1. Unpaired write rejected with "This device isn\'t paired."', () {
      BleSecurityGuard.instance.openPairingWindow();

      final fakeUnpairedKey = base64Url.encode(List<int>.generate(32, (i) => (i + 1) % 256));
      final testPayload = Uint8List.fromList(utf8.encode('Sensitive thoughts payload'));

      // Packet constructed by an unpaired device
      final packet = BleSecurityGuard.packAuthenticatedMessage(
        senderId: unpairedDeviceId,
        counter: 1,
        payload: testPayload,
        sharedKey: fakeUnpairedKey,
      );

      // Key lookup returns null for unpaired device
      final result = BleSecurityGuard.instance.validateIncomingWrite(
        packetBytes: packet,
        keyLookup: (id) => id == peerDeviceId ? sharedKey : null,
      );

      expect(result.allowed, isFalse);
      expect(result.rejectionReason, equals("This device isn't paired."));
      expect(result.payload, isNull);
    });

    test('2. Replayed message rejected: counter <= lastSeenCounter', () {
      BleSecurityGuard.instance.openPairingWindow();
      final testPayload = Uint8List.fromList(utf8.encode('Original message'));

      // First packet with counter = 100
      final packet1 = BleSecurityGuard.packAuthenticatedMessage(
        senderId: peerDeviceId,
        counter: 100,
        payload: testPayload,
        sharedKey: sharedKey,
      );

      final result1 = BleSecurityGuard.instance.validateIncomingWrite(
        packetBytes: packet1,
        keyLookup: (id) => id == peerDeviceId ? sharedKey : null,
      );

      expect(result1.allowed, isTrue);
      expect(result1.counter, equals(100));
      expect(BleSecurityGuard.instance.getLastSeenCounter(peerDeviceId), equals(100));

      // Replayed packet with counter = 100
      final result2 = BleSecurityGuard.instance.validateIncomingWrite(
        packetBytes: packet1,
        keyLookup: (id) => id == peerDeviceId ? sharedKey : null,
      );

      expect(result2.allowed, isFalse);
      expect(result2.rejectionReason, contains('Replay attack detected: counter 100 <= 100'));

      // Older packet with counter = 99
      final packetOlder = BleSecurityGuard.packAuthenticatedMessage(
        senderId: peerDeviceId,
        counter: 99,
        payload: testPayload,
        sharedKey: sharedKey,
      );

      final result3 = BleSecurityGuard.instance.validateIncomingWrite(
        packetBytes: packetOlder,
        keyLookup: (id) => id == peerDeviceId ? sharedKey : null,
      );

      expect(result3.allowed, isFalse);
      expect(result3.rejectionReason, contains('Replay attack detected: counter 99 <= 100'));
    });

    test('3. Oversized message rejected before allocating memory', () {
      BleSecurityGuard.instance.openPairingWindow();

      // Case A: Chunk size exceeds maxChunkSize (64 KB)
      final oversizedChunk = Uint8List(BleSecurityGuard.maxChunkSize + 10);
      final chunkResult = BleSecurityGuard.instance.validateIncomingWrite(
        packetBytes: oversizedChunk,
        keyLookup: (id) => sharedKey,
      );
      expect(chunkResult.allowed, isFalse);
      expect(chunkResult.rejectionReason, equals('Oversized chunk rejected.'));

      // Case B: Header advertises payloadLen exceeding maxTotalPayloadSize (5 MB)
      final senderBytes = utf8.encode(peerDeviceId);
      final fakePacket = Uint8List(1 + 1 + senderBytes.length + 8 + 4 + 32 + 10);
      final bd = ByteData.sublistView(fakePacket);
      bd.setUint8(0, 0x01); // Version
      bd.setUint8(1, senderBytes.length);
      fakePacket.setRange(2, 2 + senderBytes.length, senderBytes);
      bd.setUint64(2 + senderBytes.length, 1, Endian.big); // Counter
      bd.setUint32(2 + senderBytes.length + 8, 10 * 1024 * 1024, Endian.big); // 10 MB payload claimed

      final payloadCapResult = BleSecurityGuard.instance.validateIncomingWrite(
        packetBytes: fakePacket,
        keyLookup: (id) => sharedKey,
      );
      expect(payloadCapResult.allowed, isFalse);
      expect(payloadCapResult.rejectionReason, contains('Oversized payload rejected'));
    });

    test('4. No pairing key throws DeviceNotPairedException and nothing is sent (000000 fallback removed)', () async {
      final mockSender = MockSenderService();
      final receiver = ReceiverService(SettingsService(), HistoryService());
      final bleSync = BleSyncService(
        sender: mockSender,
        receiver: receiver,
      );

      final unpairedDevice = BleDevice(
        deviceId: 'unpaired-device-8888',
        name: 'Attacker Phone',
      );

      bool exceptionCaught = false;
      try {
        await bleSync.syncTwoWay(unpairedDevice);
      } on DeviceNotPairedException catch (e) {
        exceptionCaught = true;
        expect(e.message, contains("This device isn't paired."));
      } catch (e) {
        fail('Expected DeviceNotPairedException but got $e');
      }

      // Assert that syncTwoWay aborted and sendBytes was NEVER called
      expect(exceptionCaught, isTrue);
      expect(mockSender.sendBytesCalls, equals(0));
      expect(mockSender.lastSentBytes, isNull);
    });

    test('7. lastSeenCounter persists to disk and updates ONLY after message authenticates', () {
      BleSecurityGuard.instance.openPairingWindow();

      final mockDiskStore = <String, int>{
        peerDeviceId: 50, // Pretend disk already stored counter 50 from previous session
      };

      BleSecurityGuard.instance.configurePersistence(
        counterLookup: (id) => mockDiskStore[id] ?? 0,
        persistCounter: (id, counter) async {
          mockDiskStore[id] = counter;
        },
      );

      // Startup check: last seen counter is read from disk
      expect(BleSecurityGuard.instance.getLastSeenCounter(peerDeviceId), equals(50));

      // Attempt 1: Replayed message (counter = 50) fails at replay gate
      final replayedPacket = BleSecurityGuard.packAuthenticatedMessage(
        senderId: peerDeviceId,
        counter: 50,
        payload: Uint8List.fromList(utf8.encode('Replayed')),
        sharedKey: sharedKey,
      );
      final res1 = BleSecurityGuard.instance.validateIncomingWrite(
        packetBytes: replayedPacket,
        keyLookup: (id) => sharedKey,
      );
      expect(res1.allowed, isFalse);
      expect(mockDiskStore[peerDeviceId], equals(50), reason: 'Disk counter must NOT change on rejected write');

      // Attempt 2: Tampered message (counter = 60, but wrong key/bad HMAC)
      final badHmacPacket = BleSecurityGuard.packAuthenticatedMessage(
        senderId: peerDeviceId,
        counter: 60,
        payload: Uint8List.fromList(utf8.encode('Bad HMAC')),
        sharedKey: base64Url.encode(List<int>.filled(32, 9)),
      );
      final res2 = BleSecurityGuard.instance.validateIncomingWrite(
        packetBytes: badHmacPacket,
        keyLookup: (id) => sharedKey,
      );
      expect(res2.allowed, isFalse);
      expect(mockDiskStore[peerDeviceId], equals(50), reason: 'Disk counter must NOT change on HMAC failure');

      // Attempt 3: Valid message (counter = 60) authenticates and decrypts
      final validPacket = BleSecurityGuard.packAuthenticatedMessage(
        senderId: peerDeviceId,
        counter: 60,
        payload: Uint8List.fromList(utf8.encode('Valid data')),
        sharedKey: sharedKey,
      );
      final res3 = BleSecurityGuard.instance.validateIncomingWrite(
        packetBytes: validPacket,
        keyLookup: (id) => sharedKey,
      );
      expect(res3.allowed, isTrue);
      // Confirmed: Disk counter is updated ONLY AFTER authentication and decryption succeed
      expect(mockDiskStore[peerDeviceId], equals(60));
    });

    test('5. Receiver rejects any write when pairing window is closed', () {
      expect(BleSecurityGuard.instance.isPairingWindowOpen, isFalse);

      final packet = BleSecurityGuard.packAuthenticatedMessage(
        senderId: peerDeviceId,
        counter: 1,
        payload: Uint8List.fromList([1, 2, 3]),
        sharedKey: sharedKey,
      );

      final result = BleSecurityGuard.instance.validateIncomingWrite(
        packetBytes: packet,
        keyLookup: (id) => sharedKey,
      );

      expect(result.allowed, isFalse);
      expect(result.rejectionReason, equals('Pairing window is closed.'));
    });

    test('6. Pairing window closes on cancel or success', () {
      BleSecurityGuard.instance.openPairingWindow();
      expect(BleSecurityGuard.instance.isPairingWindowOpen, isTrue);

      BleSecurityGuard.instance.closePairingWindow(reason: 'cancel');
      expect(BleSecurityGuard.instance.isPairingWindowOpen, isFalse);

      BleSecurityGuard.instance.openPairingWindow();
      expect(BleSecurityGuard.instance.isPairingWindowOpen, isTrue);

      BleSecurityGuard.instance.closePairingWindow(reason: 'success');
      expect(BleSecurityGuard.instance.isPairingWindowOpen, isFalse);
    });
  });
}
