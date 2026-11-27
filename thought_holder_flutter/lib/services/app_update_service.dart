import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
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

enum UpdateCheckFailureKind { timeout, dns, http, badJson, network }

class UpdateCheckException implements Exception {
  final UpdateCheckFailureKind kind;
  final String message;
  final String manifestUrl;
  final int? statusCode;

  const UpdateCheckException({
    required this.kind,
    required this.message,
    required this.manifestUrl,
    this.statusCode,
  });

  String get userMessage {
    switch (kind) {
      case UpdateCheckFailureKind.timeout:
        return 'Update check timed out contacting release server.';
      case UpdateCheckFailureKind.dns:
        return 'Could not resolve release server (DNS/network). Check your connection.';
      case UpdateCheckFailureKind.http:
        return 'Release server returned HTTP ${statusCode ?? 'error'} for version manifest.';
      case UpdateCheckFailureKind.badJson:
        return 'Release manifest was invalid or unreadable JSON.';
      case UpdateCheckFailureKind.network:
        return 'Network error while checking for updates.';
    }
  }

  @override
  String toString() => 'UpdateCheckException($kind, $message, url=$manifestUrl, status=$statusCode)';
}

class AppUpdateService extends ChangeNotifier {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const MethodChannel _updaterChannel =
      MethodChannel('com.thoughtholder.app/updater');

  // Hardcoded baseline version as safe fallback
  static const String fallbackVersion = '1.2.0';
  static const int fallbackBuild = 3;
  static const String _pendingUpdateTargetVersionKey = 'pending_update_target_version';
  static const String _pendingUpdateTargetBuildKey = 'pending_update_target_build';
  static const String _lastInstalledVersionKey = 'last_installed_version_seen';

  AppInstalledVersion? _cachedVersion;
  VersionManifest? _latestManifest;
  UpdateProgress _progress = const UpdateProgress(
    stage: UpdateStage.idle,
    statusMessage: 'Ready',
  );
  bool _isCancelled = false;
  http.Client? _activeClient;
  String? _lastCheckNote;

  UpdateProgress get progress => _progress;
  VersionManifest? get latestManifest => _latestManifest;
  String? get lastCheckNote => _lastCheckNote;

  static List<int> _parseSemVer(String version) {
    var v = version.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    final core = v.split(RegExp(r'[-+]')).first;
    final parts = core.split('.');
    final nums = <int>[];
    for (var i = 0; i < 3; i++) {
      final raw = i < parts.length ? parts[i] : '0';
      final match = RegExp(r'^\d+').firstMatch(raw);
      nums.add(int.tryParse(match?.group(0) ?? '0') ?? 0);
    }
    return nums;
  }

  /// Returns positive if a>b, negative if a<b, 0 if equal (semver core only).
  static int compareSemVer(String a, String b) {
    final pa = _parseSemVer(a);
    final pb = _parseSemVer(b);
    for (var i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
    }
    return 0;
  }

  Future<void> _logUpdateCheck(String line) async {
    final ts = DateTime.now().toIso8601String();
    final msg = '[$ts] $line';
    AppLogger.info('AppUpdateService', line);
    try {
      Directory dir;
      try {
        dir = await getApplicationSupportDirectory();
      } catch (_) {
        dir = await getTemporaryDirectory();
      }
      final file = File(p.join(dir.path, 'update-check.log'));
      await file.writeAsString('$msg\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// Retrieves the running app version and build number.
  Future<AppInstalledVersion> getInstalledVersion() async {
    if (_cachedVersion != null) return _cachedVersion!;

    String vName = fallbackVersion;
    int bNum = fallbackBuild;

    try {
      final info = await PackageInfo.fromPlatform();
      final parsedName = info.version.trim();
      final parsedBuild = int.tryParse(info.buildNumber.trim());
      if (parsedName.isNotEmpty) vName = parsedName;
      if (parsedBuild != null && parsedBuild > 0) bNum = parsedBuild;
    } catch (e) {
      AppLogger.info('AppUpdateService', 'PackageInfo version fetch: $e');
      // Android fallback channel
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final res = await _updaterChannel.invokeMethod<Map>('getAppVersion');
          if (res != null) {
            vName = res['versionName'] as String? ?? fallbackVersion;
            bNum = (res['versionCode'] as num?)?.toInt() ?? fallbackBuild;
          }
        } catch (_) {}
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
  /// Returns null only for automatic cooldown-suppressed checks (manual=false, checked <24h ago).
  /// Throws [UpdateCheckException] for real failures (timeout, DNS, bad JSON, network),
  /// except beta 404 which falls back to stable with a non-error note.
  Future<VersionManifest?> checkForUpdates({
    required SettingsService settings,
    bool manual = false,
  }) async {
    _lastCheckNote = null;
    // If not manual, enforce max once per 24h
    if (!manual) {
      final lastCheck = settings.lastUpdateCheckTime;
      if (lastCheck != null) {
        final diff = DateTime.now().difference(lastCheck);
        if (diff.inHours < 24) {
          await _logUpdateCheck('auto check skipped: cooldown (${diff.inHours}h ago)');
          return null; // cooldown: automatic only
        }
      }
    }

    final betaEnabled = settings.betaUpdatesEnabled;
    final primaryUrl = betaEnabled ? UpdateConfig.betaManifestUrl : UpdateConfig.stableManifestUrl;
    await _logUpdateCheck('manifest request: GET $primaryUrl (manual=$manual, beta=$betaEnabled)');

    VersionManifest primary;
    try {
      primary = await _fetchManifestFromUrl(primaryUrl);
      await _logUpdateCheck('manifest selected: $primaryUrl (version=${primary.version}, build=${primary.build})');
    } on UpdateCheckException catch (e) {
      if (betaEnabled && e.kind == UpdateCheckFailureKind.http && e.statusCode == 404) {
        await _logUpdateCheck('beta manifest missing (HTTP 404): $primaryUrl; falling back to ${UpdateConfig.stableManifestUrl}');
        final stable = await _fetchManifestFromUrl(UpdateConfig.stableManifestUrl);
        _lastCheckNote = 'No beta release published, using stable';
        await _logUpdateCheck('manifest selected: ${UpdateConfig.stableManifestUrl} (fallback from beta 404, version=${stable.version}, build=${stable.build})');
        _latestManifest = stable;
        await settings.setLastUpdateCheckTime(DateTime.now());
        return stable;
      }
      rethrow;
    }

    if (betaEnabled) {
      try {
        final stable = await _fetchManifestFromUrl(UpdateConfig.stableManifestUrl);
        final cmp = compareSemVer(stable.version, primary.version);
        final stableNewer = cmp > 0 || (cmp == 0 && stable.build > primary.build);
        if (stableNewer) {
          await _logUpdateCheck('manifest selected: ${UpdateConfig.stableManifestUrl} (stable newer than beta ${primary.version}/${primary.build})');
          primary = stable;
        }
      } catch (e) {
        await _logUpdateCheck('stable comparison fetch failed after beta success: $e');
      }
    }

    _latestManifest = primary;
    await settings.setLastUpdateCheckTime(DateTime.now());
    return primary;
  }

  Future<VersionManifest> _fetchManifestFromUrl(String url) async {
    http.Response resp;
    try {
      resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
    } on TimeoutException catch (e) {
      await _logUpdateCheck('manifest timeout: $url ($e)');
      throw UpdateCheckException(
        kind: UpdateCheckFailureKind.timeout,
        message: e.toString(),
        manifestUrl: url,
      );
    } on SocketException catch (e) {
      final lower = e.toString().toLowerCase();
      final kind = lower.contains('failed host lookup') || lower.contains('no such host')
          ? UpdateCheckFailureKind.dns
          : UpdateCheckFailureKind.network;
      await _logUpdateCheck('manifest socket error ($kind): $url ($e)');
      throw UpdateCheckException(
        kind: kind,
        message: e.toString(),
        manifestUrl: url,
      );
    } catch (e) {
      await _logUpdateCheck('manifest network error: $url ($e)');
      throw UpdateCheckException(
        kind: UpdateCheckFailureKind.network,
        message: e.toString(),
        manifestUrl: url,
      );
    }

    await _logUpdateCheck('manifest response: HTTP ${resp.statusCode} from $url');

    if (resp.statusCode != 200) {
      throw UpdateCheckException(
        kind: UpdateCheckFailureKind.http,
        message: 'HTTP ${resp.statusCode}',
        manifestUrl: url,
        statusCode: resp.statusCode,
      );
    }

    try {
      final decoded = json.decode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('manifest root is not a JSON object');
      }
      final manifest = VersionManifest.fromJson(decoded);
      if (manifest.version.trim().isEmpty) {
        throw const FormatException('manifest version is empty');
      }
      return manifest;
    } catch (e) {
      await _logUpdateCheck('manifest bad JSON: $url ($e)');
      throw UpdateCheckException(
        kind: UpdateCheckFailureKind.badJson,
        message: e.toString(),
        manifestUrl: url,
      );
    }
  }

  Future<String?> checkPostUpdateOutcome(SettingsService settings) async {
    final installed = await getInstalledVersion();
    final box = settings.box;
    final seen = box.get(_lastInstalledVersionKey)?.toString();
    final current = '${installed.versionName}+${installed.buildNumber}';
    final pendingVersion = box.get(_pendingUpdateTargetVersionKey)?.toString();
    final pendingBuild = box.get(_pendingUpdateTargetBuildKey);
    String? message;

    if (pendingVersion != null && pendingVersion.isNotEmpty) {
      final changed = seen != null && seen != current;
      if (changed || installed.versionName == pendingVersion) {
        message = 'Updated to v${installed.versionName}';
        await _appendWindowsUpdateLog('Post-update: success. installed=$current pending=$pendingVersion+${pendingBuild ?? ''}');
      } else {
        message = 'Update did not install. See log';
        await _appendWindowsUpdateLog('Post-update: version unchanged. installed=$current pending=$pendingVersion+${pendingBuild ?? ''} seen=$seen');
      }
      await box.delete(_pendingUpdateTargetVersionKey);
      await box.delete(_pendingUpdateTargetBuildKey);
    }

    await box.put(_lastInstalledVersionKey, current);
    return message;
  }

  String get windowsUpdateLogPath {
    final tempDir = Platform.environment['TEMP'] ?? Directory.systemTemp.path;
    return p.join(tempDir, 'thoughtholder-update.log');
  }

  String get windowsInstallerLogPath {
    final tempDir = Platform.environment['TEMP'] ?? Directory.systemTemp.path;
    return p.join(tempDir, 'thoughtholder-installer.log');
  }

  Future<void> _appendWindowsUpdateLog(String line) async {
    try {
      final ts = DateTime.now().toIso8601String();
      final file = File(windowsUpdateLogPath);
      await file.writeAsString('[$ts] $line\n', mode: FileMode.append, flush: true);
      AppLogger.info('AppUpdateService', line);
    } catch (_) {}
  }

  /// Evaluates whether an update is available and should be presented.
  /// Semver is compared first (1.10.0 > 1.9.0); build number breaks ties for same version.
  Future<bool> isUpdateAvailable({
    required VersionManifest manifest,
    required SettingsService settings,
    bool ignoreSkipped = false,
  }) async {
    final installed = await getInstalledVersion();

    // Required updates cannot be skipped
    if (installed.buildNumber < manifest.minSupportedBuild) {
      return true;
    }

    final versionCmp = compareSemVer(manifest.version, installed.versionName);
    final isNewer = versionCmp > 0 ||
        (versionCmp == 0 && manifest.build > installed.buildNumber);
    if (!isNewer) return false;

    if (!ignoreSkipped) {
      final skippedVersion = settings.skippedVersion?.trim() ?? '';
      if (skippedVersion.isNotEmpty && skippedVersion == manifest.version.trim()) {
        return false;
      }
      if (settings.skippedBuild == manifest.build) {
        return false;
      }
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
        statusMessage: 'Waiting for voice note to be saved and transcribed...',
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
      statusMessage: 'Backing up thoughts and voice recordings...',
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
      statusMessage: 'Starting download...',
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
          statusMessage: 'Downloading update...',
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
      statusMessage: 'Checking the file is safe...',
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
      statusMessage: 'Installing update... ThoughtHolder will reopen',
      backupSummary: backupSummary,
    );
    notifyListeners();
    await _logUpdateCheck('installing update: ${manifest.version}+${manifest.build}, target=${downloadFile.path}');

    try {
      final box = settings.box;
      await box.put(_pendingUpdateTargetVersionKey, manifest.version);
      await box.put(_pendingUpdateTargetBuildKey, manifest.build);
      if (Platform.isAndroid) {
        final canInstall = await _updaterChannel.invokeMethod<bool>('canRequestPackageInstalls') ?? true;
        if (!canInstall) {
          await _updaterChannel.invokeMethod('openInstallPermissionSettings');
        }
        await _updaterChannel.invokeMethod('installApk', {'filePath': downloadFile.path});
      } else if (Platform.isWindows) {
        final installerLog = windowsInstallerLogPath;
        final args = [
          '/SILENT',
          '/SUPPRESSMSGBOXES',
          '/CLOSEAPPLICATIONS',
          '/RESTARTAPPLICATIONS',
          '/LOG="$installerLog"',
        ];
        await _appendWindowsUpdateLog('Launching installer: ${downloadFile.path}');
        await _appendWindowsUpdateLog('Installer args: ${args.join(' ')}');
        await _appendWindowsUpdateLog('Installer log: $installerLog');

        final launched = await Process.start(
          'cmd',
          ['/c', 'start', '', downloadFile.path, ...args],
          mode: ProcessStartMode.detached,
        );
        await _appendWindowsUpdateLog('Detached launcher started: pid=${launched.pid}');
        await Future.delayed(const Duration(seconds: 2));
        await _appendWindowsUpdateLog('Exiting app for installer handoff');
        exit(0);
      }
    } catch (e, st) {
      await _appendWindowsUpdateLog('Install launch failed: $e\n$st');
      AppLogger.error('AppUpdateService', 'Install launch failed: $e');
      _progress = UpdateProgress(
        stage: UpdateStage.failed,
        statusMessage: 'Install failed',
        backupSummary: backupSummary,
        errorMessage: 'Could not launch installer: $e\nLog: ${windowsUpdateLogPath}',
      );
      notifyListeners();
    }
  }
}

