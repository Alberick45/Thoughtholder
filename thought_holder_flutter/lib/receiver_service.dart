import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble_ids.dart';
import 'chunk_protocol.dart';
import 'transfer_progress.dart';
import 'history_model.dart';
import 'history_service.dart';
import 'settings_service.dart';

/// Puts this device into "Receive" mode: advertises the PK Share GATT
/// service and reassembles whatever text or files the sender writes to it.
class ReceiverService {
  final _reassembler = ChunkReceiver();
  final _completedController = StreamController<TransferResult>.broadcast();
  final _progressController = StreamController<TransferProgress>.broadcast();

  final SettingsService _settings;
  final HistoryService _history;

  ReceiverService(this._settings, this._history);

  Stream<TransferResult> get onTransferCompleted => _completedController.stream;
  Stream<TransferProgress> get progress => _progressController.stream;

  bool _started = false;
  bool get isActive => _started;

  DateTime? _startTime;
  int _bytesReceived = 0;
  String? _activeSender;

  Future<void> start() async {
    if (_started) return;

    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
      ].request();

      final connect = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
      final advertise = statuses[Permission.bluetoothAdvertise]?.isGranted ?? false;
      if (!connect || !advertise) {
        throw 'Bluetooth Connect and Advertise permissions are required to receive files on Android 12+';
      }
    }

    _started = true;

    _reassembler.reset();
    _reassembler.onProgress = _handleProgress;

    await UniversalBlePeripheral.addService(
      BlePeripheralService(
        uuid: BleIds.serviceUuid,
        primary: true,
        characteristics: [
          BlePeripheralCharacteristic(
            uuid: BleIds.txCharUuid,
            properties: [
              CharacteristicProperty.write,
              CharacteristicProperty.writeWithoutResponse,
            ],
            permissions: [PeripheralAttributePermission.writeable],
          ),
          BlePeripheralCharacteristic(
            uuid: BleIds.statusCharUuid,
            properties: [CharacteristicProperty.notify],
            permissions: [PeripheralAttributePermission.readable],
          ),
        ],
      ),
    );

    UniversalBlePeripheral.setWriteRequestHandlers((
      String deviceId,
      String characteristicId,
      int offset,
      Uint8List? value,
    ) {
      if (characteristicId.toLowerCase() != BleIds.txCharUuid.toLowerCase() || value == null) {
        return PeripheralWriteRequestResult(status: 0);
      }

      _activeSender = deviceId;
      if (_startTime == null) {
        _startTime = DateTime.now();
        _bytesReceived = 0;
      }

      final complete = _reassembler.add(value);
      if (complete != null) {
        _handleCompletedTransfer(complete);
      }
      return PeripheralWriteRequestResult(status: 0);
    });

    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final name = _settings.deviceName;

    await UniversalBlePeripheral.startAdvertising(
      services: [BleIds.serviceUuid],
      localName: isWindows ? null : name,
      platformConfig: PeripheralPlatformConfig(
        android: PeripheralAndroidOptions(
          addServicesInScanResponse: true,
        ),
      ),
    );
  }

  void _handleProgress(int bytesReceived, int totalBytes) {
    _bytesReceived = bytesReceived;
    final now = DateTime.now();
    final elapsedMs = _startTime != null ? now.difference(_startTime!).inMilliseconds : 0;
    final speed = elapsedMs > 0 ? (_bytesReceived / (elapsedMs / 1000.0)) : 0.0;
    final percent = totalBytes > 0 ? (bytesReceived / totalBytes).clamp(0.0, 1.0) : 0.0;

    _progressController.add(TransferProgress(
      status: TransferStatus.receiving,
      progress: percent,
      bytesTransferred: bytesReceived,
      totalBytes: totalBytes,
      speedBytesPerSec: speed,
      deviceName: _activeSender,
    ));
  }

  Future<void> _handleCompletedTransfer(TransferResult result) async {
    final meta = result.metadata;
    final data = result.data;

    String payload = '';

    if (meta.type == 'text') {
      payload = utf8.decode(data);
    } else {
      final downloadDir = await _settings.downloadPath;
      final uniquePath = _resolveUniqueFilePath(downloadDir, meta.name ?? 'download');

      // Create download folder if it doesn't exist
      final directory = Directory(downloadDir);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final file = File(uniquePath);
      await file.writeAsBytes(data);
      payload = uniquePath;
    }

    // Save to database history
    final historyItem = TransferHistoryItem(
      id: meta.id,
      type: meta.type,
      name: meta.name,
      payload: payload,
      size: meta.size,
      timestamp: DateTime.now(),
      isSent: false,
      deviceName: _activeSender ?? 'Sender Device',
    );
    await _history.add(historyItem);

    // Notify UI of completion
    _progressController.add(TransferProgress(
      status: TransferStatus.completed,
      progress: 1.0,
      bytesTransferred: meta.size,
      totalBytes: meta.size,
      speedBytesPerSec: 0.0,
      deviceName: _activeSender,
    ));

    _completedController.add(result);

    // Reset tracking state
    _startTime = null;
    _bytesReceived = 0;
    _activeSender = null;
  }

  String _resolveUniqueFilePath(String dir, String name) {
    int dotIndex = name.lastIndexOf('.');
    String base = dotIndex != -1 ? name.substring(0, dotIndex) : name;
    String ext = dotIndex != -1 ? name.substring(dotIndex) : '';
    int counter = 0;
    String fullPath = '$dir/$name';
    while (File(fullPath).existsSync()) {
      counter++;
      fullPath = '$dir/${base}_$counter$ext';
    }
    return fullPath;
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _startTime = null;
    _bytesReceived = 0;
    _activeSender = null;
    await UniversalBlePeripheral.stopAdvertising();
    await UniversalBlePeripheral.clearServices();
  }

  void dispose() {
    _completedController.close();
    _progressController.close();
  }
}
