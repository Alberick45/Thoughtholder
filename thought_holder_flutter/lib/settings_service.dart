import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'secure_storage_service.dart';
import 'services/ble_security_guard.dart';
import 'utils/app_logger.dart';

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
    await _loadAndMigrateGroqKey();
    BleSecurityGuard.instance.configurePersistence(
      counterLookup: getDeviceLastSeenCounter,
      persistCounter: setDeviceLastSeenCounter,
    );
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
            if (key.isNotEmpty && _cachedGroqApiKey.isEmpty) {
              final sec = await SecureStorageService.getGroqApiKey();
              if (sec == null || sec.isEmpty) {
                await SecureStorageService.saveGroqApiKey(key);
                _cachedGroqApiKey = key;
              }
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

  // --- Main Pin Settings: 'shuffle' or 'choose' ---
  String get mainPinMode => _box.get('main_pin_mode', defaultValue: 'shuffle') as String;

  Future<void> setMainPinMode(String value) async {
    await _box.put('main_pin_mode', value);
    notifyListeners();
  }

  String? get dailyShufflePickDate => _box.get('main_shuffle_pick_date') as String?;
  String? get dailyShufflePickId => _box.get('main_shuffle_pick_id') as String?;

  Future<void> setDailyShufflePick(String date, String thoughtId) async {
    await _box.put('main_shuffle_pick_date', date);
    await _box.put('main_shuffle_pick_id', thoughtId);
    notifyListeners();
  }

  String? get chosenMainPinId => _box.get('chosen_main_pin_id') as String?;

  Future<void> setChosenMainPinId(String id) async {
    await _box.put('chosen_main_pin_id', id);
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

  // --- Sound Settings (Section 2) ---
  bool get soundPromptAnswered => _box.get('sound_prompt_answered', defaultValue: false);

  Future<void> setSoundPromptAnswered(bool value) async {
    await _box.put('sound_prompt_answered', value);
    notifyListeners();
  }

  bool get soundsEnabled => _box.get('sounds_enabled', defaultValue: false);

  Future<void> setSoundsEnabled(bool value) async {
    await _box.put('sounds_enabled', value);
    notifyListeners();
  }

  double get soundVolume => (_box.get('sound_volume', defaultValue: 0.40) as num).toDouble();

  Future<void> setSoundVolume(double value) async {
    final clamped = value.clamp(0.0, 0.80);
    await _box.put('sound_volume', clamped);
    notifyListeners();
  }

  bool get soundGroupTaps => _box.get('sound_group_taps', defaultValue: true);

  Future<void> setSoundGroupTaps(bool value) async {
    await _box.put('sound_group_taps', value);
    notifyListeners();
  }

  bool get soundGroupSwipes => _box.get('sound_group_swipes', defaultValue: true);

  Future<void> setSoundGroupSwipes(bool value) async {
    await _box.put('sound_group_swipes', value);
    notifyListeners();
  }

  bool get soundGroupSaving => _box.get('sound_group_saving', defaultValue: true);

  Future<void> setSoundGroupSaving(bool value) async {
    await _box.put('sound_group_saving', value);
    notifyListeners();
  }

  bool get soundGroupDeleting => _box.get('sound_group_deleting', defaultValue: true);

  Future<void> setSoundGroupDeleting(bool value) async {
    await _box.put('sound_group_deleting', value);
    notifyListeners();
  }

  bool get soundGroupTyping => _box.get('sound_group_typing', defaultValue: false);

  Future<void> setSoundGroupTyping(bool value) async {
    await _box.put('sound_group_typing', value);
    notifyListeners();
  }

  String get soundStyle => _box.get('sound_style', defaultValue: 'soft');

  Future<void> setSoundStyle(String value) async {
    await _box.put('sound_style', value);
    notifyListeners();
  }

  // --- Gesture Settings ---
  bool get swipeSortedUnsorted => _box.get('swipe_sorted_unsorted', defaultValue: true);

  Future<void> setSwipeSortedUnsorted(bool value) async {
    await _box.put('swipe_sorted_unsorted', value);
    notifyListeners();
  }

  bool get swipeCaptureStream => _box.get('swipe_capture_stream', defaultValue: true);

  Future<void> setSwipeCaptureStream(bool value) async {
    await _box.put('swipe_capture_stream', value);
    notifyListeners();
  }

  bool get swipeActionsOnIdeas => _box.get('swipe_actions_on_ideas', defaultValue: false);

  Future<void> setSwipeActionsOnIdeas(bool value) async {
    await _box.put('swipe_actions_on_ideas', value);
    notifyListeners();
  }

  String get swipeDistance => _box.get('swipe_distance', defaultValue: 'Normal');

  Future<void> setSwipeDistance(String value) async {
    await _box.put('swipe_distance', value);
    notifyListeners();
  }

  double get swipeThresholdFraction {
    switch (swipeDistance) {
      case 'Easy':
        return 0.20;
      case 'Firm':
        return 0.45;
      case 'Normal':
      default:
        return 0.30;
    }
  }

  /// Days to retain voice note audio after successful transcription (default 7 days).
  int get audioRetentionDays => _box.get('audio_retention_days', defaultValue: 7) as int;

  Future<void> setAudioRetentionDays(int days) async {
    await _box.put('audio_retention_days', days);
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

  String _cachedGroqApiKey = '';
  bool _groqKeyMigrated = false;
  bool _groqTestSucceeded = false;
  String? _groqMigrationStatus;

  bool get isGroqKeyInSecureStorage => _cachedGroqApiKey.isNotEmpty;
  bool get hasLegacyGroqKeyInSettings =>
      (_box.get('groq_api_key', defaultValue: '') as String).trim().isNotEmpty;
  bool get groqKeyMigrated => _groqKeyMigrated;
  bool get groqTestSucceeded => _groqTestSucceeded;
  String? get groqMigrationStatus => _groqMigrationStatus;

  Future<void> _loadAndMigrateGroqKey() async {
    try {
      // 1. Try reading directly from OS SecureStorage
      final secureKey = await SecureStorageService.getGroqApiKey();
      if (secureKey != null && secureKey.trim().isNotEmpty) {
        _cachedGroqApiKey = secureKey.trim();
        _groqMigrationStatus = 'Loaded from OS Secure Storage';
        if (_box.containsKey('groq_api_key')) {
          await _box.delete('groq_api_key');
        }
        AppLogger.info('SettingsService', 'Groq key loaded from SecureStorage');
        return;
      }

      // 2. Check for legacy key in plain Hive settings
      final legacyKey = (_box.get('groq_api_key', defaultValue: '') as String).trim();
      if (legacyKey.isNotEmpty) {
        // Step A: write to secure storage
        await SecureStorageService.saveGroqApiKey(legacyKey);
        // Step B: read back and compare byte-for-byte
        final verifiedKey = await SecureStorageService.getGroqApiKey();
        if (verifiedKey == legacyKey) {
          _cachedGroqApiKey = verifiedKey!;
          _groqKeyMigrated = true;
          // Step C: Test connection ping
          final testOk = await testGroqKey(verifiedKey);
          _groqTestSucceeded = testOk;
          _groqMigrationStatus = testOk
              ? 'Migrated to OS secure storage (byte match & live ping OK)'
              : 'Migrated to OS secure storage (byte match OK)';
          AppLogger.info('SettingsService', 'Groq key migrated to SecureStorage and verified match');
          // Step D: Purge plaintext copy from Hive settings file now that user approved
          await _box.delete('groq_api_key');
        } else {
          _groqMigrationStatus = 'Secure storage read-back failed verification';
          AppLogger.error('SettingsService', 'Groq key read-back did not match legacy key');
        }
      }
    } catch (e) {
      _groqMigrationStatus = 'Exception during secure storage migration';
      AppLogger.error('SettingsService', 'Exception migrating Groq key', e);
    }
  }

  String get groqApiKey {
    const fromEnv = String.fromEnvironment('GROQ_KEY');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (_cachedGroqApiKey.isNotEmpty) return _cachedGroqApiKey;
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
    final trimmed = key.trim();
    _cachedGroqApiKey = trimmed;
    await SecureStorageService.saveGroqApiKey(trimmed);
    if (_box.containsKey('groq_api_key')) {
      await _box.delete('groq_api_key');
    }
    notifyListeners();
  }

  // --- History view preferences ---
  bool get historyGridView => _box.get('history_grid_view', defaultValue: true) as bool;

  Future<void> setHistoryGridView(bool value) async {
    await _box.put('history_grid_view', value);
    notifyListeners();
  }

  /// Clears the key from both OS secure storage and legacy plain settings.
  Future<void> removeGroqApiKey() async {
    _cachedGroqApiKey = '';
    _groqMigrationStatus = null;
    _groqTestSucceeded = false;
    _groqKeyMigrated = false;
    await SecureStorageService.deleteGroqApiKey();
    await _box.delete('groq_api_key');
    notifyListeners();
  }

  /// Removes the legacy plaintext key copy from Hive settings file.
  /// To be executed ONLY upon user's explicit confirmation.
  Future<void> purgeLegacyGroqKeyFromSettings() async {
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

  /// Retrieves the persisted last-seen replay counter for [senderId].
  int getDeviceLastSeenCounter(String senderId) {
    final raw = _box.get('ble_last_seen_counters', defaultValue: <dynamic, dynamic>{});
    if (raw is Map && raw.containsKey(senderId)) {
      return (raw[senderId] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  /// Persists the last-seen replay counter for [senderId] to disk.
  Future<void> setDeviceLastSeenCounter(String senderId, int counter) async {
    final raw = _box.get('ble_last_seen_counters', defaultValue: <dynamic, dynamic>{});
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    map[senderId] = counter;
    await _box.put('ble_last_seen_counters', map);
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

  // --- In-App Updates & Backup Settings ---

  DateTime? get lastBackupDate {
    final ms = _box.get('last_backup_timestamp') as int?;
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  Future<void> setLastBackupDate(DateTime dt) async {
    await _box.put('last_backup_timestamp', dt.millisecondsSinceEpoch);
    notifyListeners();
  }

  bool get hasOfferedRawDefaultRecovery =>
      _box.get('raw_default_recovery_offered_v133', defaultValue: false) as bool;

  Future<void> setHasOfferedRawDefaultRecovery(bool value) async {
    await _box.put('raw_default_recovery_offered_v133', value);
    notifyListeners();
  }

  String get lastDailyGoalCelebratedDate =>
      _box.get('last_daily_goal_celebrated_date', defaultValue: '') as String;

  Future<void> setLastDailyGoalCelebratedDate(String value) async {
    await _box.put('last_daily_goal_celebrated_date', value);
    notifyListeners();
  }

  bool get hapticsEnabled => _box.get('haptics_enabled', defaultValue: true) as bool;

  Future<void> setHapticsEnabled(bool value) async {
    await _box.put('haptics_enabled', value);
    notifyListeners();
  }

  bool get reduceAnimations =>
      _box.get('reduce_animations', defaultValue: false) as bool;

  Future<void> setReduceAnimations(bool value) async {
    await _box.put('reduce_animations', value);
    notifyListeners();
  }

  bool get betaUpdatesEnabled => _box.get('beta_updates_enabled', defaultValue: false) as bool;

  Future<void> setBetaUpdatesEnabled(bool value) async {
    await _box.put('beta_updates_enabled', value);
    notifyListeners();
  }

  int get skippedBuild => _box.get('skipped_update_build', defaultValue: 0) as int;

  Future<void> setSkippedBuild(int build) async {
    await _box.put('skipped_update_build', build);
    notifyListeners();
  }

  String? get skippedVersion {
    final v = _box.get('skipped_update_version') as String?;
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  Future<void> setSkippedVersion(String version) async {
    await _box.put('skipped_update_version', version.trim());
    notifyListeners();
  }

  Future<void> clearSkippedUpdate() async {
    await _box.delete('skipped_update_build');
    await _box.delete('skipped_update_version');
    notifyListeners();
  }

  bool get hasSkippedUpdate =>
      skippedBuild > 0 || (skippedVersion != null && skippedVersion!.isNotEmpty);

  DateTime? get lastUpdateCheckTime {
    final ms = _box.get('last_update_check_time') as int?;
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  Future<void> setLastUpdateCheckTime(DateTime dt) async {
    await _box.put('last_update_check_time', dt.millisecondsSinceEpoch);
  }

  Box get box => _box;
}

