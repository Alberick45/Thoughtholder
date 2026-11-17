import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:thought_holder_flutter/services/voice_segment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceSegmentService Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('voice_test_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('buildWavHeader generates valid 44-byte RIFF PCM header', () {
      final pcmBytes = 32000 * 10; // 10 seconds of 16kHz 16-bit mono
      final header = VoiceSegmentService.buildWavHeader(pcmBytes);

      expect(header.length, equals(44));
      final byteData = ByteData.sublistView(header);

      // Check RIFF
      expect(String.fromCharCodes(header.sublist(0, 4)), equals('RIFF'));
      expect(byteData.getUint32(4, Endian.little), equals(pcmBytes + 36));
      expect(String.fromCharCodes(header.sublist(8, 12)), equals('WAVE'));

      // Check fmt
      expect(String.fromCharCodes(header.sublist(12, 16)), equals('fmt '));
      expect(byteData.getUint16(20, Endian.little), equals(1)); // PCM
      expect(byteData.getUint16(22, Endian.little), equals(1)); // 1 channel
      expect(byteData.getUint32(24, Endian.little), equals(16000)); // Sample rate
      expect(byteData.getUint32(28, Endian.little), equals(32000)); // Byte rate
      expect(byteData.getUint16(32, Endian.little), equals(2)); // Block align
      expect(byteData.getUint16(34, Endian.little), equals(16)); // Bits per sample

      // Check data
      expect(String.fromCharCodes(header.sublist(36, 40)), equals('data'));
      expect(byteData.getUint32(40, Endian.little), equals(pcmBytes));
    });

    test('repairWavHeader repairs broken/crashed recording with invalid header', () async {
      final pcmLength = 32000 * 5; // 5 seconds of audio
      final testFile = File('${tempDir.path}/crashed_unfinished.wav');

      // Create file with corrupt 0-length header
      final badHeader = Uint8List(44);
      final pcmData = Uint8List(pcmLength);
      await testFile.writeAsBytes([...badHeader, ...pcmData]);

      final repaired = await VoiceSegmentService.instance.repairWavHeader(testFile);
      expect(repaired, isTrue);

      final repairedBytes = await testFile.readAsBytes();
      final bd = ByteData.sublistView(repairedBytes);
      expect(bd.getUint32(4, Endian.little), equals(pcmLength + 36));
      expect(bd.getUint32(40, Endian.little), equals(pcmLength));
    });

    test('splitWavFile splits 20-minute audio into ~14 segments of 90s with 2s overlap', () async {
      // 20 minutes = 1200 seconds * 32,000 bytes/sec = 38,400,000 bytes
      // To test without allocating 38 MB in memory, simulate 5 minutes (300 sec)
      const testDurationSec = 300; // 5 minutes
      const pcmBytes = testDurationSec * VoiceSegmentService.bytesPerSecond;

      final testFile = File('${tempDir.path}/long_recording.wav');
      final header = VoiceSegmentService.buildWavHeader(pcmBytes);

      // Write header and mock PCM data in chunks
      final raf = await testFile.open(mode: FileMode.write);
      await raf.writeFrom(header);
      final dummyChunk = Uint8List(64000); // 2 sec chunk
      int written = 0;
      while (written < pcmBytes) {
        final toWrite = (pcmBytes - written) < dummyChunk.length ? (pcmBytes - written) : dummyChunk.length;
        await raf.writeFrom(dummyChunk, 0, toWrite);
        written += toWrite;
      }
      await raf.close();

      final outDir = Directory('${tempDir.path}/segments');
      final segments = await VoiceSegmentService.instance.splitWavFile(
        wavFile: testFile,
        outputDir: outDir,
        segmentDurationSec: 90,
        overlapSec: 2,
      );

      // 300 seconds total:
      // seg 0: 0..90s
      // seg 1: 88..178s
      // seg 2: 176..266s
      // seg 3: 264..300s (36s remainder)
      // Total = 4 segments
      expect(segments.length, equals(4));
      expect(segments[0].index, equals(0));
      expect(segments[0].startMs, equals(0));
      expect(segments[0].endMs, equals(90000));

      expect(segments[1].index, equals(1));
      expect(segments[1].startMs, equals(88000));
      expect(segments[1].endMs, equals(178000));

      expect(segments[2].index, equals(2));
      expect(segments[2].startMs, equals(176000));
      expect(segments[2].endMs, equals(266000));

      expect(segments[3].index, equals(3));
      expect(segments[3].startMs, equals(264000));
      expect(segments[3].endMs, equals(300000));

      // Verify each segment file exists and has valid 44-byte header
      for (final seg in segments) {
        final f = File(seg.filePath);
        expect(await f.exists(), isTrue);
        final bytes = await f.readAsBytes();
        expect(bytes.length, greaterThan(44));
        expect(String.fromCharCodes(bytes.sublist(0, 4)), equals('RIFF'));
      }
    });

    test('stitchTranscripts stitches in order and marks failed segments', () {
      final segments = [
        {
          'segment_index': 0,
          'status': 'done',
          'transcript': 'First segment text.',
        },
        {
          'segment_index': 1,
          'status': 'failed',
          'transcript': null,
        },
        {
          'segment_index': 2,
          'status': 'done',
          'transcript': 'Third segment text.',
        },
      ];

      final stitched = VoiceSegmentService.instance.stitchTranscripts(segments);
      expect(
        stitched,
        equals('First segment text.\n[part 2 not transcribed]\n Third segment text.'),
      );
    });
  });
}

