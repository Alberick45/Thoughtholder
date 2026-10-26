class TransferHistoryItem {
  final String id;
  final String type; // 'text' | 'file'
  final String? name; // File name (null if text)
  final String payload; // The text content or the local file path
  final int size; // Size in bytes
  final DateTime timestamp;
  final bool isSent; // true if sent, false if received
  final String deviceName; // The device we shared with / received from

  TransferHistoryItem({
    required this.id,
    required this.type,
    this.name,
    required this.payload,
    required this.size,
    required this.timestamp,
    required this.isSent,
    required this.deviceName,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'name': name,
        'payload': payload,
        'size': size,
        'timestamp': timestamp.toIso8601String(),
        'isSent': isSent,
        'deviceName': deviceName,
      };

  factory TransferHistoryItem.fromMap(Map<dynamic, dynamic> map) =>
      TransferHistoryItem(
        id: map['id'] as String,
        type: map['type'] as String,
        name: map['name'] as String?,
        payload: map['payload'] as String,
        size: map['size'] as int,
        timestamp: DateTime.parse(map['timestamp'] as String),
        isSent: map['isSent'] as bool,
        deviceName: map['deviceName'] as String,
      );
}
