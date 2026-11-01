import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'settings_service.dart';

/// RFC 4122 v4 UUID generator and Hybrid Logical Clock (HLC)
class SyncIdentity {
  static final Random _secureRandom = Random.secure();

  /// Generates a permanent unique ID (UUID v4)
  static String newUuid() {
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    // Set version to 4 (bits 12-15 of time_hi_and_version)
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Set variant to RFC 4122 (bits 6-7 of clock_seq_hi_and_reserved)
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int b) => b.toRadixString(16).padLeft(2, '0');

    return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}-'
        '${hex(bytes[4])}${hex(bytes[5])}-'
        '${hex(bytes[6])}${hex(bytes[7])}-'
        '${hex(bytes[8])}${hex(bytes[9])}-'
        '${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
  }

  /// Retrieves or initializes a permanent unique deviceId for this install
  static String getDeviceId(SettingsService settings) {
    var id = settings.deviceId;
    if (id.isEmpty) {
      id = newUuid();
      settings.setDeviceId(id);
    }
    return id;
  }

  /// Default friendly device name based on platform
  static String defaultDeviceName() {
    if (kIsWeb) return 'Web Browser';
    if (Platform.isAndroid) return 'Android Phone';
    if (Platform.isWindows) return 'Windows PC';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isLinux) return 'Linux Device';
    return 'ThoughtHolder Device';
  }
}

/// Hybrid Logical Clock (HLC) implementation ensuring monotonic causality
/// across devices regardless of clock skew or drift.
class Hlc implements Comparable<Hlc> {
  final int millis;
  final int counter;
  final String nodeId;
  String get deviceId => nodeId;

  const Hlc({
    required this.millis,
    required this.counter,
    String? nodeId,
    String? deviceId,
  }) : nodeId = nodeId ?? deviceId ?? '';

  Hlc update(Hlc remote) => Hlc.receive(remote, nodeId);

  static int _lastPhysicalMillis = 0;
  static int _lastCounter = 0;

  /// Creates a new HLC event on the local device
  static Hlc now(String nodeId) {
    final physical = DateTime.now().millisecondsSinceEpoch;
    if (physical > _lastPhysicalMillis) {
      _lastPhysicalMillis = physical;
      _lastCounter = 0;
    } else {
      _lastCounter++;
    }
    return Hlc(millis: _lastPhysicalMillis, counter: _lastCounter, nodeId: nodeId);
  }

  /// Updates the local HLC state upon receiving a remote HLC timestamp
  static Hlc receive(Hlc remote, String localNodeId) {
    final physical = DateTime.now().millisecondsSinceEpoch;
    final maxMillis = [physical, _lastPhysicalMillis, remote.millis].reduce(max);

    if (maxMillis == _lastPhysicalMillis && maxMillis == remote.millis) {
      _lastCounter = max(_lastCounter, remote.counter) + 1;
    } else if (maxMillis == _lastPhysicalMillis) {
      _lastCounter++;
    } else if (maxMillis == remote.millis) {
      _lastCounter = remote.counter + 1;
    } else {
      _lastCounter = 0;
    }
    _lastPhysicalMillis = maxMillis;
    return Hlc(millis: _lastPhysicalMillis, counter: _lastCounter, nodeId: localNodeId);
  }

  /// Formats HLC as a sortable string: millis:counter:nodeId
  @override
  String toString() => '$millis:$counter:$nodeId';

  /// Parses HLC from string
  static Hlc parse(String str) {
    final parts = str.split(':');
    if (parts.length >= 3) {
      final m = int.tryParse(parts[0]) ?? 0;
      final c = int.tryParse(parts[1]) ?? 0;
      final node = parts.sublist(2).join(':');
      return Hlc(millis: m, counter: c, nodeId: node);
    }
    final singleNum = int.tryParse(str) ?? 0;
    return Hlc(millis: singleNum, counter: 0, nodeId: '');
  }

  @override
  int compareTo(Hlc other) {
    if (millis != other.millis) {
      return millis.compareTo(other.millis);
    }
    if (counter != other.counter) {
      return counter.compareTo(other.counter);
    }
    return nodeId.compareTo(other.nodeId);
  }

  static int compare(String? aStr, String? bStr) {
    if (aStr == null || aStr.isEmpty) return (bStr == null || bStr.isEmpty) ? 0 : -1;
    if (bStr == null || bStr.isEmpty) return 1;
    final a = Hlc.parse(aStr);
    final b = Hlc.parse(bStr);
    return a.compareTo(b);
  }
}
