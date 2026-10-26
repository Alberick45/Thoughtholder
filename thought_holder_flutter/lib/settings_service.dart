import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Service to persist and manage application settings using Hive.
class SettingsService {
  static const String _boxName = 'app_settings';
  late Box _box;

  Future<void> init() async {
    try {
      _box = await Hive.openBox(_boxName);
    } catch (_) {
      // Another instance may be holding the lock file.
      // Fall back to a temporary in-memory box so the app still launches.
      _box = await Hive.openBox('${_boxName}_temp');
    }
  }

  /// Get the local device name (defaults to system hostname).
  String get deviceName {
    try {
      return _box.get('device_name', defaultValue: Platform.localHostname);
    } catch (_) {
      return _box.get('device_name', defaultValue: 'QuickLink Device');
    }
  }

  Future<void> setDeviceName(String name) async {
    await _box.put('device_name', name);
  }

  /// Check if auto-receive (advertise BLE server when app is open) is active.
  bool get autoReceive => _box.get('auto_receive', defaultValue: false);

  Future<void> setAutoReceive(bool value) async {
    await _box.put('auto_receive', value);
  }

  /// Check if Google Drive Backup is enabled.
  bool get googleDriveBackup => _box.get('google_drive_backup', defaultValue: false);

  Future<void> setGoogleDriveBackup(bool value) async {
    await _box.put('google_drive_backup', value);
  }

  /// Google account linked email for backups.
  String get googleAccountEmail => _box.get('google_account_email', defaultValue: '');

  Future<void> setGoogleAccountEmail(String email) async {
    await _box.put('google_account_email', email);
  }

  /// Get download folder path (defaults to standard downloads folder or document folder).
  Future<String> get downloadPath async {
    final stored = _box.get('download_path');
    if (stored != null && stored is String && stored.isNotEmpty) {
      return stored;
    }
    
    String defaultPath = '';
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final dir = await getDownloadsDirectory();
        if (dir != null) {
          defaultPath = dir.path;
        }
      }
    } catch (_) {}

    if (defaultPath.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      defaultPath = dir.path;
    }
    return defaultPath;
  }

  Future<void> setDownloadPath(String path) async {
    await _box.put('download_path', path);
  }

  /// Launch app automatically at system startup (Desktop).
  bool get launchAtStartup => _box.get('launch_at_startup', defaultValue: false);

  Future<void> setLaunchAtStartup(bool value) async {
    await _box.put('launch_at_startup', value);
  }

  /// Whether closing window minimizes/hides to system tray instead of exiting.
  bool get closeToTray => _box.get('close_to_tray', defaultValue: true);

  Future<void> setCloseToTray(bool value) async {
    await _box.put('close_to_tray', value);
  }

  /// Continuous speech dictation (auto-restarts session on silence/short pauses).
  bool get speechContinuous => _box.get('speech_continuous', defaultValue: true);

  Future<void> setSpeechContinuous(bool value) async {
    await _box.put('speech_continuous', value);
  }

  /// Use online speech recognition engine when available.
  bool get speechOnline => _box.get('speech_online', defaultValue: true);

  Future<void> setSpeechOnline(bool value) async {
    await _box.put('speech_online', value);
  }
}

