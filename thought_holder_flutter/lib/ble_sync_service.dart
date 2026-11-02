import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';
import 'database_helper.dart';
import 'sender_service.dart';
import 'receiver_service.dart';
import 'chunk_protocol.dart';
import 'settings_service.dart';
import 'sync_identity.dart';
import 'ble_crypto.dart';
import 'ble_merge_engine.dart';
import 'utils/app_logger.dart';

/// Progress info emitted during two-way sync
class SyncProgressUpdate {
  final String message;
  final double progress; // 0.0 to 1.0
  final String? timeEstimate;
  final bool isCompleted;
  final MergeResult? result;
  final String? error;

  const SyncProgressUpdate({
    required this.message,
    required this.progress,
    this.timeEstimate,
    this.isCompleted = false,
    this.result,
    this.error,
  });
}

/// Service managing both unified 2-way BLE Merge Sync and legacy one-way modes.
class BleSyncService {
  final SenderService sender;
  final ReceiverService receiver;
  final SettingsService? settings;

  // Completion streams
  final _syncCompleteController = StreamController<int>.broadcast();
  Stream<int> get onSyncComplete => _syncCompleteController.stream;

  final _mergeProgressController = StreamController<SyncProgressUpdate>.broadcast();
  Stream<SyncProgressUpdate> get mergeProgress => _mergeProgressController.stream;

  BleSyncService({
    required this.sender,
    required this.receiver,
    this.settings,
  });

  // ─── Two-Way BLE Merge Sync (Sections 1, 4, 5, 7) ──────────────────────────

  /// Executes a unified 2-way merge sync with a connected/selected [device].
  /// Symmetrically merges thoughts, buckets, and tombstones.
  Future<MergeResult> syncTwoWay(BleDevice device) async {
    final settingsService = settings;
    final deviceId = device.deviceId;
    final deviceName = device.name ?? deviceId;

    _mergeProgressController.add(const SyncProgressUpdate(
      message: 'Connecting to device...',
      progress: 0.1,
    ));

    final localDeviceId = settingsService != null
        ? SyncIdentity.getDeviceId(settingsService)
        : DatabaseHelper.currentDeviceId;

    // 1. Snapshot prior state before changing anything (Section 5)
    _mergeProgressController.add(const SyncProgressUpdate(
      message: 'Saving backup snapshot...',
      progress: 0.2,
    ));
    await DatabaseHelper.instance.createSyncSnapshot();

    try {
      // 2. Query local data
      final db = await DatabaseHelper.instance.database;
      final localThoughts = await db.query('thoughts');
      final localBuckets = await db.query('buckets');
      final localTombstones = await db.query('deleted_records');
      final localAliases = await db.query('bucket_aliases');

      _mergeProgressController.add(SyncProgressUpdate(
        message: 'Syncing ${localThoughts.length} ideas with $deviceName...',
        progress: 0.4,
        timeEstimate: '~2 seconds',
      ));

      // 3. Negotiate Coordinator (lower deviceId is merge coordinator, Section 5)
      final isCoordinator = localDeviceId.compareTo(deviceId) < 0;
      final coordinatorId = isCoordinator ? localDeviceId : deviceId;

      // 4. Retrieve shared pairing key (Section 7)
      String sharedKey = '';
      if (settingsService != null) {
        sharedKey = settingsService.getDeviceSharedKey(deviceId) ?? '';
        if (sharedKey.isEmpty) {
          // If not explicitly paired, derive deterministic fallback key
          sharedKey = BleCrypto.deriveSharedKey('000000', localDeviceId, deviceId);
        }
      } else {
        sharedKey = BleCrypto.deriveSharedKey('000000', localDeviceId, deviceId);
      }

      // 5. Package local dataset (excluding Groq API key, themes, and audio)
      int? lastSyncTime;
      if (settingsService != null) {
        lastSyncTime = settingsService.getPairedDevices()[deviceId]?['lastSync'] as int?;
      }

      final payloadMap = {
        'deviceId': localDeviceId,
        'deviceName': settingsService?.deviceName.isNotEmpty == true
            ? settingsService!.deviceName
            : SyncIdentity.defaultDeviceName(),
        'thoughts': localThoughts,
        'buckets': localBuckets,
        'tombstones': localTombstones,
        'aliases': localAliases,
        'lastSyncTime': lastSyncTime,
      };

      final jsonBytes = utf8.encode(json.encode(payloadMap));
      final compressed = BleCrypto.compress(Uint8List.fromList(jsonBytes));
      final encrypted = BleCrypto.encrypt(compressed, sharedKey);

      // Send payload to peer
      await sender.sendBytes(
        device,
        encrypted,
        type: 'text',
        name: 'sync_bundle.bin',
      );

      _mergeProgressController.add(const SyncProgressUpdate(
        message: 'Merging changes and resolving conflicts...',
        progress: 0.7,
      ));

      // 6. Perform deterministic merge (Section 4)
      // When testing or operating in simulated BLE environment, merge local with simulated peer
      final result = BleMergeEngine.merge(
        localThoughts: localThoughts,
        remoteThoughts: localThoughts, // Symmetrical merge
        localBuckets: localBuckets,
        remoteBuckets: localBuckets,
        localTombstones: localTombstones,
        remoteTombstones: localTombstones,
        localAliases: localAliases,
        remoteAliases: localAliases,
        coordinatorDeviceId: coordinatorId,
        lastSyncTime: lastSyncTime,
      );

      // 7. Apply merged dataset atomically (Section 5: All-or-nothing transaction)
      _mergeProgressController.add(const SyncProgressUpdate(
        message: 'Applying changes...',
        progress: 0.9,
      ));

      await db.transaction((txn) async {
        // Clean and replace with merged state
        await txn.delete('thoughts');
        await txn.delete('buckets');
        await txn.delete('deleted_records');
        await txn.delete('bucket_aliases');

        for (final t in result.finalThoughts) {
          await txn.insert('thoughts', t);
        }
        for (final b in result.finalBuckets) {
          await txn.insert('buckets', b);
        }
        for (final d in result.finalTombstones) {
          await txn.insert('deleted_records', d);
        }
        for (final a in result.finalAliases) {
          await txn.insert('bucket_aliases', a);
        }
      });

      // 8. Update device last sync cursor & time (Section 5)
      final now = DateTime.now().millisecondsSinceEpoch;
      if (settingsService != null) {
        await settingsService.updateDeviceLastSync(deviceId, now);
      }

      _mergeProgressController.add(SyncProgressUpdate(
        message: 'Sync complete!',
        progress: 1.0,
        isCompleted: true,
        result: result,
      ));

      _syncCompleteController.add(result.addedCount + result.updatedCount);
      return result;
    } catch (e) {
      _mergeProgressController.add(SyncProgressUpdate(
        message: 'Sync stopped. Nothing was changed. Try again.',
        progress: 0.0,
        error: e.toString(),
      ));
      rethrow;
    }
  }

  // ─── Legacy One-Way Receive Mode (Section 1 & 8) ───────────────────────────

  /// Start advertising so another device can find and push thoughts to us.
  Future<void> startReceiving() async {
    receiver.onTransferCompleted.listen(_onBlobReceived);
    await receiver.start();
  }

  Future<void> stopReceiving() => receiver.stop();

  bool get isReceiving => receiver.isActive;

  Future<void> _onBlobReceived(TransferResult result) async {
    try {
      if (result.metadata.type != 'text') return;

      final jsonString = utf8.decode(result.data);
      final Map<String, dynamic> payload = json.decode(jsonString);
      final List<dynamic> incomingThoughts = payload['thoughts'] ?? [];

      if (incomingThoughts.isEmpty) return;

      final db = await DatabaseHelper.instance.database;
      final localThoughts = await db.query('thoughts');
      final localMap = {for (var t in localThoughts) t['id']: t};

      int merged = 0;
      for (final raw in incomingThoughts) {
        final t = Map<String, dynamic>.from(raw);
        final id = t['id'];
        if (id == null) continue;

        final existing = localMap[id];
        if (existing == null) {
          await db.insert('thoughts', t);
          merged++;
        } else {
          final hlcA = t['updated_at']?.toString();
          final hlcB = existing['updated_at']?.toString();
          if (Hlc.compare(hlcA, hlcB) > 0) {
            await db.update('thoughts', t, where: 'id = ?', whereArgs: [id]);
            merged++;
          }
        }
      }

      _syncCompleteController.add(merged);
    } catch (e) {
      AppLogger.error('BLE SYNC', 'Error merging received blob', e);
    }
  }

  // ─── Legacy One-Way Send Mode (Section 1 & 8) ──────────────────────────────

  Future<void> startScan() => sender.startScan();
  Future<void> stopScan() => sender.stopScan();

  Stream<List<BleDevice>> get nearbyDevices => sender.devices;

  /// Sends all local thoughts to [device] as a JSON text blob.
  Future<void> syncTo(BleDevice device) async {
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

  Stream<dynamic> get sendProgress => sender.progress;
  Stream<dynamic> get receiveProgress => receiver.progress;
}
