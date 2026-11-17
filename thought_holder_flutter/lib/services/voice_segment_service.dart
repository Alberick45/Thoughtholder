import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';

class AudioSegment {
  final int index;
  final String filePath;
  final int startMs;
  final int endMs;

  const AudioSegment({
    required this.index,
    required this.filePath,
    required this.startMs,
    required this.endMs,
  });
}

class VoiceSegmentService {
  static final VoiceSegmentService instance = VoiceSegmentService._();
  VoiceSegmentService._();

  static const int sampleRate = 16000;
  static const int numChannels = 1;
  static const int bitsPerSample = 16;
  static const int bytesPerSample = (bitsPerSample ~/ 8) * numChannels; // 2 bytes
  static const int bytesPerSecond = sampleRate * bytesPerSample; // 32,000 bytes/sec

  /// Generates a standard 44-byte RIFF PCM header
  static Uint8List buildWavHeader(int pcmByteLength) {
    final header = Uint8List(44);
    final byteData = ByteData.sublistView(header);

    // RIFF chunk descriptor
    header.setRange(0, 4, 'RIFF'.codeUnits);
    byteData.setUint32(4, 36 + pcmByteLength, Endian.little); // ChunkSize
    header.setRange(8, 12, 'WAVE'.codeUnits);

    // fmt sub-chunk
    header.setRange(12, 16, 'fmt '.codeUnits);
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    byteData.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
    byteData.setUint16(22, numChannels, Endian.little); // NumChannels
    byteData.setUint32(24, sampleRate, Endian.little); // SampleRate
    byteData.setUint32(28, bytesPerSecond, Endian.little); // ByteRate
    byteData.setUint16(32, bytesPerSample, Endian.little); // BlockAlign
    byteData.setUint16(34, bitsPerSample, Endian.little); // BitsPerSample

    // data sub-chunk
    header.setRange(36, 40, 'data'.codeUnits);
    byteData.setUint32(40, pcmByteLength, Endian.little); // Subchunk2Size

    return header;
  }

  /// Validates and fixes the 44-byte RIFF header of an unfinished or crashed recording
  Future<bool> repairWavHeader(File wavFile) async {
    if (!await wavFile.exists()) return false;
    final totalBytes = await wavFile.length();
    if (totalBytes < 44) return false;

    try {
      final pcmLength = totalBytes - 44;
      final header = buildWavHeader(pcmLength);

      final raf = await wavFile.open(mode: FileMode.writeOnlyAppend);
      await raf.setPosition(0);
      await raf.writeFrom(header);
      await raf.close();
      return true;
    } catch (e) {
      AppLogger.error('VoiceSegmentService', 'Failed to repair WAV header: $e');
      return false;
    }
  }

  /// Splits an uncompressed 16kHz mono WAV file into segments with overlap
  /// Default: 90 seconds per segment (~2.88 MB) with 2 seconds overlap.
  Future<List<AudioSegment>> splitWavFile({
    required File wavFile,
    required Directory outputDir,
    int segmentDurationSec = 90,
    int overlapSec = 2,
  }) async {
    if (!await wavFile.exists()) return [];
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    // Ensure header length fields match actual file size
    await repairWavHeader(wavFile);

    final fileSize = await wavFile.length();
    if (fileSize <= 44) return [];

    final pcmLength = fileSize - 44;
    final totalSec = pcmLength / bytesPerSecond;

    // If audio is under 90 seconds, use single segment directly
    if (totalSec <= segmentDurationSec) {
      final singleDest = File('${outputDir.path}/seg_0.wav');
      await wavFile.copy(singleDest.path);
      return [
        AudioSegment(
          index: 0,
          filePath: singleDest.path,
          startMs: 0,
          endMs: (totalSec * 1000).round(),
        ),
      ];
    }

    final segmentBytes = segmentDurationSec * bytesPerSecond;
    final overlapBytes = overlapSec * bytesPerSecond;
    final stepBytes = segmentBytes - overlapBytes;

    final segments = <AudioSegment>[];
    final raf = await wavFile.open(mode: FileMode.read);

    try {
      int offset = 44; // Start right after WAV header
      int segIndex = 0;

      while (offset < fileSize) {
        final remainingBytes = fileSize - offset;
        final thisSegPcmBytes = remainingBytes < segmentBytes ? remainingBytes : segmentBytes;
        if (thisSegPcmBytes <= 0) break;

        await raf.setPosition(offset);
        final pcmChunk = await raf.read(thisSegPcmBytes);

        // Prepend valid WAV header
        final segHeader = buildWavHeader(pcmChunk.length);
        final segPath = '${outputDir.path}/seg_$segIndex.wav';
        final segFile = File(segPath);
        final segRaf = await segFile.open(mode: FileMode.write);
        await segRaf.writeFrom(segHeader);
        await segRaf.writeFrom(pcmChunk);
        await segRaf.close();

        final startMs = (((offset - 44) / bytesPerSecond) * 1000).round();
        final endMs = startMs + ((pcmChunk.length / bytesPerSecond) * 1000).round();

        segments.add(AudioSegment(
          index: segIndex,
          filePath: segPath,
          startMs: startMs,
          endMs: endMs,
        ));

        segIndex++;
        offset += stepBytes;
      }
    } finally {
      await raf.close();
    }

    return segments;
  }

  /// Stitches transcribed segments together in order.
  /// If a segment failed permanently, inserts a placeholder marker `[part X not transcribed]`.
  String stitchTranscripts(List<Map<String, dynamic>> segments) {
    if (segments.isEmpty) return '';

    final sorted = List<Map<String, dynamic>>.from(segments)
      ..sort((a, b) => ((a['segment_index'] as num?)?.toInt() ?? 0)
          .compareTo((b['segment_index'] as num?)?.toInt() ?? 0));

    final buffer = StringBuffer();
    for (int i = 0; i < sorted.length; i++) {
      final seg = sorted[i];
      final status = seg['status']?.toString().toLowerCase() ?? 'pending';
      final text = (seg['transcript'] as String?)?.trim() ?? '';
      final partNum = i + 1;

      if (status == 'done' && text.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(text);
      } else if (status == 'failed') {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write('[part $partNum not transcribed]\n');
      }
    }

    return buffer.toString().trim();
  }
}

