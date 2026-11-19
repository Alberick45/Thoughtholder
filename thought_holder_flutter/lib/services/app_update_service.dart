import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../background_recording_service.dart';
import '../config/update_config.dart';
import '../database_helper.dart';
import '../settings_service.dart';
import '../utils/app_logger.dart';
import 'backup_service.dart';

enum UpdateStage {
  idle,
  waitingForVoiceCapture,
  backingUp,
  downloading,
  verifying,
  readyToInstall,
  installing,
  failed,
  canceled,
}

class UpdateProgress {
  final UpdateStage stage;
  final double downloadFraction; // 0.0 to 1.0
  final int downloadedBytes;
  final int totalBytes;
  final String statusMessage;
  final String? backupSummary;
  final String? errorMessage;

  const UpdateProgress({
    required this.stage,
    this.downloadFraction = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    required this.statusMessage,
    this.backupSummary,
    this.errorMessage,
  });

  String get formattedDownloadStats {
    if (totalBytes <= 0) return '${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    final doneMb = (downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
    final totalMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
    final pct = (downloadFraction * 100).toInt();
    return '$pct% ($doneMb / $totalMb MB)';
  }
}

class AppInstalledVersion {
  final String versionName;
  final int buildNumber;

  const AppInstalledVersion({
    required this.versionName,
    required this.buildNumber,
  });
}

class AppUpdateService extends ChangeNotifier {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const MethodChannel _updaterChannel =
      MethodChannel('com.thoughtholder.app/updater');

  // Hardcoded baseline version as safe fallback
  static const String fallbackVersion = '1.2.0';
  static const int fallbackBuild = 3;

  AppInstalledVersion? _cachedVersion;
  VersionManifest? _latestManifest;
  UpdateProgress _progress = const UpdateProgress(
    stage: UpdateStage.idle,
    statusMessage: 'Ready',
  );
  bool _isCancelled = false;
  http.Client? _activeClient;

  UpdateProgress get progress => _progress;
  VersionManifest? get latestManifest => _latestManifest;

  /// Retrieves the running app version and build number.
  Future<AppInstalledVersion> getInstalledVersion() async {
    if (_cachedVersion != null) return _cachedVersion!;

    String vName = fallbackVersion;
    int bNum = fallbackBuild;

    // Check Android native channel
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _updaterChannel.invokeMethod<Map>('getAppVersion');
        if (res != null) {
          vName = res['versionName'] as String? ?? fallbackVersion;
          bNum = (res['versionCode'] as num?)?.toInt() ?? fallbackBuild;
        }
      } catch (e) {
        AppLogger.info('AppUpdateService', 'Native Android version fetch: $e');
      }
    }

    _cachedVersion = AppInstalledVersion(versionName: vName, buildNumber: bNum);
    return _cachedVersion!;
  }

  /// Checks whether an update check is safe to show (no ongoing voice recording/transcription).
  bool isVoiceCaptureActive(BackgroundRecordingService recordingService) {
    return recordingService.isRecording || recordingService.isTranscribing;
  }

  /// Fetches the latest release manifest from GitHub Releases.
  Future<VersionManifest?> checkForUpdates({
    required SettingsService settings,
    bool manual = false,
  }) async {
    // If not manual, enforce max once per 24h
    if (!manual) {
      final lastCheck = settings.lastUpdateCheckTime;
      if (lastCheck != null) {
        final diff = DateTime.now().difference(lastCheck);
        if (diff.inHours < 24) {
          AppLogger.info('AppUpdateService', 'Update check skipped (checked ${diff.inHours}h ago)');
          return null;
        }
      }
    }

    final url = settings.betaUpdatesEnabled
        ? UpdateConfig.betaManifestUrl
        : UpdateConfig.stableManifestUrl;

    try {
      AppLogger.info('AppUpdateService', 'Fetching update manifest from $url');
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      await settings.setLastUpdateCheckTime(DateTime.now());

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        _latestManifest = VersionManifest.fromJson(data);
        return _latestManifest;
      } else {
        AppLogger.info('AppUpdateService', 'Update manifest returned HTTP ${resp.statusCode}');
      }
    } catch (e) {
      AppLogger.error('AppUpdateService', 'Error checking for updates: $e');
      if (manual) rethrow;
    }
    return null;
  }

  /// Evaluates whether an update is available and should be presented.
  Future<bool> isUpdateAvailable({
    required VersionManifest manifest,
    required SettingsService settings,
    bool ignoreSkipped = false,
  }) async {
    final installed = await getInstalledVersion();
    if (manifest.build <= installed.buildNumber) {
      return false;
    }

    // If update is required (below minSupportedBuild), cannot skip
    if (installed.buildNumber < manifest.minSupportedBuild) {
      return true;
    }

    if (!ignoreSkipped && settings.skippedBuild == manifest.build) {
      return false;
    }

    return true;
  }

  /// Checks if installed build is below the minimum required build.
  Future<bool> isUpdateRequired(VersionManifest manifest) async {
    final installed = await getInstalledVersion();
    return installed.buildNumber < manifest.minSupportedBuild;
  }

  /// Cancels any in-flight download or installation.
  void cancelUpdate() {
    _isCancelled = true;
    _activeClient?.close();
    _progress = const UpdateProgress(
      stage: UpdateStage.canceled,
      statusMessage: 'Update canceled',
    );
    notifyListeners();
  }

  /// Main update pipeline:
  /// 1. Wait for any active voice note recording/transcription to finish.
  /// 2. Create complete safe pre-update backup (DB + pending audio).
  /// 3. Download update artifact with streaming progress.
  /// 4. Verify SHA-256 checksum.
  /// 5. Trigger platform installer and restart.
  Future<void> startUpdate({
    required VersionManifest manifest,
    required SettingsService settings,
    required BackgroundRecordingService recordingService,
  }) async {
    _isCancelled = false;

    // STEP 1: Wait for ongoing recording or transcription
    if (isVoiceCaptureActive(recordingService)) {
      _progress = const UpdateProgress(
        stage: UpdateStage.waitingForVoiceCapture,
        statusMessage: 'Waiting for voice note to be saved and transcribed…',
      );
      notifyListeners();

      while (isVoiceCaptureActive(recordingService)) {
        if (_isCancelled) return;
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // STEP 2: Backup
    _progress = const UpdateProgress(
      stage: UpdateStage.backingUp,
      statusMessage: 'Backing up thoughts and voice recordings…',
    );
    notifyListeners();

    String backupSummary = 'Backup completed';
    try {
      final backup = await BackupService.instance.createBackup();
      await settings.setLastBackupDate(backup.createdAt);

      // Count voice recordings
      int voiceCount = 0;
      try {
        final recs = await DatabaseHelper.instance.fetchAllVoiceRecordings();
        voiceCount = recs.length;
      } catch (_) {}

      backupSummary = '${backup.ideaCount} thoughts and $voiceCount voice recordings saved';
      _progress = UpdateProgress(
        stage: UpdateStage.backingUp,
        statusMessage: 'Backup completed',
        backupSummary: backupSummary,
      );
      notifyListeners();
    } catch (e) {
      AppLogger.error('AppUpdateService', 'Pre-update backup failed: $e');
      _progress = UpdateProgress(
        stage: UpdateStage.failed,
        statusMessage: 'Backup failed',
        errorMessage: 'Could not create a safety backup: $e. Update aborted for your safety.',
      );
      notifyListeners();
      return;
    }

    if (_isCancelled) return;

    // STEP 3: Determine platform asset
    PlatformReleaseAsset? targetAsset;
    String targetFileName = '';
    if (Platform.isAndroid) {
      targetAsset = manifest.android;
      targetFileName = 'thoughtholder-${manifest.version}.apk';
    } else if (Platform.isWindows) {
      targetAsset = manifest.windows;
      targetFileName = 'thoughtholder-setup-${manifest.version}.exe';
    }

    if (targetAsset == null || targetAsset.url.isEmpty) {
      _progress = const UpdateProgress(
        stage: UpdateStage.failed,
        statusMessage: 'Release file unavailable',
        errorMessage: 'No download package found for this device platform.',
      );
      notifyListeners();
      return;
    }

    // STEP 4: Download with progress
    _progress = UpdateProgress(
      stage: UpdateStage.downloading,
      statusMessage: 'Starting download…',
      backupSummary: backupSummary,
    );
    notifyListeners();

    File downloadFile;
    try {
      final tempDir = await getTemporaryDirectory();
      downloadFile = File(p.join(tempDir.path, targetFileName));
      if (await downloadFile.exists()) {
        await downloadFile.delete();
      }

      _activeClient = http.Client();
      final req = http.Request('GET', Uri.parse(targetAsset.url));
      final streamedResponse = await _activeClient!.send(req);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Download failed with HTTP ${streamedResponse.statusCode}');
      }

      final contentLength = streamedResponse.contentLength ?? 0;
      int received = 0;

      final sink = downloadFile.openWrite();
      await for (final chunk in streamedResponse.stream) {
        if (_isCancelled) {
          await sink.close();
          if (await downloadFile.exists()) await downloadFile.delete();
          return;
        }
        sink.add(chunk);
        received += chunk.length;

        final fraction = contentLength > 0 ? (received / contentLength).clamp(0.0, 1.0) : 0.0;
        _progress = UpdateProgress(
          stage: UpdateStage.downloading,
          downloadFraction: fraction,
          downloadedBytes: received,
          totalBytes: contentLength,
          statusMessage: 'Downloading update…',
          backupSummary: backupSummary,
        );
        notifyListeners();
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      AppLogger.error('AppUpdateService', 'Download error: $e');
      _progress = UpdateProgress(
        stage: UpdateStage.failed,
        statusMessage: 'Download failed',
        backupSummary: backupSummary,
        errorMessage: 'Network error downloading update: $e',
      );
      notifyListeners();
      return;
    } finally {
      _activeClient = null;
    }

    if (_isCancelled) return;

    // STEP 5: SHA-256 verification
    _progress = UpdateProgress(
      stage: UpdateStage.verifying,
      statusMessage: 'Checking the file is safe…',
      backupSummary: backupSummary,
    );
    notifyListeners();

    try {
      final bytes = await downloadFile.readAsBytes();
      final digest = sha256.convert(bytes);
      final computedHash = digest.toString().toLowerCase();
      final expectedHash = targetAsset.sha256.toLowerCase();

      AppLogger.info('AppUpdateService', 'Downloaded SHA: $computedHash, Expected: $expectedHash');

      if (expectedHash.isNotEmpty && computedHash != expectedHash) {
        if (await downloadFile.exists()) await downloadFile.delete();
        _progress = UpdateProgress(
          stage: UpdateStage.failed,
          statusMessage: 'Integrity check failed',
          backupSummary: backupSummary,
          errorMessage: 'Checksum mismatch. The download was corrupted or incomplete. File has been safely deleted.',
        );
        notifyListeners();
        return;
      }
    } catch (e) {
      _progress = UpdateProgress(
        stage: UpdateStage.failed,
        statusMessage: 'Safety check failed',
        backupSummary: backupSummary,
        errorMessage: 'Could not verify file integrity: $e',
      );
      notifyListeners();
      return;
    }

    if (_isCancelled) return;

    // STEP 6: Install and restart
    _progress = UpdateProgress(
      stage: UpdateStage.readyToInstall,
      statusMessage: 'Installing and restarting…',
      backupSummary: backupSummary,
    );
    notifyListeners();

    try {
      if (Platform.isAndroid) {
        // Android install via FileProvider
        final canInstall = await _updaterChannel.invokeMethod<bool>('canRequestPackageInstalls') ?? true;
        if (!canInstall) {
          await _updaterChannel.invokeMethod('openInstallPermissionSettings');
        }
        await _updaterChannel.invokeMethod('installApk', {'filePath': downloadFile.path});
      } else if (Platform.isWindows) {
        // Windows silent install and close app
        await Process.start(
          downloadFile.path,
          ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
          mode: ProcessStartMode.detached,
        );
        // Terminate app immediately so installer can replace binaries smoothly
        exit(0);
      }
    } catch (e) {
      AppLogger.error('AppUpdateService', 'Install launch failed: $e');
      _progress = UpdateProgress(
        stage: UpdateStage.failed,
        statusMessage: 'Install failed',
        backupSummary: backupSummary,
        errorMessage: 'Could not launch installer: $e',
      );
      notifyListeners();
    }
  }
}

