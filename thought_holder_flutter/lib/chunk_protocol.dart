import 'dart:convert';
import 'dart:typed_data';

/// Represents metadata about the text or file transfer.
class TransferMetadata {
  final String id;
  final String type; // 'text' | 'file'
  final String? name; // filename for files, null for text
  final int size; // total size of the actual data in bytes

  TransferMetadata({
    required this.id,
    required this.type,
    this.name,
    required this.size,
  });

  /// Encodes metadata into a compact binary representation:
  /// [type (1 byte)][size (4 bytes LE)][name length (1 byte)][name bytes (variable)]
  Uint8List toBytes() {
    final nameBytes = name != null ? utf8.encode(name!) : Uint8List(0);
    final bytes = Uint8List(1 + 4 + 1 + nameBytes.length);
    final bd = ByteData.view(bytes.buffer);
    bd.setUint8(0, type == 'file' ? 2 : 1);
    bd.setUint32(1, size, Endian.little);
    bd.setUint8(5, nameBytes.length);
    bytes.setRange(6, bytes.length, nameBytes);
    return bytes;
  }

  /// Decodes metadata from binary.
  factory TransferMetadata.fromBytes(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final typeVal = bd.getUint8(0);
    final type = typeVal == 2 ? 'file' : 'text';
    final size = bd.getUint32(1, Endian.little);
    final nameLen = bd.getUint8(5);
    String? name;
    if (nameLen > 0 && bytes.length >= 6 + nameLen) {
      name = utf8.decode(bytes.sublist(6, 6 + nameLen));
    }
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    return TransferMetadata(id: id, type: type, name: name, size: size);
  }
}

/// Represents the completed result of a transfer.
class TransferResult {
  final TransferMetadata metadata;
  final Uint8List data;

  TransferResult(this.metadata, this.data);
}

/// A wire format for sending text and files over BLE.
///
/// Chunk 0 is ALWAYS the compact binary representation of [TransferMetadata].
/// Chunk 1..N are raw data bytes.
///
/// Header is: [uint16 index LE][uint16 totalChunks LE]
class ChunkProtocol {
  static const headerBytes = 4;

  static List<Uint8List> encode({
    required Uint8List payloadBytes,
    required String type,
    String? name,
    int chunkPayloadSize = 200,
  }) {
    // 1. Create metadata
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final metadata = TransferMetadata(
      id: id,
      type: type,
      name: name,
      size: payloadBytes.length,
    );
    final metadataBytes = metadata.toBytes();

    // 2. Calculate data chunks
    final dataChunksCount = payloadBytes.isEmpty
        ? 1
        : (payloadBytes.length / chunkPayloadSize).ceil().clamp(1, 65535);

    // Total chunks = 1 (for metadata) + dataChunksCount
    final totalChunks = dataChunksCount + 1;

    final chunks = <Uint8List>[];

    // Chunk 0: Metadata
    {
      final chunk = Uint8List(headerBytes + metadataBytes.length);
      final header = ByteData.view(chunk.buffer, 0, headerBytes);
      header.setUint16(0, 0, Endian.little); // index = 0
      header.setUint16(2, totalChunks, Endian.little);
      chunk.setRange(headerBytes, chunk.length, metadataBytes);
      chunks.add(chunk);
    }

    // Chunk 1..N: Data
    for (var i = 0; i < dataChunksCount; i++) {
      final start = i * chunkPayloadSize;
      final end = (start + chunkPayloadSize > payloadBytes.length)
          ? payloadBytes.length
          : start + chunkPayloadSize;
      final payload = payloadBytes.sublist(start, end);

      final chunk = Uint8List(headerBytes + payload.length);
      final header = ByteData.view(chunk.buffer, 0, headerBytes);
      header.setUint16(0, i + 1, Endian.little); // index = i + 1
      header.setUint16(2, totalChunks, Endian.little);
      chunk.setRange(headerBytes, chunk.length, payload);
      chunks.add(chunk);
    }

    return chunks;
  }
}

/// Buffers incoming chunks and returns a [TransferResult] once the full set has arrived.
class ChunkReceiver {
  TransferMetadata? _metadata;
  final Map<int, Uint8List> _parts = {};
  int? _total;

  /// Callback to notify progress: (bytesReceived, totalBytes)
  void Function(int bytesReceived, int totalBytes)? onProgress;

  /// Resets the receiver state for a new transfer.
  void reset() {
    _metadata = null;
    _parts.clear();
    _total = null;
  }

  /// Returns the completed transfer result once all chunks are in, otherwise null.
  TransferResult? add(Uint8List data) {
    if (data.length < ChunkProtocol.headerBytes) return null;

    final header = ByteData.sublistView(data, 0, ChunkProtocol.headerBytes);
    final index = header.getUint16(0, Endian.little);
    final total = header.getUint16(2, Endian.little);
    final payload = data.sublist(ChunkProtocol.headerBytes);

    _total = total;

    if (index == 0) {
      // Metadata chunk
      try {
        _metadata = TransferMetadata.fromBytes(payload);
      } catch (e) {
        reset();
        return null;
      }
    } else {
      // Data chunk
      _parts[index] = payload;
    }

    // Calculate bytes received so far
    int bytesReceived = 0;
    _parts.forEach((_, p) => bytesReceived += p.length);

    if (_metadata != null && onProgress != null) {
      onProgress!(bytesReceived, _metadata!.size);
    }

    // Since chunk 0 is metadata, we expect parts to have indices 1..total-1.
    // Total parts count should be total - 1.
    if (_metadata != null && _parts.length == _total! - 1) {
      final ordered = List.generate(_total! - 1, (i) => _parts[i + 1]!);
      final allBytes = Uint8List.fromList(ordered.expand((e) => e).toList());
      final result = TransferResult(_metadata!, allBytes);
      reset();
      return result;
    }

    return null;
  }
}
