import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:universal_ble/universal_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble_ids.dart';
import 'chunk_protocol.dart';
import 'transfer_progress.dart';

/// Puts this device into "Send" mode: scans for nearby devices advertising
/// the PK Share service, then streams the data (text or files) over as chunked
/// BLE writes.
class SenderService {
  final List<BleDevice> _found = [];
  final _foundController = StreamController<List<BleDevice>>.broadcast();
  final _progressController = StreamController<TransferProgress>.broadcast();

  Stream<List<BleDevice>> get devices => _foundController.stream;
  Stream<TransferProgress> get progress => _progressController.stream;

  Future<void> startScan() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      final scan = statuses[Permission.bluetoothScan]?.isGranted ?? false;
      final connect = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
      if (!scan || !connect) {
        throw 'Bluetooth Scan and Connect permissions are required to scan for receivers on Android 12+';
      }
    }

    _found.clear();
    _foundController.add(List.of(_found));

    UniversalBle.onScanResult = (BleDevice result) {
      final index = _found.indexWhere((d) => d.deviceId == result.deviceId);
      if (index != -1) {
        bool updated = false;
        final existing = _found[index];
        if (result.name != null && result.name!.isNotEmpty && existing.name != result.name) {
          existing.name = result.name;
          updated = true;
        }
        if (result.rssi != null && existing.rssi != result.rssi) {
          existing.rssi = result.rssi;
          updated = true;
        }
        if (updated) {
          _foundController.add(List.of(_found));
        }
      } else {
        _found.add(result);
        _foundController.add(List.of(_found));
      }
    };

    // Filter by our service UUID so only ThoughtHolder devices appear.
    // This is critical on Windows where d.services is not populated in scan results —
    // the BLE stack does the filtering at hardware level instead.
    await UniversalBle.startScan(
      scanFilter: ScanFilter(
        withServices: [BleIds.serviceUuid],
      ),
    );
  }

  Future<void> stopScan() => UniversalBle.stopScan();

  /// Connects to [device], negotiates MTU, chunks the payload, and sends it.
  Future<void> sendBytes(
    BleDevice device,
    Uint8List dataBytes, {
    required String type,
    String? name,
  }) async {
    final deviceId = device.deviceId;
    final deviceName = device.name ?? deviceId;

    _emitProgress(TransferProgress(
      status: TransferStatus.connecting,
      progress: 0.0,
      bytesTransferred: 0,
      totalBytes: dataBytes.length,
      speedBytesPerSec: 0.0,
      deviceName: deviceName,
    ));

    try {
      await UniversalBle.connect(deviceId);
      await UniversalBle.discoverServices(deviceId);

      _emitProgress(TransferProgress(
        status: TransferStatus.negotiatingMtu,
        progress: 0.0,
        bytesTransferred: 0,
        totalBytes: dataBytes.length,
        speedBytesPerSec: 0.0,
        deviceName: deviceName,
      ));

      // Request larger MTU
      var mtu = 23;
      try {
        mtu = await UniversalBle.requestMtu(deviceId, 247);
      } catch (_) {
        // Fallback to default MTU if negotiation fails or is unsupported
      }

      final chunkPayloadSize = (mtu - 3 - ChunkProtocol.headerBytes).clamp(16, 500);

      // Encode payload to chunks (including metadata chunk at index 0)
      final chunks = ChunkProtocol.encode(
        payloadBytes: dataBytes,
        type: type,
        name: name,
        chunkPayloadSize: chunkPayloadSize,
      );

      _emitProgress(TransferProgress(
        status: TransferStatus.sending,
        progress: 0.0,
        bytesTransferred: 0,
        totalBytes: dataBytes.length,
        speedBytesPerSec: 0.0,
        deviceName: deviceName,
      ));

      final startTime = DateTime.now();
      int bytesSent = 0;

      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        await UniversalBle.write(
          deviceId,
          BleIds.serviceUuid,
          BleIds.txCharUuid,
          chunk,
        );

        // Update progress (skip metadata chunk size for actual data progress)
        if (i > 0) {
          final payloadLength = chunk.length - ChunkProtocol.headerBytes;
          bytesSent += payloadLength;
        }

        final now = DateTime.now();
        final elapsedMs = now.difference(startTime).inMilliseconds;
        final speed = elapsedMs > 0 ? (bytesSent / (elapsedMs / 1000.0)) : 0.0;
        final percent = dataBytes.isEmpty ? 1.0 : (bytesSent / dataBytes.length).clamp(0.0, 1.0);

        _emitProgress(TransferProgress(
          status: TransferStatus.sending,
          progress: percent,
          bytesTransferred: bytesSent.clamp(0, dataBytes.length),
          totalBytes: dataBytes.length,
          speedBytesPerSec: speed,
          deviceName: deviceName,
        ));

        // Pacing delay to avoid buffer overflow on slower BLE adapters
        await Future.delayed(const Duration(milliseconds: 15));
      }

      _emitProgress(TransferProgress(
        status: TransferStatus.completed,
        progress: 1.0,
        bytesTransferred: dataBytes.length,
        totalBytes: dataBytes.length,
        speedBytesPerSec: 0.0,
        deviceName: deviceName,
      ));

      // Small delay to ensure GATT operations complete before disconnect
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      _emitProgress(TransferProgress(
        status: TransferStatus.failed,
        progress: 0.0,
        bytesTransferred: 0,
        totalBytes: dataBytes.length,
        speedBytesPerSec: 0.0,
        error: e.toString(),
        deviceName: deviceName,
      ));
      rethrow;
    } finally {
      try {
        await UniversalBle.disconnect(deviceId);
      } catch (_) {}
    }
  }

  void _emitProgress(TransferProgress p) {
    _progressController.add(p);
  }

  void dispose() {
    _foundController.close();
    _progressController.close();
  }
}
