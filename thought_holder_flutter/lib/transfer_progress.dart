enum TransferStatus {
  idle,
  connecting,
  negotiatingMtu,
  sending,
  receiving,
  completed,
  failed,
}

class TransferProgress {
  final TransferStatus status;
  final double progress; // 0.0 to 1.0
  final int bytesTransferred;
  final int totalBytes;
  final double speedBytesPerSec; // transfer speed in bytes per second
  final String? error;
  final String? deviceName; // peer device name

  TransferProgress({
    required this.status,
    required this.progress,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.speedBytesPerSec,
    this.error,
    this.deviceName,
  });

  factory TransferProgress.idle() => TransferProgress(
        status: TransferStatus.idle,
        progress: 0.0,
        bytesTransferred: 0,
        totalBytes: 0,
        speedBytesPerSec: 0.0,
      );
}
