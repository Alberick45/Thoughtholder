import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';
import 'database_helper.dart';
import 'sender_service.dart';
import 'receiver_service.dart';
import 'chunk_protocol.dart';

/// Wraps [SenderService] and [ReceiverService] to provide a ThoughtHolder-
/// specific BLE sync experience.
///
/// Instead of sending arbitrary files, it serializes all local SQLite thoughts
/// to a JSON blob and transmits them. The receiver deserializes and merges
/// them using the same timestamp-based intelligent-merge logic used by
/// Google Drive sync.
class BleSyncService {
  final SenderService sender;
  final ReceiverService receiver;

  // Fires with the count of merged thoughts after a successful BLE receive.
  // Screens should listen to this and call ThoughtProvider.loadThoughts().
  final _syncCompleteController = StreamController<int>.broadcast();
  Stream<int> get onSyncComplete => _syncCompleteController.stream;

  BleSyncService({required this.sender, required this.receiver});

  // ─── Receive Side ────────────────────────────────────────────────────────

  /// Start advertising so another device can find and push thoughts to us.
  /// When a full blob arrives, it is immediately merged into SQLite.
  Future<void> startReceiving() async {
    // Hook into the receiver's completion stream BEFORE starting advertising
    receiver.onTransferCompleted.listen(_onBlobReceived);
    await receiver.start();
  }

  Future<void> stopReceiving() => receiver.stop();

  bool get isReceiving => receiver.isActive;

  Future<void> _onBlobReceived(TransferResult result) async {
    try {
      if (result.metadata.type != 'text') return; // We only send text blobs

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
          // New thought — insert it
          await db.insert('thoughts', _sanitize(t));
          merged++;
        } else {
          // Existing thought — keep whichever has the latest timestamp
          if (_latestTimestamp(t) > _latestTimestamp(existing)) {
            await db.update('thoughts', _sanitize(t), where: 'id = ?', whereArgs: [id]);
            merged++;
          }
        }
      }

      print('[BLE SYNC] Merged $merged thoughts from remote device.');
      // Notify listeners (e.g. BleSyncScreen) so they can reload ThoughtProvider
      _syncCompleteController.add(merged);
    } catch (e) {
      print('[BLE SYNC] Error merging received blob: $e');
    }
  }

  // ─── Send Side ───────────────────────────────────────────────────────────

  /// Scans for nearby devices advertising the QuickLink service UUID.
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

  // ─── Helpers ─────────────────────────────────────────────────────────────

  int _latestTimestamp(Map<String, dynamic>? t) {
    if (t == null) return 0;
    int parse(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }
    final updated = parse(t['updated_at']);
    final viewed = parse(t['last_viewed_at']);
    final created = parse(t['created_at']);
    return [updated, viewed, created].reduce((a, b) => a > b ? a : b);
  }

  /// Ensures all required columns have non-null defaults before DB insertion.
  /// Only includes columns that exist in the DB schema defined in database_helper.dart.
  Map<String, dynamic> _sanitize(Map<String, dynamic> t) {
    return {
      'id': t['id'] ?? '',
      'thought_id': t['thought_id'] ?? 'LOG-0000',
      'content': t['content'] ?? '',
      'type': t['type'] ?? 'thought',
      'status': t['status'] ?? 'active',
      'tags': t['tags'] ?? '',
      'summary': t['summary'] ?? '',
      'created_at': t['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
      'last_viewed_at': t['last_viewed_at'] ?? DateTime.now().millisecondsSinceEpoch,
      'stale_score': t['stale_score'] ?? 0,
      'linked_thoughts': t['linked_thoughts'] ?? '[]',
    };
  }
}
