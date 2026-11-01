import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'secure_storage_service.dart';

/// Service to persist and manage application settings using Hive.
class SettingsService extends ChangeNotifier {
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
    await _tryLoadFromEnvFile();
    await scrubNearbyDevices();
    await _loadSecureKeys();
  }

  Future<void> _tryLoadFromEnvFile() async {
    try {
      final envFile = File('.env');
      if (await envFile.exists()) {
        final lines = await envFile.readAsLines();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('GROQ_KEY=')) {
            final key = trimmed.substring('GROQ_KEY='.length).trim();
            final currentKey = _box.get('groq_api_key', defaultValue: '') as String;
            if (key.isNotEmpty && currentKey.isEmpty) {
              await _box.put('groq_api_key', key);
            }
          }
          if (trimmed.startsWith('WHISPER_PROMPT=')) {
            final prompt = trimmed.substring('WHISPER_PROMPT='.length).trim();
            final currentPrompt = _box.get('whisper_prompt', defaultValue: '') as String;
            if (prompt.isNotEmpty && currentPrompt.isEmpty) {
              await _box.put('whisper_prompt', prompt);
            }
          }
        }
      }
    } catch (_) {}
  }

  // --- Theme Selection: 'dark', 'light', 'calm' ---
  String get theme => _box.get('app_theme', defaultValue: 'dark');

  Future<void> setTheme(String value) async {
    await _box.put('app_theme', value);
    notifyListeners();
  }

  // --- Bucket Order: 'ideas' (most ideas first) or 'creation' (creation order) ---
  String get bucketOrder => _box.get('bucket_order', defaultValue: 'ideas');

  Future<void> setBucketOrder(String value) async {
    await _box.put('bucket_order', value);
    notifyListeners();
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
    notifyListeners();
  }

  /// Check if auto-receive (advertise BLE server when app is open) is active.
  bool get autoReceive => _box.get('auto_receive', defaultValue: false);

  Future<void> setAutoReceive(bool value) async {
    await _box.put('auto_receive', value);
    notifyListeners();
  }

  /// Check if Google Drive Backup is enabled.
  bool get googleDriveBackup => _box.get('google_drive_backup', defaultValue: false);

  Future<void> setGoogleDriveBackup(bool value) async {
    await _box.put('google_drive_backup', value);
    notifyListeners();
  }

  /// Google account linked email for backups.
  String get googleAccountEmail => _box.get('google_account_email', defaultValue: '');

  Future<void> setGoogleAccountEmail(String email) async {
    await _box.put('google_account_email', email);
    notifyListeners();
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
    notifyListeners();
  }

  /// Launch app automatically at system startup (Desktop).
  bool get launchAtStartup => _box.get('launch_at_startup', defaultValue: false);

  Future<void> setLaunchAtStartup(bool value) async {
    await _box.put('launch_at_startup', value);
    notifyListeners();
  }

  /// Whether closing window minimizes/hides to system tray instead of exiting.
  bool get closeToTray => _box.get('close_to_tray', defaultValue: true);

  Future<void> setCloseToTray(bool value) async {
    await _box.put('close_to_tray', value);
    notifyListeners();
  }

  /// Continuous speech dictation (auto-restarts session on silence/short pauses).
  bool get speechContinuous => _box.get('speech_continuous', defaultValue: true);

  Future<void> setSpeechContinuous(bool value) async {
    await _box.put('speech_continuous', value);
    notifyListeners();
  }

  /// Use online speech recognition engine when available.
  bool get speechOnline => _box.get('speech_online', defaultValue: true);

  Future<void> setSpeechOnline(bool value) async {
    await _box.put('speech_online', value);
    notifyListeners();
  }

  // --- Groq Whisper AI Settings ---
  static const String defaultGroqKey = String.fromEnvironment('GROQ_KEY', defaultValue: '');
  static const String defaultWhisperPrompt = 'Albert, PK, Aaenics, UMaT, Tarkwa, Ghana';

  String get groqApiKey {
    const fromEnv = String.fromEnvironment('GROQ_KEY');
    if (fromEnv.isNotEmpty) return fromEnv;
    return _box.get('groq_api_key', defaultValue: defaultGroqKey);
  }

  bool get hasGroqKey => groqApiKey.trim().isNotEmpty;

  String get maskedGroqApiKey {
    final key = groqApiKey.trim();
    if (key.isEmpty) return '';
    if (key.length <= 8) return 'gsk_••••';
    return 'gsk_••••${key.substring(key.length - 4)}';
  }

  Future<void> setGroqApiKey(String key) async {
    await _box.put('groq_api_key', key.trim());
    notifyListeners();
  }

  // --- History view preferences ---
  bool get historyGridView => _box.get('history_grid_view', defaultValue: true) as bool;

  Future<void> setHistoryGridView(bool value) async {
    await _box.put('history_grid_view', value);
    notifyListeners();
  }

  Future<void> removeGroqApiKey() async {
    await _box.delete('groq_api_key');
    notifyListeners();
  }

  /// Test Groq API key with a fast validation ping
  Future<bool> testGroqKey(String key) async {
    final trimmed = key.trim();
    if (!trimmed.startsWith('gsk_')) return false;
    try {
      final res = await http.get(
        Uri.parse('https://api.groq.com/openai/v1/models'),
        headers: {'Authorization': 'Bearer $trimmed'},
      ).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String get whisperPrompt =>
      _box.get('whisper_prompt', defaultValue: defaultWhisperPrompt);

  Future<void> setWhisperPrompt(String prompt) async {
    await _box.put('whisper_prompt', prompt.trim());
    notifyListeners();
  }

  bool get useWhisperAsPrimary =>
      _box.get('use_whisper_primary', defaultValue: true);

  Future<void> setUseWhisperAsPrimary(bool val) async {
    await _box.put('use_whisper_primary', val);
    notifyListeners();
  }

  // ==========================================================================
  // UPDATE 4: BACKGROUND RECORDING SETTINGS
  // ==========================================================================
  bool get hasSeenBatteryOptimizationTip =>
      _box.get('has_seen_battery_tip', defaultValue: false);

  Future<void> setSeenBatteryOptimizationTip() async {
    await _box.put('has_seen_battery_tip', true);
    notifyListeners();
  }

  bool get hasSeenRecordingPrivacyNotice =>
      _box.get('has_seen_recording_privacy', defaultValue: false);

  Future<void> setSeenRecordingPrivacyNotice() async {
    await _box.put('has_seen_recording_privacy', true);
    notifyListeners();
  }

  // ==========================================================================
  // UPDATE 5: NOTIFICATIONS & NUDGES SETTINGS
  // ==========================================================================
  // C. Quick-Capture Notification (default off)
  bool get quickCaptureNotification =>
      _box.get('quick_capture_notification', defaultValue: false);

  Future<void> setQuickCaptureNotification(bool value) async {
    await _box.put('quick_capture_notification', value);
    notifyListeners();
  }

  // D. "Start here" Nudges
  // 'off', 'once', 'twice', 'thrice'
  String get startHereFrequency =>
      _box.get('start_here_frequency', defaultValue: 'off');

  Future<void> setStartHereFrequency(String value) async {
    await _box.put('start_here_frequency', value);
    notifyListeners();
  }

  List<String> get startHereTimes => List<String>.from(
      _box.get('start_here_times', defaultValue: ['09:00', '14:00', '19:00']));

  Future<void> setStartHereTimes(List<String> times) async {
    await _box.put('start_here_times', times);
    notifyListeners();
  }

  // Privacy: Show my idea’s words on the lock screen (default false)
  bool get showWordsOnLockScreen =>
      _box.get('show_words_on_lock_screen', defaultValue: false);

  Future<void> setShowWordsOnLockScreen(bool value) async {
    await _box.put('show_words_on_lock_screen', value);
    notifyListeners();
  }

  // Tap behaviour: 'idea' or 'capture' (default 'idea')
  String get startHereTapTarget =>
      _box.get('start_here_tap_target', defaultValue: 'idea');

  Future<void> setStartHereTapTarget(String value) async {
    await _box.put('start_here_tap_target', value);
    notifyListeners();
  }

  // Skippable onboarding prompt: "Want a nudge to tell you what to start with?"
  bool get hasSeenStartHereOnboardingPrompt =>
      _box.get('has_seen_start_here_prompt', defaultValue: false);

  Future<void> setSeenStartHereOnboardingPrompt() async {
    await _box.put('has_seen_start_here_prompt', true);
    notifyListeners();
  }

  // E. Gentle Capture Reminders
  // 'off', 'once', 'twice', 'thrice'
  String get captureReminderFrequency =>
      _box.get('capture_reminder_frequency', defaultValue: 'off');

  Future<void> setCaptureReminderFrequency(String value) async {
    await _box.put('capture_reminder_frequency', value);
    notifyListeners();
  }

  List<String> get captureReminderTimes => List<String>.from(
      _box.get('capture_reminder_times', defaultValue: ['11:00', '16:00', '20:00']));

  Future<void> setCaptureReminderTimes(List<String> times) async {
    await _box.put('capture_reminder_times', times);
    notifyListeners();
  }

  // Shared Quiet Hours (default 21:00 to 08:00)
  String get quietHoursStart =>
      _box.get('quiet_hours_start', defaultValue: '21:00');

  String get quietHoursEnd =>
      _box.get('quiet_hours_end', defaultValue: '08:00');

  Future<void> setQuietHours(String start, String end) async {
    await _box.put('quiet_hours_start', start);
    await _box.put('quiet_hours_end', end);
    notifyListeners();
  }

  // User App Activity & Nudge Limits tracking
  int get lastAppActiveTime =>
      _box.get('last_app_active_time', defaultValue: 0);

  Future<void> recordAppActiveTime() async {
    await _box.put('last_app_active_time', DateTime.now().millisecondsSinceEpoch);
  }

  int get nudgesSentTodayCount {
    final today = _todayDateString();
    return _box.get('nudges_count_$today', defaultValue: 0);
  }

  Future<void> incrementNudgesSentToday() async {
    final today = _todayDateString();
    final count = nudgesSentTodayCount;
    await _box.put('nudges_count_$today', count + 1);
  }

  // --- UPDATE 6: Unsorted Order (Section A) ---
  // 'newest' (default) or 'oldest'
  String get unsortedOrder =>
      _box.get('unsorted_order', defaultValue: 'newest') as String;

  Future<void> setUnsortedOrder(String value) async {
    await _box.put('unsorted_order', value);
    notifyListeners();
  }

  // --- UPDATE 6: Starter Buckets First-Run Choice (Section B & D) ---
  bool get hasChosenStarterBuckets =>
      _box.get('has_chosen_starter_buckets', defaultValue: false) as bool;

  Future<void> setHasChosenStarterBuckets(bool value) async {
    await _box.put('has_chosen_starter_buckets', value);
    notifyListeners();
  }

  // --- UPDATE 6: Bucket Split Dismissal (Section C) ---
  bool isBucketSplitDismissed(String bucketName) {
    final list = _box.get('dismissed_split_buckets', defaultValue: <dynamic>[]) as List;
    final lower = bucketName.trim().toLowerCase();
    return list.map((e) => e.toString().trim().toLowerCase()).contains(lower);
  }

  Future<void> dismissBucketSplit(String bucketName) async {
    final list = List<String>.from(
      (_box.get('dismissed_split_buckets', defaultValue: <dynamic>[]) as List)
          .map((e) => e.toString()),
    );
    final lower = bucketName.trim().toLowerCase();
    if (!list.map((e) => e.trim().toLowerCase()).contains(lower)) {
      list.add(bucketName.trim());
      await _box.put('dismissed_split_buckets', list);
      notifyListeners();
    }
  }

  // --- UPDATE 7: Device Identity & BLE Merge Sync (Sections 2, 5, 7) ---
  String get deviceId => _box.get('device_id', defaultValue: '') as String;
  Future<void> setDeviceId(String id) async {
    await _box.put('device_id', id);
    notifyListeners();
  }

  final Map<String, String> _secureKeysCache = {};

  /// Removes any legacy or unverified "Nearby Device" entries from storage.
  Future<void> scrubNearbyDevices() async {
    final map = getPairedDevices();
    final keysToRemove = <String>[];
    for (final entry in map.entries) {
      final dev = entry.value;
      if (dev is Map) {
        final name = (dev['name'] as String? ?? '').trim();
        final verified = dev['verified'] == true;
        // Scrub if it has name "Nearby Device", empty name, or unverified legacy entry
        if (name == 'Nearby Device' || name.isEmpty || !verified) {
          keysToRemove.add(entry.key);
        }
      } else {
        keysToRemove.add(entry.key);
      }
    }
    if (keysToRemove.isNotEmpty) {
      for (final k in keysToRemove) {
        map.remove(k);
        _secureKeysCache.remove(k);
        try {
          await SecureStorageService.deleteSharedKey(k);
        } catch (_) {}
      }
      await _box.put('paired_devices_map', map);
      notifyListeners();
    }
  }

  Future<void> _loadSecureKeys() async {
    final map = getPairedDevices();
    bool migratedAny = false;
    for (final entry in map.entries) {
      final devId = entry.key;
      final dev = entry.value;
      try {
        final sec = await SecureStorageService.getSharedKey(devId);
        if (sec != null && sec.isNotEmpty) {
          _secureKeysCache[devId] = sec;
        } else if (dev is Map && dev['sharedKey'] != null) {
          final legacyKey = dev['sharedKey'] as String;
          if (legacyKey.isNotEmpty) {
            await SecureStorageService.saveSharedKey(devId, legacyKey);
            _secureKeysCache[devId] = legacyKey;
            dev.remove('sharedKey');
            migratedAny = true;
          }
        }
      } catch (_) {}
    }
    if (migratedAny) {
      await _box.put('paired_devices_map', map);
    }
  }

  Map<String, dynamic> getPairedDevices() {
    final raw = _box.get('paired_devices_map', defaultValue: <dynamic, dynamic>{});
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v is Map ? Map<String, dynamic>.from(v) : v));
    }
    return {};
  }

  Future<void> savePairedDevice(String peerDeviceId, String peerName, String sharedKey, {int? lastSync}) async {
    final map = getPairedDevices();
    try {
      await SecureStorageService.saveSharedKey(peerDeviceId, sharedKey);
    } catch (_) {}
    _secureKeysCache[peerDeviceId] = sharedKey;

    map[peerDeviceId] = {
      'deviceId': peerDeviceId,
      'name': peerName,
      'lastSync': lastSync,
      'verified': true,
      'pairedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _box.put('paired_devices_map', map);
    notifyListeners();
  }

  Future<void> updateDeviceLastSync(String peerDeviceId, int timestamp) async {
    final map = getPairedDevices();
    if (map.containsKey(peerDeviceId)) {
      final dev = Map<String, dynamic>.from(map[peerDeviceId] as Map);
      dev['lastSync'] = timestamp;
      map[peerDeviceId] = dev;
      await _box.put('paired_devices_map', map);
      await _box.put('global_last_sync_time', timestamp);
      await _box.put('global_last_sync_device', dev['name'] ?? peerDeviceId);
      notifyListeners();
    }
  }

  Future<void> removePairedDevice(String peerDeviceId) async {
    final map = getPairedDevices();
    map.remove(peerDeviceId);
    _secureKeysCache.remove(peerDeviceId);
    try {
      await SecureStorageService.deleteSharedKey(peerDeviceId);
    } catch (_) {}
    await _box.put('paired_devices_map', map);
    notifyListeners();
  }

  bool isDevicePaired(String peerDeviceId) {
    final map = getPairedDevices();
    return map.containsKey(peerDeviceId);
  }

  String? getDeviceSharedKey(String peerDeviceId) {
    if (_secureKeysCache.containsKey(peerDeviceId)) {
      return _secureKeysCache[peerDeviceId];
    }
    final map = getPairedDevices();
    if (map.containsKey(peerDeviceId)) {
      return (map[peerDeviceId] as Map)['sharedKey'] as String?;
    }
    return null;
  }

  String? getLastSyncInfo() {
    final time = _box.get('global_last_sync_time') as int?;
    final dev = _box.get('global_last_sync_device') as String?;
    if (time == null || dev == null) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(time);
    final formattedTime = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$dev, $formattedTime';
  }

  int getLastSyncRevision(String peerDeviceId) {
    return _box.get('last_sync_rev_$peerDeviceId', defaultValue: 0) as int;
  }

  Future<void> setLastSyncRevision(String peerDeviceId, int revision) async {
    await _box.put('last_sync_rev_$peerDeviceId', revision);
  }

  String _todayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

