import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'app_theme.dart';

/// QR scanner widget for phone (Android/iOS) and Mac only.
/// NEVER instantiated or built on Windows.
class QrScannerWidget extends StatefulWidget {
  final ValueChanged<String> onScanned;
  final VoidCallback onCancel;

  const QrScannerWidget({
    super.key,
    required this.onScanned,
    required this.onCancel,
  });

  @override
  State<QrScannerWidget> createState() => _QrScannerWidgetState();
}

class _QrScannerWidgetState extends State<QrScannerWidget> {
  MobileScannerController? _controller;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    // Safety check: Never initialize scanner on Windows
    if (!kIsWeb && !Platform.isWindows) {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows || _controller == null) {
      return Center(
        child: Text(
          'Camera scanning is not supported on Windows. Please use Compare numbers.',
          textAlign: TextAlign.center,
          style: appFont(color: Colors.white70, fontSize: 14),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller!,
            onDetect: (capture) {
              if (_scanned) return;
              final barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final raw = barcode.rawValue;
                if (raw != null && raw.isNotEmpty) {
                  _scanned = true;
                  widget.onScanned(raw);
                  break;
                }
              }
            },
          ),
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFC59B27), width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          Positioned(
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(180),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Point camera at the other device’s QR code',
                style: appFont(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
